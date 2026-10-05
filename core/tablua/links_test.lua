-- Unit cases for tablua.links: what a page posts to and sends, what an action reads, which scenario lines need a
-- step of the app's own, and a step's text compiled as test.step compiles it.
local spec = require("mono.spec")
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

spec.test("a markup page's own actions are defined by it; only a scenario's own words are lines to settle", function()
  local rows = src.from_files({
    markup = '{% function post.water(req) end %}\n<form post="water"><input name="plant"></form>\n',
    feature = 'Feature: Plants\n\n  Scenario: water\n    When I open the page\n'
      .. '    And there is a plant named "Fern"\n    Then I see "Fern"\n' })
  local l = links.scan(rows)
  spec.ok(has(l, "post", nil, "post.water") and has(l, "defines", nil, "post.water"))
  spec.ok(has(l, "line", "1.2", 'there is a plant named "Fern"'))
  spec.ok(not has(l, "line", "1.1", "I open the page") and not has(l, "line", "1.3", 'I see "Fern"'))
end)

spec.test("a step's text matches as test.step's holes do", function()
  spec.eq(links.step('there is a plant named "Fern"', { "there are {int} plants", "there is a plant named {string}" }),
    "there is a plant named {string}")
  spec.eq(links.step("there are 3 plants", { "there are {int} plants" }), "there are {int} plants")
  spec.eq(links.step("there are many plants", { "there are {int} plants" }), nil)
  spec.eq(links.step("the total is 5.50 (all)", { "the total is {number} (all)" }), "the total is {number} (all)")
end)

spec.run()
