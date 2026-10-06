-- The terminal's world model: Qwen-AgentWorld (a language world model trained on agents' terminal sessions)
-- foreseeing the screen one more action will leave, from the session so far in its own format (term.turns). It
-- answers without its long reasoning (thinking off): 3 to 6 seconds a turn on one L40S, where thinking took 20 to 80
-- (2026-10-06), and the screen it foresees is read into the same rows as the real one (term.read, tablua.term).
--
--   local world = require("ports.agentworld").new(chat, { encoder? })
--                    chat: a ports.chat on a server serving the model; encoder: { host, url, key, model, timeout? },
--                    the same weights served as an encoder (vLLM's pooling runner, POST /v1/embeddings)
--   world:foresee(session, keys, wait) -> screen, record | nil, why
--   world:encode(session, keys, wait) -> vector, record | nil, why   the model's last hidden state at the end of the
--                    same prompt: its reading of what the action will do, as numbers (2048 for AgentWorld)
--        session = { opening, turns = { { keys, wait, screen }, ... } } (term.turns.messages)
local turns = require("term.turns")
local call = require("ports.call")
local prompt = require("term.agentworld_prompt")

local M = {}

M.temperature = 0.6   -- AgentWorldBench's

local W = {}
W.__index = W

function M.new(chat, opts)
  assert(chat and chat.chat, "agentworld needs a chat port")
  opts = opts or {}
  return setmetatable({ chat = chat, thinking = opts.thinking or false, encoder = opts.encoder }, W)
end

function W:foresee(session, keys, wait)
  local ok, text, record = pcall(self.chat.chat, self.chat, { system = prompt, messages = turns.messages(session, keys,
    wait), thinking = self.thinking, temperature = M.temperature })
  if not ok then return nil, type(text) == "table" and tostring(text.message) or tostring(text) end
  local screen = turns.observed(text)
  if not screen then return nil, "the world model foresaw no screen" end
  return screen, record
end

function W:encode(session, keys, wait)
  local e = self.encoder
  if not e then return nil, "no encoder" end
  local messages = { { role = "system", content = prompt } }
  for _, m in ipairs(turns.messages(session, keys, wait)) do messages[#messages + 1] = m end
  local ok, body, record = pcall(call.post, e.host, "agentworld-encoder", e.url, e.key,
    { model = e.model, messages = messages }, e.timeout or 20, nil, true)
  if not ok then return nil, type(body) == "table" and tostring(body.message) or tostring(body) end
  local v = body and body.data and body.data[1] and body.data[1].embedding
  if type(v) ~= "table" then return nil, "the encoder gave no vector" end
  return v, record
end

return M
