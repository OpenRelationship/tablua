-- Compaction, as pi does it (badlogic/pi-mono packages/coding-agent/src/core/compaction): once the transcript nears
-- the model's window, the turns before a cut are summarised by the model in a fixed checkpoint format and replaced by
-- one user turn holding the summary; the newest ~keep tokens stay as they were. Only then: a transcript kept whole
-- keeps the provider's prompt cache (pi's case against pruning tool results every turn).
--
--   compact.tokens(messages) -> n            characters over four; an image 1200 (pi: 4800 characters)
--   compact.due(messages, { window, reserve? }) -> bool     past window - reserve (16384)
--   compact.cut(messages, keep) -> i         the first message kept: a user or assistant turn, never a tool result
--   compact.run(messages, model, { keep?, render? }) -> messages, why?   keep 20000; on failure the messages as
--                                            they were; render(older, previous) -> text, when given, makes the
--                                            checkpoint from the host's records instead of asking the model
--   compact.transform(model, { window, reserve?, keep? }) -> fn(messages, l)   for agent.loop's transform hook: it
--                                            replaces l.messages when due, so the summary is made once
local json = require("ports.json")

local M = {}

M.reserve, M.keep, M.image = 16384, 20000, 1200

local function text_of(c)
  if type(c) == "string" then return c end
  local out = {}
  for _, p in ipairs(type(c) == "table" and c or {}) do if p.type == "text" then out[#out + 1] = p.text end end
  return table.concat(out, "\n")
end

function M.tokens(messages)
  local n = 0
  for _, m in ipairs(messages) do
    local chars = #text_of(m.content) + #(m.reasoning_content or "")
    for _, c in ipairs(m.tool_calls or {}) do
      chars = chars + #((c["function"] or {}).name or "") + #((c["function"] or {}).arguments or "")
    end
    local images = m.image and 1 or 0
    if type(m.content) == "table" then
      for _, p in ipairs(m.content) do if p.type == "image_url" then images = images + 1 end end
    end
    n = n + math.ceil(chars / 4) + images * M.image
  end
  return n
end

function M.due(messages, o)
  return M.tokens(messages) > o.window - (o.reserve or M.reserve)
end

function M.cut(messages, keep)
  local acc = 0
  for i = #messages, 1, -1 do
    acc = acc + M.tokens({ messages[i] })
    if acc >= keep then
      -- the nearest turn at or after i where a cut leaves no tool result without its call
      for j = i, #messages do
        if messages[j].role == "user" or messages[j].role == "assistant" then return j end
      end
      return i
    end
  end
  return 1
end

M.system = "You are a context summarization assistant. Your task is to read a conversation between a user and an AI "
  .. "assistant, then produce a structured summary following the exact format specified.\n\nDo NOT continue the "
  .. "conversation. Do NOT respond to any questions in the conversation. ONLY output the structured summary."

local FORMAT = [[
## Goal
[What is the user trying to accomplish? Can be multiple items if the session covers different tasks.]

## Constraints & Preferences
- [Any constraints, preferences, or requirements mentioned by user]
- [Or "(none)" if none were mentioned]

## Progress
### Done
- [x] [Completed tasks/changes]

### In Progress
- [ ] [Current work]

### Blocked
- [Issues preventing progress, if any]

## Key Decisions
- **[Decision]**: [Brief rationale]

## Next Steps
1. [Ordered list of what should happen next]

## Critical Context
- [Any data, examples, or references needed to continue]
- [Or "(none)" if not applicable]

Keep each section concise. Preserve exact node ids, prop names, values and error messages.]]

M.prompt = "The messages above are a conversation to summarize. Create a structured context checkpoint summary that "
  .. "another LLM will use to continue the work.\n\nUse this EXACT format:\n\n" .. FORMAT

M.update = "The messages above are NEW conversation messages to incorporate into the existing summary provided in "
  .. "<previous-summary> tags.\n\nUpdate the existing structured summary with new information. RULES:\n"
  .. "- PRESERVE all existing information from the previous summary\n- ADD new progress, decisions, and context from "
  .. "the new messages\n- UPDATE the Progress section: move items from \"In Progress\" to \"Done\" when completed\n"
  .. "- UPDATE \"Next Steps\" based on what was accomplished\n- If something is no longer relevant, you may remove it"
  .. "\n\nUse this EXACT format:\n\n" .. FORMAT

M.prefix = "The conversation history before this point was compacted into the following summary:\n\n<summary>\n"
M.suffix = "\n</summary>"

-- pi's serializeConversation: each turn as "[Role]: text", tool calls as name(args), results cut to 2000 characters
function M.serialize(messages)
  local parts = {}
  for _, m in ipairs(messages) do
    if m.role == "user" and not m.summary then
      local t = text_of(m.content)
      if t ~= "" then parts[#parts + 1] = "[User]: " .. t end
    elseif m.role == "assistant" then
      if (m.reasoning_content or "") ~= "" then parts[#parts + 1] = "[Assistant thinking]: " .. m.reasoning_content end
      if (m.content or "") ~= "" then parts[#parts + 1] = "[Assistant]: " .. text_of(m.content) end
      local calls = {}
      for _, c in ipairs(m.tool_calls or {}) do
        local f = c["function"] or {}
        local ok, args = pcall(json.decode, f.arguments or "{}")
        local shown = {}
        if ok and type(args) == "table" then
          local keys = {}
          for k in pairs(args) do keys[#keys + 1] = k end
          table.sort(keys)
          for _, k in ipairs(keys) do shown[#shown + 1] = k .. "=" .. json.encode(args[k]) end
        end
        calls[#calls + 1] = tostring(f.name) .. "(" .. table.concat(shown, ", ") .. ")"
      end
      if #calls > 0 then parts[#parts + 1] = "[Assistant tool calls]: " .. table.concat(calls, "; ") end
    elseif m.role == "tool" then
      local t = text_of(m.content)
      if t ~= "" then parts[#parts + 1] = "[Tool result]: " .. (#t > 2000 and (t:sub(1, 2000) .. "...") or t) end
    end
  end
  return table.concat(parts, "\n\n")
end

function M.run(messages, model, o)
  o = o or {}
  local cut = M.cut(messages, o.keep or M.keep)
  if cut <= 1 then return messages end
  local older, previous = {}, nil
  for i = 1, cut - 1 do
    local m = messages[i]
    if m.summary then previous = m.text else older[#older + 1] = m end
  end
  local ok, text
  if o.render then
    -- the checkpoint rendered from the host's own records (the studio's tables), exact, with no model call
    ok, text = pcall(o.render, older, previous)
  else
    local user = M.serialize(older) .. "\n\n" .. (previous and ("<previous-summary>\n" .. previous
      .. "\n</previous-summary>\n\n" .. M.update) or M.prompt)
    ok, text = pcall(model.chat, model, { system = M.system, user = user })
  end
  if not ok or type(text) ~= "string" or text == "" then
    return messages, "compaction failed: " .. tostring(ok and "an empty summary" or text)
  end
  local out = { { role = "user", content = M.prefix .. text .. M.suffix, summary = true, text = text } }
  for i = cut, #messages do out[#out + 1] = messages[i] end
  return out
end

function M.transform(model, o)
  return function(messages, l)
    if not M.due(messages, o) or #messages < 3 then return messages end
    local out = M.run(messages, model, o)
    if l then l.messages = out end
    return out
  end
end

return M
