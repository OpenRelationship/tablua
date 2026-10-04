-- arock-log.tokens against its vectors, the file another implementation is held to.
local spec = require("mono.spec")
local alog = require("arock-log")
local vectors = require("arock-log.tokens_vectors")

local function show(s) return (s:gsub("[^%w ]", function(c) return ("\\%d"):format(c:byte()) end)) end

spec.test("every vector tokenizes exactly", function()
  for i, v in ipairs(vectors) do
    local got, want = alog.tokens(v[1]), v[2]
    spec.eq(#got, #want, "vector " .. i .. " count")
    for j = 1, #want do
      if got[j] ~= want[j] then error(("vector %d token %d: %s, want %s"):format(i, j, show(got[j] or "nil"), show(want[j])), 0) end
    end
  end
end)

spec.test("a token is at most 64 bytes and a text at most 10,000 tokens", function()
  spec.eq(alog.TOKEN_BYTES, 64)
  spec.eq(alog.TOKENS, 10000)
  local got = alog.tokens(("abcdefghij"):rep(100) .. " " .. ("x "):rep(20000))
  spec.eq(#got, 10000)
  spec.eq(#got[1], 64)
end)

spec.test("tokens folds ASCII case only, whatever the host's string.lower does", function()
  spec.same(alog.tokens("\195\137T\195\137"), { "\195\137t\195\137" })
end)

spec.run()
