-- Test vectors for arock-log.tokens, the one tokenizer recall uses: each is
-- { text, tokens }, the bytes in and the tokens out, in order. Another
-- implementation (Moss's, in Elixir) is checked against this file, so it is
-- data only: strings and lists, the long ones made by string.rep and a loop.
local A64 = ("a"):rep(64)

return {
  { "", {} },
  { "   \t\n", {} },
  { "Hello, World!", { "hello", "world" } },
  { "snake_case-and.dots", { "snake", "case", "and", "dots" } },
  { "ABC_DEF", { "abc", "def" } },
  { "MiXeD123abc", { "mixed123abc" } },
  { "ls -la /home/todo.txt", { "ls", "la", "home", "todo", "txt" } },
  { "x = 1 + 2.5e10", { "x", "1", "2", "5e10" } },
  { "O'Brien's", { "o", "brien", "s" } },
  { "tab\tnew\nline\r\n", { "tab", "new", "line" } },
  { "\0abc\1def\127ghi", { "abc", "def", "ghi" } },
  { "@#$%^&*()[]{}|\\;:'\",.<>/?`~-+=", {} },
  -- bytes 0x80-0xFF are word bytes and are never folded: UTF-8 words stay whole, any case
  { "caf\195\169 \195\156n\195\175code", { "caf\195\169", "\195\156n\195\175code" } },
  { "CAF\195\137", { "caf\195\137" } },
  { "na\195\175ve\226\128\148Dash", { "na\195\175ve\226\128\148dash" } },
  { "\230\151\165\230\156\172 \227\131\134\227\130\173", { "\230\151\165\230\156\172", "\227\131\134\227\130\173" } },
  { "\255\254", { "\255\254" } },
  -- a token keeps its first 64 bytes, even when that splits a UTF-8 character
  { ("A"):rep(64), { A64 } },
  { ("Ab"):rep(40) .. " next", { ("ab"):rep(32), "next" } },
  { ("a"):rep(63) .. "\195\169", { ("a"):rep(63) .. "\195" } },
  -- a text gives at most 10,000 tokens; the rest is not read
  { ("w "):rep(10001), (function() local t = {} for i = 1, 10000 do t[i] = "w" end return t end)() },
  { ("w "):rep(9999) .. "Last stop", (function()
    local t = {}
    for i = 1, 9999 do t[i] = "w" end
    t[10000] = "last"
    return t
  end)() },
}
