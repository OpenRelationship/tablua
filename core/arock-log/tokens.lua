-- alog.tokens(text) -> list: the words recall indexes a text by, and searches
-- a query by. Moss implements it again in Elixir for its hot path, so it is
-- specified exactly here and pinned by tokens_vectors.lua:
--
--   1. The text is bytes. A word byte is 0-9, A-Z, a-z (0x30-0x39, 0x41-0x5A,
--      0x61-0x7A) or any byte from 0x80 to 0xFF; every other byte separates
--      words. So a UTF-8 word stays whole, and so does anything joined to it
--      by a non-ASCII character (an em dash, a non-breaking space).
--   2. The tokens are the maximal runs of word bytes, in the order they occur.
--   3. Each byte A-Z becomes its lower case (+0x20); no other byte changes.
--   4. A token longer than TOKEN_BYTES (64) keeps its first 64 bytes, even if
--      that splits a UTF-8 character.
--   5. Only the first TOKENS (10,000) tokens are kept; the rest of the text is
--      not read.
--
-- It is portable Lua: an explicit byte class rather than %w, and its own
-- ASCII fold rather than string.lower (which is Unicode in tv-labs lua).
local M = {}

M.TOKEN_BYTES = 64
M.TOKENS = 10000

local WORD = "[0-9A-Za-z\128-\255]+"
local LOWER = {}
for c = 65, 90 do LOWER[string.char(c)] = string.char(c + 32) end

function M.tokens(text)
  local out, n = {}, 0
  for run in text:gmatch(WORD) do -- a loop variable is constant in Lua 5.5
    local w = run
    if #w > M.TOKEN_BYTES then w = w:sub(1, M.TOKEN_BYTES) end
    if w:find("[A-Z]") then w = (w:gsub("[A-Z]", LOWER)) end
    n = n + 1
    out[n] = w
    if n >= M.TOKENS then break end
  end
  return out
end

return M
