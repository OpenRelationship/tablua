-- Unit cases for tablua.change: parsing a change block, its operations applied all or nothing with their reverse,
-- a step and a scenario changed, and the refusals named by operation. The feature's scenarios
-- (context/projects/arock/features/change-blocks) cover the rest.
local spec = require("mono.spec")
local src = require("tablua.source")
local change = require("tablua.change")

local CODE = "local M = {}\n\nlocal function sum(a, b) return a + b end\n\nreturn M\n"
local STEPS = 'test.step("I add {int} and {int}", function(w, a, b) w.a, w.b = a, b end)\n'
local FEATURE = "Feature: Sums\n\n  Scenario: Adding\n    When I add 2 and 3\n    Then I see \"5\"\n"

local function rows() return src.from_files{ code = CODE, steps = STEPS, feature = FEATURE } end

spec.test("a change block parses into numbered operations with their bodies", function()
  local ops = assert(change.parse("\n%% add d after sum\nlocal d = 1\n\n%% rename sum plus\n%% scenario S first\n"))
  spec.eq(#ops, 3)
  spec.same({ ops[1].op, ops[1].name, ops[1].after, ops[1].body }, { "add", "d", "sum", "local d = 1\n" })
  spec.same({ ops[2].name, ops[2].to }, { "sum", "plus" })
  spec.ok(ops[3].first and ops[3].body == "")
  spec.eq(select(2, change.parse("local x = 1\n")), "a change starts with an operation: a line beginning %% and its verb")
  spec.eq(select(2, change.parse("%% move x\n")), 'operation 1: there is no "move" (add, replace, delete, rename, scenario)')
  spec.eq(select(2, change.parse("%% delete x\nlocal x\n")), "operation 1: delete takes nothing under it")
  spec.eq(select(2, change.parse("%% replace x\n")), "operation 1: replace needs the unit's source under it")
  spec.eq(select(2, change.parse("")), "the change has no operations")
end)

spec.test("a new unit goes before the module's return, a step into the steps", function()
  local done = assert(change.apply(rows(), "%% add M.sum\nfunction M.sum(a, b) return sum(a, b) end\n"
    .. '%% add I see {string}\ntest.step("I see {string}", function(w, s) end)\n'))
  local code = src.body(done.rows.sections[3]) .. src.body(done.rows.sections[2])
  spec.ok(code:find("function M.sum(a, b) return sum(a, b) end\n\nreturn M", 1, true))
  spec.ok(code:find('test.step("I see {string}"', 1, true))
  spec.same({ done.ops[2].kind, done.ops[2].lines }, { "step", 1 })
end)

spec.test("the reverse gives back the program byte for byte", function()
  local before = src.compile(rows())
  local done = assert(change.apply(rows(), "%% replace sum\n-- sums\nlocal function sum(a, b)\n  return a + b\nend\n"
    .. "%% delete M\n%% rename sum plus\n%% scenario More after Adding\n"
    .. "  Scenario: More\n    When I add 1 and 1\n%% scenario Adding\n"))
  spec.ok(src.compile(done.rows) ~= before)
  local back = assert(change.apply(done.rows, done.reverse))
  spec.eq(src.compile(back.rows), before)
end)

spec.test("refusals name the operation, and nothing changes", function()
  local r = rows()
  local before = src.compile(r)
  local function why(text) return select(2, change.apply(r, text)) end
  spec.eq(why("%% add sum\nlocal function sum() end\n"), "operation 1: there is already a unit sum")
  spec.eq(why("%% replace sum\nlocal function total() end\n"),
    "operation 1: its source should be the one unit sum, and is total")
  spec.eq(why("%% rename sum M\n"), "operation 1: M is already a name in the code")
  spec.eq(why("%% add d after nothing\nlocal d\n"), 'operation 1 names no unit "nothing"')
  spec.eq(why("%% scenario Gone\n"), 'operation 1 names no scenario "Gone"')
  spec.eq(why("%% scenario Other\n  Scenario: Different\n"), 'operation 1: its text should be the one scenario "Other"')
  spec.ok(why("%% delete sum\n%% add x\nlocal x = sum(1, 2) +\n"):find("^operation 2 does not compile"))
  spec.eq(src.compile(r), before)
end)

spec.test("the columns of each unit", function()
  local shape = change.shape(rows())
  spec.same({ shape[3].name, shape[3].arity, shape[3].depth, shape[3].names }, { "sum", 2, 1, 0 })
  spec.same({ shape[4].name, shape[4].names }, { "return", 1 })
  spec.same({ shape[1].kind, shape[1].name, shape[1].arity, shape[1].depth }, { "step", "I add {int} and {int}", 3, 1 })
end)

spec.test("a file is changed by its kind: a module, a step file, a feature, an org page", function()
  spec.eq(assert(change.file("code/sums.lua", CODE, "%% rename sum plus\n")),
    "local M = {}\n\nlocal function plus(a, b) return a + b end\n\nreturn M\n")
  local steps = assert(change.file("code/steps/sums.lua", STEPS, "%% add I see {string}\n"
    .. 'test.step("I see {string}", function(w, s) end)\n'))
  spec.ok(steps:find("I see {string}", 1, true) and steps:find("I add {int}", 1, true))
  local feature = assert(change.file("features/sums.feature", FEATURE, "%% scenario Zero\n  Scenario: Zero\n    When I add 0 and 0\n"))
  spec.ok(feature:find("Scenario: Zero", 1, true) and feature:find("Scenario: Adding", 1, true))
  local new = assert(change.file("code/new.lua", nil, "%% add M\nlocal M = {}\n"))
  spec.eq(new, "local M = {}\n")
  local org = src.compile(src.from_files{ code = CODE })
  local page, done = change.file("ui/sums.org", org, "%% delete sum\n")
  spec.ok(page and not page:find("local function sum", 1, true))
  spec.same({ done.ops[1].op, done.ops[1].breaks }, { "delete", 0 })
  spec.eq(select(2, change.file("notes.txt", "x", "%% delete x\n")), "a change is to a .feature, a .lua file or an org page: notes.txt")
  spec.eq(select(2, change.file("ui/none.org", nil, "%% delete x\n")), "ui/none.org does not exist yet: write the page whole")
end)

spec.run()
