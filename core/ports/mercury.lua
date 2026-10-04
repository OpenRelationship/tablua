-- The Mercury port: Inception's own API, laid out for its prompt cache.
--
--   local m = require("ports.mercury").new(host, { key = k })
--   m:fill{ context = { { path, text }, ... }, path, before, after }   -> text, record
--   m:edit{ context = { { path, text }, ... }, path, lines, first, last, diffs } -> text, record
--   m:chat{ system, user, max_tokens, json, reasoning_effort }         -> text, record
--
-- Inception caches on the start of the prompt and nothing else. So every
-- request puts what changes least first (other files, then the top of the
-- current file) and what changes most last (the text at the cursor, the edit
-- history). A fill's prompt is ordered context, then the current file up to
-- the gap; its suffix follows the gap. The record carries the usage and
-- whether the cache hit: cached_tokens of 30 or fewer is only the template.
local call = require("ports.call")

local M = {}
local Mercury = {}
Mercury.__index = Mercury

M.base = "https://api.inceptionlabs.ai/v1"
M.edit_model = "mercury-edit-2"
M.chat_model = "mercury-2.5"
M.template_tokens = 30

function M.new(host, opts)
  assert(host and host.fetch, "mercury needs a host with fetch")
  assert(opts and opts.key, "mercury needs a key")
  return setmetatable({ host = host, key = opts.key, base = opts.base or M.base }, Mercury)
end

local function post(self, path, payload)
  -- 60 s: a move filled at medium reasoning over the whole work so far can take longer than 30 (runs met timeouts)
  local body, record = call.post(self.host, "mercury", self.base .. path, self.key, payload, 60)
  local usage = body.usage or {}
  local cached = usage.prompt_tokens_details and usage.prompt_tokens_details.cached_tokens or 0
  record.model = body.model
  record.usage = { prompt = usage.prompt_tokens, completion = usage.completion_tokens, cached = cached }
  record.hit = cached > M.template_tokens
  return body, record
end

-- Other files in Mercury's own snippet tags, in the caller's order, which
-- should be the order least likely to change.
local function snippets(context)
  local out = {}
  for _, f in ipairs(context or {}) do
    out[#out + 1] = "<|recently_viewed_code_snippet|>\ncode_snippet_file_path: " .. f[1] .. "\n"
      .. f[2] .. "\n<|/recently_viewed_code_snippet|>\n"
  end
  return table.concat(out)
end

function Mercury:fill(req)
  local prompt = snippets(req.context) .. "current_file_path: " .. req.path .. "\n" .. req.before
  local body, record = post(self, "/fim/completions", {
    model = M.edit_model, prompt = prompt, suffix = req.after or "", max_tokens = req.max_tokens or 512,
  })
  return body.choices[1].text, record
end

-- lines is the current file as a list of lines; first..last is the region
-- to rewrite, which Inception wants at 10 to 25 lines. The endpoint refuses a
-- message without <|cursor|>; it goes at the start of line `cursor`, the
-- region's first line unless the caller knows better.
function Mercury:edit(req)
  local before, region, after = {}, {}, {}
  local cursor = req.cursor or req.first
  for i, line in ipairs(req.lines) do
    local into = i < req.first and before or i > req.last and after or region
    into[#into + 1] = (i == cursor and "<|cursor|>" or "") .. line
  end
  local function block(t) return #t > 0 and table.concat(t, "\n") .. "\n" or "" end
  local message = "<|recently_viewed_code_snippets|>\n" .. snippets(req.context)
    .. "<|/recently_viewed_code_snippets|>\n\n"
    .. "<|current_file_content|>\ncurrent_file_path: " .. req.path .. "\n" .. block(before)
    .. "<|code_to_edit|>\n" .. block(region) .. "<|/code_to_edit|>\n" .. block(after)
    .. "<|/current_file_content|>\n\n"
    .. "<|edit_diff_history|>\n" .. block(req.diffs or {}) .. "<|/edit_diff_history|>\n"
  local body, record = post(self, "/edit/completions", {
    model = M.edit_model, messages = { { role = "user", content = message } }, max_tokens = req.max_tokens or 1024,
  })
  local text = body.choices[1].message.content
  return (text:match("^%s*```[%w_+-]*\n(.-)\n?```%s*$") or text), record
end

-- Chat without reasoning (the slow part) unless req.reasoning_effort asks for
-- some ("low", "medium", "high"; billed as output), at the lowest temperature
-- Mercury honours (req.temperature may raise it: Inception suggests 0.6 for
-- tool calling); below 0.5 it silently resets to 1. req.messages, when given,
-- is the whole conversation in place of system and user. With req.tools
-- (OpenAI's tools[], which Inception's tool use takes, strict schemas
-- included) and req.tool_choice, the calls Mercury makes come back in the
-- record: record.tool_calls = { { id, type, ["function"] = { name, arguments } } }.
function Mercury:chat(req)
  local payload = {
    model = M.chat_model, reasoning_effort = req.reasoning_effort or "instant",
    temperature = math.max(0.5, req.temperature or 0.5), max_tokens = req.max_tokens or 600,
    messages = req.messages or { { role = "system", content = req.system }, { role = "user", content = req.user } },
  }
  if req.json then payload.response_format = { type = "json_object" } end
  if req.tools then payload.tools, payload.tool_choice = req.tools, req.tool_choice end
  local body, record = post(self, "/chat/completions", payload)
  local message = body.choices[1].message
  if req.tools then record.tool_calls = message.tool_calls or {} end
  return message.content, record
end

return M
