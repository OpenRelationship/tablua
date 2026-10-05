-- Unit cases for tablua.links: what a page posts to and sends, what an action reads, which calls need a keyword of
-- the app's own, and how a call finds its keyword.
local spec = require("spec")
local links = require("tablua.links")
local src = require("tablua.source")

local function has(list, kind, source, target)
  for _, l in ipairs(list) do
    if l.kind == kind and (source == nil or l.source == source) and l.target == target then return true end
  end
  return false
end

spec.test("a Lua page posts to actions and sends fields; an action reads the fields it needs", function()
  local rows = src.decode(table.concat({
    "* Code", "#+begin_src lua",
    "function post.add(req) d:exec('insert into item (name, qty) values (?, ?)', req.form.name, req.form.qty) end",
    "#+end_src", "* Page", "#+begin_src lua",
    'return ui.form{ post = "add", ui.input{ name = "name" },',
    '  ui.button{ post = "remove", vals = { id = 3 }, "x" } }',
    "#+end_src", "" }, "\n"))
  local l = links.scan(rows)
  spec.ok(has(l, "post", nil, "post.add") and has(l, "post", nil, "post.remove"))
  spec.ok(has(l, "sends", nil, "name") and has(l, "sends", nil, "id"))
  spec.ok(has(l, "reads", "post.add", "name") and has(l, "reads", "post.add", "qty"))
end)

spec.test("a markup page's own actions are defined by it; only calls of the app's own keywords need one", function()
  local rows = src.from_files({
    markup = '{% function post.water(req) end %}\n<form post="water"><input name="plant"></form>\n',
    tests = "*** Test Cases ***\nWater\n    Open    /\n    There is a plant named Fern\n    Type    plant    Ivy\n"
      .. "    Press    Water\n    See    Fern    Ivy\n" })
  local l = links.scan(rows)
  spec.ok(has(l, "post", nil, "post.water") and has(l, "defines", nil, "post.water"))
  spec.ok(has(l, "call", "1.2", "There is a plant named Fern"))
  spec.ok(not has(l, "call", "1.1", "Open"), "the page's keywords are the computer's")
  spec.ok(has(l, "field", "1.3", "plant") and has(l, "press", "1.4", "Water"))
  spec.ok(has(l, "see", "1.5", "Fern") and not has(l, "see", "1.5", "Ivy"), "what a test typed is the person's")
end)

spec.test("a call names a keyword exactly, by embedded arguments, past a Given, or one of BuiltIn's", function()
  local kws = { "There are ${n} plants", "Add Plant" }
  spec.eq(links.keyword("there are 3 plants", kws), "There are ${n} plants")
  spec.eq(links.keyword("Given add_plant", kws), "Add Plant")
  spec.eq(links.keyword("Should Be Equal", kws), "Should Be Equal")
  spec.eq(links.keyword("Press", kws), "Press")
  spec.eq(links.keyword("Water every plant", kws), nil)
end)

spec.run()
