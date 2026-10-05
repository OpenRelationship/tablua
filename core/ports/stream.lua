-- A chat reply as it streams (features/messenger: a reply's first words within 1 s): the server-sent events an
-- OpenAI-shaped chat route sends when asked with `stream: true` (a proxy passes them through), read a chunk at a
-- time as the host's fetch receives them. Each piece of the reply's text is handed on as it arrives; the whole
-- reply is kept for the end. Portable Lua; the fetch that feeds it is the host's.
--
--   local r = stream.reader(on_text)    on_text(piece, so_far) for each piece of text, as it comes
--   r:feed(chunk)                       bytes as they arrive, cut anywhere (inside a line or an event)
--   r.text  r.done                      the reply so far; true once the stream said [DONE]
--   r.model  r.usage  r.finish          as the events said them (usage comes in the last, when asked for)
local json = require("ports.json")

local M = {}
local R = {}
R.__index = R

function M.reader(on_text)
  return setmetatable({ on_text = on_text or function() end, pending = "", text = "", done = false }, R)
end

-- One `data:` line: [DONE], or a chunk whose first choice's delta may carry content.
local function line(self, data)
  if data == "[DONE]" then self.done = true; return end
  local ok, event = pcall(json.decode, data)
  if not ok or type(event) ~= "table" then return end
  if type(event.model) == "string" then self.model = event.model end
  if type(event.usage) == "table" then self.usage = event.usage end
  if type(event.choices) ~= "table" or not event.choices[1] then return end
  if event.choices[1].finish_reason then self.finish = event.choices[1].finish_reason end
  local delta = event.choices[1].delta
  local piece = type(delta) == "table" and delta.content
  if type(piece) == "string" and piece ~= "" then
    self.text = self.text .. piece
    self.on_text(piece, self.text)
  end
end

function R:feed(chunk)
  self.pending = self.pending .. (chunk or ""):gsub("\r", "")
  while true do
    local nl = self.pending:find("\n", 1, true)
    if not nl then break end
    local l = self.pending:sub(1, nl - 1)
    self.pending = self.pending:sub(nl + 1)
    local data = l:match("^data:%s?(.*)$")
    if data then line(self, data) end
  end
  return self
end

return M
