-- Unit cases for tablua.effects: a step's effects, from snapshots before and after it, in the harness's closed
-- vocabulary; keywords by the page's own keywords; a step's commands from its lines.
local spec = require("spec")
local effects = require("tablua.effects")

local function has(list, keyword, arg)
  for _, e in ipairs(list) do if e.keyword == keyword and (arg == nil or e.arg == arg) then return true end end
  return false
end

local function tests(passed, total, failing)
  return { passed = passed, total = total, undefined = 0, failing = failing or {} }
end

spec.test("a keyword is named by the page's own keywords, else the app's own", function()
  spec.eq(effects.keyword_kind("Open"), "open")
  spec.eq(effects.keyword_kind("Press For"), "press_for")
  spec.eq(effects.keyword_kind("Then See Before"), "see_before")
  spec.eq(effects.keyword_kind("see_for"), "see_for")
  spec.eq(effects.keyword_kind("Do Not See"), "not_see")
  spec.eq(effects.keyword_kind("There is a plant named Fern"), "own")
end)

local function f(test, path, keyword, why, reach)
  return { test = test, path = path, keyword = keyword, why = why, reach = reach or 0 }
end

spec.test("a test turned green names its fixed keyword; one failing elsewhere moved on, one further reached", function()
  local before = { tests = tests(0, 2, { f("add", "1", "Open", "500"), f("order", "4", "See Before", "B first", 3) }),
    stage = "building" }
  local after = { tests = tests(1, 2, { f("order", "4", "See Before", "B first", 3) }), stage = "building" }
  local e = effects.compare(before, after, { verb = "rewrite", outcome = "complete" }, {})
  spec.ok(has(e, "Step Complete"))
  spec.ok(has(e, "More Passing"))
  spec.ok(has(e, "Test Turned Green", "add"))
  spec.ok(has(e, "Keyword Fixed", "open"))
  spec.ok(has(e, "Same Keyword Failing", "see_before"))
  spec.ok(not has(e, "All Green") and not has(e, "Reached Further"))
  local later = { tests = tests(1, 2, { f("order", "5", "See", "not shown", 4) }) }
  local m = effects.compare(after, later, {}, {})
  spec.ok(has(m, "Failure Moved On", "see") and has(m, "Reached Further"))
  local back = { tests = tests(1, 2, { f("order", "2.1", "Add Plant", "nil", 1) }) }
  spec.ok(has(effects.compare(later, back, {}, {}), "Fell Back"))
end)

spec.test("all green, a red turn, pages, commands and the stage are effects too", function()
  local before = { tests = tests(1, 2, { f("b", "1", "Open", "x") }), pages = { ["/"] = 500 }, stage = "building" }
  local green = { tests = tests(2, 2), pages = { ["/"] = 200 }, stage = "ready" }
  local e = effects.compare(before, green, { verb = "write_page", outcome = "complete" },
    { { name = "check", exit = 0 }, { name = "cat", exit = 1 } })
  spec.ok(has(e, "All Green") and has(e, "Page Fixed", "/") and has(e, "Check Passed"))
  spec.ok(has(e, "Command Failed", "cat") and has(e, "Stage Became", "ready"))
  local red = { tests = tests(1, 2, { f("a", "1", "Open", "500") }), pages = { ["/"] = 500 } }
  local r = effects.compare(green, red, { regressed = true, outcome = "broken" }, {})
  spec.ok(has(r, "Test Turned Red", "a") and has(r, "Page Broke", "/") and has(r, "Regressed"))
  spec.ok(has(r, "Fewer Passing") and has(r, "Step Broken"))
end)

spec.test("the harness's facts make a snapshot, and a step's lines its commands", function()
  local s = effects.snapshot({ tests = { passed = 0, total = 1, failing = { "add: Open: no page" },
    undefined = {} }, pages = { { path = "/", status = 500 } } }, "building")
  spec.same(s.tests.failing[1], { test = "add", path = "", keyword = "Open", why = "no page", reach = 0 })
  spec.eq(s.pages["/"], 500)
  spec.same(effects.commands({ "$ cd '/home' && test tests/a.robot  -> 1\n# ...", "$ check  -> 0\nok" }),
    { { name = "test", exit = 1 }, { name = "check", exit = 0 } })
end)

spec.run()
