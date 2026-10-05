-- Text cut to fit what a model reads: the start and the end of a long text, with how much was left
-- out between them, never cut inside a UTF-8 character.
--
--   clip.clip(text, n) -> text of at most about n bytes, cut in the middle
--   clip.head(text, n) -> the start of text, at most n bytes
local M = {}

-- The start of s up to about n bytes, not ending inside a UTF-8 character; and the end, likewise.
local function head(s, n)
  while n > 0 and n < #s do
    local b = s:byte(n + 1)
    if b < 0x80 or b >= 0xC0 then break end
    n = n - 1
  end
  return s:sub(1, n)
end
local function tail(s, n)
  local i = #s - n + 1
  while i > 1 and i <= #s do
    local b = s:byte(i)
    if b < 0x80 or b >= 0xC0 then break end
    i = i + 1
  end
  return s:sub(i)
end

M.head = head

function M.clip(text, n)
  text = tostring(text or "")
  if #text <= n then return text end
  local a, b = head(text, math.floor(n * 0.7)), tail(text, math.floor(n * 0.25))
  return a .. "\n(… " .. (#text - #a - #b) .. " characters not shown …)\n" .. b
end

return M
