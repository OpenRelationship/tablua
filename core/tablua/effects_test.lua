-- Unit cases for tablua.effects: a step's effects, from snapshots before and after it, in the harness's closed
-- vocabulary; Gherkin lines by the page's own step shapes; a step's commands from its lines.
local spec = require("mono.spec")
local effects = require("tablua.effects")

local function has(list, keyword, arg)
  for _, e in ipairs(list) do if e.keyword == keyword and (arg == nil or e.arg == arg) then return true end end
  return false
end

local function tests(passed, total, failing)
  return { passed = passed, total = total, undefined = 0, failing = failing or {} }
end

spec.test("a Gherkin line is named by the page's own step shapes, else the app's own", function()
  spec.eq(effects.line_kind("When I open the page"), "open")
  spec.eq(effects.line_kind('And I press "Water" for "Fern"'), "press_for")
  spec.eq(effects.line_kind('Then I see "Alice" before "Bob"'), "see_before")
  spec.eq(effects.line_kind('Then I see "watered" for "Fern"'), "see_for")
  spec.eq(effects.line_kind('Then I do not see "Old"'), "not_see")
  spec.eq(effects.line_kind("Given there is a plant named Fern"), "own")
end)

spec.test("a scenario turned green names its fixed line; one failing at a later line moved on", function()
  local before = { tests = tests(0, 2, {
    { scenario = "add", step = "When I open the page", why = "500" },
    { scenario = "order", step = 'Then I see "A" before "B"', why = "B first" } }), stage = "building" }
  local after = { tests = tests(1, 2, {
    { scenario = "order", step = 'Then I see "A" before "B"', why = "B first" } }), stage = "building" }
  local e = effects.compare(before, after, { verb = "rewrite", outcome = "complete" }, {})
  spec.ok(has(e, "Step Complete"))
  spec.ok(has(e, "More Passing"))
  spec.ok(has(e, "Scenario Turned Green", "add"))
  spec.ok(has(e, "Line Fixed", "open"))
  spec.ok(has(e, "Same Line Failing", "see_before"))
  spec.ok(not has(e, "All Green"))
  local later = { tests = tests(1, 2, { { scenario = "order", step = 'Then I see "B"', why = "not shown" } }) }
  spec.ok(has(effects.compare(after, later, {}, {}), "Failure Moved On", "see"))
end)

spec.test("all green, a red turn, pages, commands and the stage are effects too", function()
  local before = { tests = tests(1, 2, { { scenario = "b", step = "When I open the page", why = "x" } }),
    pages = { ["/"] = 500 }, stage = "building" }
  local green = { tests = tests(2, 2), pages = { ["/"] = 200 }, stage = "ready" }
  local e = effects.compare(before, green, { verb = "write_page", outcome = "complete" },
    { { name = "check", exit = 0 }, { name = "cat", exit = 1 } })
  spec.ok(has(e, "All Green") and has(e, "Page Fixed", "/") and has(e, "Check Passed"))
  spec.ok(has(e, "Command Failed", "cat") and has(e, "Stage Became", "ready"))
  local red = { tests = tests(1, 2, { { scenario = "a", step = "When I open the page", why = "500" } }),
    pages = { ["/"] = 500 } }
  local r = effects.compare(green, red, { regressed = true, outcome = "broken" }, {})
  spec.ok(has(r, "Scenario Turned Red", "a") and has(r, "Page Broke", "/") and has(r, "Regressed"))
  spec.ok(has(r, "Fewer Passing") and has(r, "Step Broken"))
end)

spec.test("the harness's facts make a snapshot, and a step's lines its commands", function()
  local s = effects.snapshot({ tests = { passed = 0, total = 1, failing = { "add: When I open the page: no page" },
    undefined = {} }, pages = { { path = "/", status = 500 } } }, "building")
  spec.same(s.tests.failing[1], { scenario = "add", step = "When I open the page", why = "no page" })
  spec.eq(s.pages["/"], 500)
  spec.same(effects.commands({ "$ cd '/home' && test features/a.feature  -> 1\n# ...", "$ check  -> 0\nok" }),
    { { name = "test", exit = 1 }, { name = "check", exit = 0 } })
end)

spec.run()
