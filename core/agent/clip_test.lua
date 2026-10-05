-- Unit cases for agent/clip.lua: a long text keeps its start and end, says how much it left out, and never cuts a
-- UTF-8 character in two.
local spec = require("spec")
local clip = require("agent.clip")

spec.test("a short text is kept whole", function()
  spec.eq(clip.clip("abc", 10), "abc")
end)

spec.test("a long text keeps its start and its end and counts what is between", function()
  local out = clip.clip(("a"):rep(70) .. ("b"):rep(30) .. ("c"):rep(25), 100)
  spec.ok(out:find("^a+"))
  spec.ok(out:find("c+$"))
  spec.ok(out:find("characters not shown", 1, true))
end)

spec.test("a cut never falls inside a character", function()
  local s = ("é"):rep(50)   -- two bytes each
  spec.eq(#clip.head(s, 7) % 2, 0)
  spec.eq(#clip.clip(s, 20):match("^[^\n]*") % 2, 0)
end)

spec.run()
