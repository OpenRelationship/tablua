-- The agent loop, the way pi runs it (owner, 2026-10-07; badlogic/pi-mono packages/agent/src/agent-loop.ts is the
-- guide): one model with a system prompt and tools calls tools until it answers without one, and that ends the run.
-- Its context is the transcript itself, kept whole; a hook may compact it. Tool errors go back to the model as
-- results. Steering read between turns redirects it; a follow-up queued for after it would stop starts another turn.
-- No step, token or turn cap: a run ends when the model is done, a hook ends it, the model fails, or it is aborted.
--
--   local loop = require("agent.loop")
--   local l = loop.new{ model, system, tools, before_tool?, after_tool?, finish_turn?, transform?, on?,
--                       reasoning_effort?, max_tokens? }
--   l:prompt(text | message) -> { stop, error?, messages }   stop: "stop" | "error" | "aborted" | "ended"
--   l:continue() -> the same, from the transcript as it is (its last message a user or tool turn)
--   l:steer(text | message)      read before the next reply      l:follow_up(text | message)   read when it would stop
--   l:abort()                    the run ends after the tool call in hand      l.messages   the transcript
--
-- model: a chat port (ports.chat): chat{ system, messages, tools, ... } -> text, { tool_calls, finish, reasoning,
-- usage, provider, model }. A tool: { name, description, parameters (JSON schema), execute(args, l, call) -> result,
-- prepare?(args) -> args, check?(args) -> true | nil, why }; a result { content = text, image? (PNG base64), details?,
-- is_error?, terminate? }, and a tool that raises returns its message as an error result.
-- Hooks: before_tool(call, args, l) -> { block, reason, terminate }?; after_tool(call, args, result, l) -> fields
-- that replace the result's?; finish_turn(turn, l) -> "end" | "continue" | nil, turn = { message, results };
-- transform(messages) -> messages (compaction); on(event) hears agent_start, turn_start, message (each message as
-- it joins the transcript), tool_start, tool_end, turn_end, agent_end.
-- Messages are OpenAI-shaped, as the chat port sends them: user { content }, assistant { content, tool_calls,
-- reasoning_content }, tool { tool_call_id, name, content }; the loop's own fields (is_error, details, image, stop,
-- usage) stay in the transcript and are not sent.
local json = require("ports.json")

local M = {}
local L = {}
L.__index = L

local function as_message(m) return type(m) == "table" and m or { role = "user", content = tostring(m) } end

function M.new(o)
  assert(o.model and o.model.chat, "loop needs a model with chat")
  local l = setmetatable({ o = o, messages = {}, steering = {}, following = {}, aborted = false }, L)
  l.by_name, l.declared = {}, {}
  for i, t in ipairs(o.tools or {}) do
    l.by_name[t.name] = t
    l.declared[i] = { type = "function", ["function"] = { name = t.name, description = t.description,
      parameters = t.parameters or { type = "object" } } }
  end
  return l
end

function L:steer(m) self.steering[#self.steering + 1] = as_message(m) end
function L:follow_up(m) self.following[#self.following + 1] = as_message(m) end
function L:abort() self.aborted = true end

local function emit(self, e) if self.o.on then self.o.on(e, self) end end

local function push(self, m, new)
  self.messages[#self.messages + 1] = m
  new[#new + 1] = m
  emit(self, { type = "message", message = m })
end

-- one queue's messages, all of them, the queue emptied
local function drain(q)
  local out = {}
  for i = 1, #q do out[i] = q[i] end
  for i = #q, 1, -1 do q[i] = nil end
  return out
end

-- the transcript as the provider takes it: the loop's own fields left out, and a result's image sent as a user
-- turn after the tool turns it belongs to (a tool turn carries text only)
function M.convert(messages)
  local out, images = {}, {}
  local function flush()
    if #images == 0 then return end
    local parts = { { type = "text", text = "The image" .. (#images > 1 and "s" or "") .. " from the tool results above." } }
    for _, b64 in ipairs(images) do
      parts[#parts + 1] = { type = "image_url", image_url = { url = "data:image/png;base64," .. b64 } }
    end
    out[#out + 1] = { role = "user", content = parts }
    images = {}
  end
  for _, m in ipairs(messages) do
    if m.role ~= "tool" then flush() end
    if m.role == "tool" then
      out[#out + 1] = { role = "tool", tool_call_id = m.tool_call_id, name = m.name, content = m.content }
      if m.image then images[#images + 1] = m.image end
    elseif m.role == "assistant" then
      out[#out + 1] = { role = "assistant", content = m.content or "", tool_calls = m.tool_calls,
        reasoning_content = m.reasoning_content }
    elseif m.role == "user" then
      out[#out + 1] = { role = "user", content = m.content }
    end
  end
  flush()
  return out
end

-- the model's reply as an assistant message; a failed call is one with stop = "error"
local function respond(self)
  local msgs = self.messages
  if self.o.transform then msgs = self.o.transform(msgs, self) end
  local req = { system = self.o.system, messages = M.convert(msgs), reasoning_effort = self.o.reasoning_effort,
    max_tokens = self.o.max_tokens }
  if #self.declared > 0 then req.tools, req.tool_choice = self.declared, "auto" end
  local ok, text, record = pcall(self.o.model.chat, self.o.model, req)
  if not ok then return { role = "assistant", content = "", stop = "error", error = tostring(text) } end
  local calls = record and record.tool_calls
  if calls and #calls == 0 then calls = nil end
  local stop = (record and record.finish == "length") and "length" or (calls and "tool_calls" or "stop")
  return { role = "assistant", content = text or "", tool_calls = calls, reasoning_content = record and record.reasoning,
    stop = stop, usage = record and record.usage, model = record and record.model,
    provider = record and record.provider }
end

local function result_message(call, result, is_error)
  return { role = "tool", tool_call_id = call.id, name = call["function"] and call["function"].name,
    content = type(result.content) == "string" and result.content or json.encode(result.content or ""),
    image = result.image, details = result.details, is_error = is_error or nil, terminate = result.terminate }
end

local function failed(text) return { content = text } end

-- one call through prepare, check, before_tool, execute and after_tool (agent-loop.ts prepareToolCall,
-- executePreparedToolCall, finalizeExecutedToolCall): never raises; a failure is an error result
local function run_call(self, call)
  local name = call["function"] and call["function"].name
  local tool = self.by_name[name]
  if not tool then return failed("Tool " .. tostring(name) .. " not found"), true end
  local raw = call["function"].arguments
  local ok, args = true, raw
  if type(raw) == "string" then ok, args = pcall(json.decode, raw ~= "" and raw or "{}") end
  if not ok or type(args) ~= "table" then
    return failed(("The arguments to %s are not valid JSON: %s"):format(name, tostring(raw):sub(1, 200))), true
  end
  if tool.prepare then args = tool.prepare(args) or args end
  if tool.check then
    local good, why = tool.check(args)
    if not good then return failed(tostring(why)), true end
  end
  if self.o.before_tool then
    local b = self.o.before_tool(call, args, self)
    if b and b.block then
      local r = failed(b.reason or "Tool execution was blocked")
      r.terminate = b.terminate
      return r, true
    end
  end
  local okx, result = pcall(tool.execute, args, self, call)
  local is_error
  if not okx then result, is_error = failed(tostring(result)), true
  else
    result = type(result) == "table" and result or { content = tostring(result or "") }
    is_error = result.is_error == true
  end
  if self.o.after_tool then
    local okh, patch = pcall(self.o.after_tool, call, args, result, self)
    if not okh then result, is_error = failed(tostring(patch)), true
    elseif patch then
      for k, v in pairs(patch) do result[k] = v end
      if patch.is_error ~= nil then is_error = patch.is_error end
    end
  end
  return result, is_error
end

-- the calls of one reply, in order (a comp's edits depend on the ones before); all terminating ends the run
local function run_calls(self, message, new)
  local results, terminate = {}, true
  for _, call in ipairs(message.tool_calls) do
    local name = call["function"] and call["function"].name
    emit(self, { type = "tool_start", call = call, name = name })
    local result, is_error
    if message.stop == "length" then
      result, is_error = failed(("Tool call %s was not run: the reply hit the output token limit, so its arguments may be "
        .. "cut short. Make the call again with complete arguments."):format(tostring(name))), true
    else
      result, is_error = run_call(self, call)
    end
    local m = result_message(call, result, is_error)
    emit(self, { type = "tool_end", call = call, name = name, result = m })
    push(self, m, new)
    results[#results + 1] = m
    terminate = terminate and result.terminate == true
    if self.aborted then break end
  end
  return results, #results > 0 and terminate
end

-- agent-loop.ts runLoop: an inner loop while there are calls or steering, an outer one for follow-ups
local function run(self, new, initial)
  emit(self, { type = "agent_start" })
  emit(self, { type = "turn_start" })
  for _, m in ipairs(initial or {}) do push(self, m, new) end
  local pending = drain(self.steering)
  local finished, last = false, nil
  while true do
    local more = true
    while more or #pending > 0 do
      if last then emit(self, { type = "turn_start" }) end
      for _, m in ipairs(pending) do push(self, m, new) end
      pending = {}
      local message = respond(self)
      push(self, message, new)
      last = message
      if message.stop == "error" then
        emit(self, { type = "turn_end", message = message, results = {} })
        emit(self, { type = "agent_end", messages = new })
        return { stop = "error", error = message.error, messages = new }
      end
      local results = {}
      more = false
      if message.tool_calls then
        local terminate
        results, terminate = run_calls(self, message, new)
        more = not terminate
      end
      emit(self, { type = "turn_end", message = message, results = results })
      if self.aborted then
        emit(self, { type = "agent_end", messages = new })
        return { stop = "aborted", messages = new }
      end
      local decision = self.o.finish_turn and self.o.finish_turn({ message = message, results = results }, self)
      if decision == "end" then
        emit(self, { type = "agent_end", messages = new })
        return { stop = "ended", messages = new }
      end
      finished = decision == "continue"
      pending = drain(self.steering)
      if more or #pending > 0 then finished = false end
    end
    local follow = drain(self.following)
    if #follow > 0 then pending, finished = follow, false
    elseif finished then finished = false
    else break end
  end
  emit(self, { type = "agent_end", messages = new })
  return { stop = "stop", messages = new }
end

function L:prompt(m)
  self.aborted = false
  return run(self, {}, { as_message(m) })
end

function L:continue()
  local last = self.messages[#self.messages]
  assert(last and last.role ~= "assistant", "loop: nothing to continue from (the last message is the model's)")
  self.aborted = false
  return run(self, {})
end

return M
