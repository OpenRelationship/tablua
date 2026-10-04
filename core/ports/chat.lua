-- Any OpenRouter or Cerebras chat model behind Mercury's chat shape, so a model can take
-- Mercury's place as the writer without the solver knowing.
--
--   local kimi = require("ports.chat").new(host, { key = k, model = "moonshotai/kimi-k2-thinking" })
--   local oss = require("ports.chat").new(host, { key = k, service = "cerebras", model = "gpt-oss-120b" })
--   local voice = require("ports.chat").new(host, { key = k, model = "deepseek/deepseek-v4.1-flash", thinking = false,
--                                                   sort = "latency" })
--   m:chat{ system, user | messages, max_tokens, json, reasoning_effort, on_text, tools, tool_choice, temperature }
--     -> text, record
--
-- on_text(piece, so_far), when given, asks for the reply as a stream (ports/stream.lua) and hears it as it comes,
-- so its first words can be shown before the last is written; the whole reply is still returned.
--
-- messages, when given, are the conversation as real turns ({ role = "user" | "assistant", content }) after the
-- system text, in place of one user message (with no system, messages are the whole conversation, its own system
-- turn first, as Mercury takes them). tools and tool_choice ask for tool calls, as Mercury's do: the calls come
-- back in record.tool_calls, and a reply of calls alone is an answer; opts.tool_choice, when given, is sent in
-- place of every request's (Qwen 3.8 thinking refuses "required", 2026-10-02, so a caller gives it "auto").
-- thinking = false (OpenRouter) asks the model not to reason before it answers, and reserves no reasoning tokens: for a spoken reply, where the first words must come at once.
--
-- Cerebras (owner, 2026-09-28) takes reasoning_effort as asked (Mercury's low | medium | high) and reports
-- no cost, so the record's cost comes from its listed prices per million tokens (M.prices).
--
-- A thinking model spends tokens on reasoning before it answers, so the
-- request allows opts.reasoning_tokens (default 8000) on top of max_tokens.
-- The record carries OpenRouter's own cost and the token counts in Mercury's
-- shape { prompt, cached, completion }; it never holds the key.
local call = require("ports.call")
local stream = require("ports.stream")

local M = {}
local Chat = {}
Chat.__index = Chat

M.url = "https://openrouter.ai/api/v1/chat/completions"
M.urls = { openrouter = M.url, cerebras = "https://api.cerebras.ai/v1/chat/completions" }
M.reasoning_tokens = 8000
-- USD per million tokens, input and output, as Cerebras lists them (2026-09-28).
M.prices = { ["gpt-oss-120b"] = { 0.35, 0.75 }, ["qwen-3.8-27b"] = { 0.99, 1.49 },
  ["meta-llama/llama-4-scout-17b-16e-instruct"] = { 0.11, 0.34 } }

function M.cost(model, u)
  local p = M.prices[model]
  if not p or not u.prompt_tokens then return nil end
  return (u.prompt_tokens * p[1] + (u.completion_tokens or 0) * p[2]) / 1e6
end

function M.new(host, opts)
  assert(host and host.fetch, "chat needs a host with fetch")
  assert(opts and opts.key, "chat needs a key")
  assert(opts.model, "chat needs a model")
  local service = opts.service or "openrouter"
  assert(M.urls[service], "chat knows no service " .. tostring(service))
  return setmetatable({ host = host, key = opts.key, model = opts.model, service = service,
    url = opts.url or M.urls[service],
    reasoning_tokens = opts.reasoning_tokens or (opts.thinking == false and 0 or M.reasoning_tokens), sort = opts.sort,
    thinking = opts.thinking, tool_choice = opts.tool_choice }, Chat)
end

function Chat:chat(req)
  local payload = {
    model = self.model, max_tokens = (req.max_tokens or 600) + self.reasoning_tokens,
    messages = { req.system and { role = "system", content = req.system } or nil },
    temperature = req.temperature,
  }
  if req.messages then
    for _, m in ipairs(req.messages) do payload.messages[#payload.messages + 1] = { role = m.role, content = m.content } end
  else
    payload.messages[2] = { role = "user", content = req.user }
  end
  if self.service == "openrouter" then
    payload.usage = { include = true }
    if self.sort then payload.provider = { sort = self.sort } end
    if self.thinking == false then payload.reasoning = { enabled = false } end
  else
    payload.reasoning_effort = req.reasoning_effort
  end
  if req.json then payload.response_format = { type = "json_object" } end
  if req.tools then payload.tools, payload.tool_choice = req.tools, self.tool_choice or req.tool_choice end
  local body, record
  if req.on_text then
    payload.stream = true
    local r = stream.reader(req.on_text)
    _, record = call.post(self.host, self.service, self.url, self.key, payload, 180, function(c) r:feed(c) end)
    body = { model = r.model, usage = r.usage, choices = { { message = { content = r.text }, finish_reason = r.finish } } }
  else
    body, record = call.post(self.host, self.service, self.url, self.key, payload, 180)
  end
  local u = body.usage or {}
  local details = u.prompt_tokens_details or {}
  record.model = body.model or self.model
  record.cost = u.cost or M.cost(self.model, u)
  record.usage = { prompt = u.prompt_tokens, cached = details.cached_tokens or 0, completion = u.completion_tokens }
  local choice = body.choices and body.choices[1]
  local text = choice and choice.message and choice.message.content
  if req.tools then
    record.tool_calls = choice and choice.message and choice.message.tool_calls or {}
    if #record.tool_calls > 0 then return type(text) == "string" and text or "", record end
  end
  if type(text) ~= "string" or text == "" then
    error(("%s gave no answer (finish %s)"):format(record.model, tostring(choice and choice.finish_reason)), 0)
  end
  return text, record
end

return M
