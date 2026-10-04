-- A fast image model for vision checks (owner, 2026-09-28): one frame and one
-- instruction in, the model's text out. Qwen3-VL-235B-A22B-Instruct on OpenRouter by
-- default: no expiry date listed, one to three seconds per frame, and it named
-- characters drawn as empty boxes on each of three tries (the 32B is listed
-- to expire 2026-10-09).
--
--   local see = require("ports.see").new(host, { key = k, model?, service? })
--
-- service "cerebras" (owner, 2026-09-28) sends to Cerebras with reasoning off: qwen-3.8-27b there judged
-- 47 of 48 labelled claims on eval frames at 0.76 s a call, where Qwen3-VL-235B judged 44 at 1.81 s.
-- service "groq" (owner, 2026-09-30: "should work better and faster for image and vision tasks") sends to Groq's
-- Llama 4 Scout; it takes no reasoning setting.
--   see:look(frames, text) -> reply, record
--
-- frames is one PNG or a list of them in order (a sequence from one run: the
-- model reads them as successive images). Each comes as base64 text (the shell's `base64`), so no host has to
-- carry image bytes through exec; line breaks in it are dropped. The reply is
-- the model's text: the caller asks for a format and validates it (build.verdict
-- asks for Robot rows and checks them with the Robot grammar).
local call = require("ports.call")

local M = {}
local See = {}
See.__index = See

M.url = "https://openrouter.ai/api/v1/chat/completions"
M.model = "qwen/qwen3-vl-235b-a22b-instruct"
M.services = { openrouter = { url = M.url, model = M.model },
  cerebras = { url = "https://api.cerebras.ai/v1/chat/completions", model = "qwen-3.8-27b" },
  groq = { url = "https://api.groq.com/openai/v1/chat/completions", model = "meta-llama/llama-4-scout-17b-16e-instruct" } }

function M.new(host, opts)
  assert(host and host.fetch, "see needs a host with fetch")
  assert(opts and opts.key, "see needs a key")
  local service = opts.service or "openrouter"
  local s = assert(M.services[service], "see knows no service " .. tostring(service))
  return setmetatable({ host = host, key = opts.key, service = service, model = opts.model or s.model,
    url = opts.url or s.url }, See)
end

function See:look(frames, text)
  if type(frames) == "string" then frames = { frames } end
  local content = { { type = "text", text = text } }
  for _, png64 in ipairs(frames) do
    content[#content + 1] = { type = "image_url", image_url = { url = "data:image/png;base64," .. png64:gsub("%s+", "") } }
  end
  local payload = { model = self.model, max_tokens = 400, messages = { { role = "user", content = content } } }
  if self.service == "openrouter" then payload.usage = { include = true }
  elseif self.service == "cerebras" then payload.reasoning_effort = "none" end
  local body, record = call.post(self.host, self.service, self.url, self.key, payload, 90)
  local u = body.usage or {}
  record.model = body.model or self.model
  record.cost = u.cost or require("ports.chat").cost(self.model, u)
  record.usage = { prompt = u.prompt_tokens, cached = 0, completion = u.completion_tokens }
  local choice = body.choices and body.choices[1]
  return choice and choice.message and choice.message.content or "", record
end

return M
