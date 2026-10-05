-- Unit cases for tablua.change: parsing a change block, its operations applied all or nothing with their reverse,
-- a keyword unit and a test changed, and the refusals named by operation.
-- The rest is covered where a host binds the change block to its agent.
local spec = require("spec")
local src = require("tablua.source")
local change = require("tablua.change")

local CODE = "local M = {}\n\nlocal function sum(a, b) return a + b end\n\nreturn M\n"
local KEYWORDS = 'keyword("I add ${a} and ${b}", function(a, b) sums[#sums + 1] = a + b end)\n'
local TESTS = "*** Test Cases ***\nAdding\n    I add 2 and 3\n    See    5\n\n*** Keywords ***\nAdd Twice\n    I add 1 and 1\n"
  .. "    I add 1 and 1\n"

local function rows() return src.from_files{ code = CODE, keywords = KEYWORDS, tests = TESTS } end

spec.test("a change block parses into numbered operations with their bodies", function()
  local ops = assert(change.parse("\n%% add d after sum\nlocal d = 1\n\n%% rename sum plus\n%% test S first\n"))
  spec.eq(#ops, 3)
  spec.same({ ops[1].op, ops[1].name, ops[1].after, ops[1].body }, { "add", "d", "sum", "local d = 1\n" })
  spec.same({ ops[2].name, ops[2].to }, { "sum", "plus" })
  spec.ok(ops[3].first and ops[3].body == "")
  spec.eq(select(2, change.parse("local x = 1\n")), "a change starts with an operation: a line beginning %% and its verb")
  spec.eq(select(2, change.parse("%% shove x\n")),
    'operation 1: there is no "shove" (add, replace, delete, rename, test, task, keyword; a page\'s set, put, drop, move, wrap, unwrap)')
  spec.eq(select(2, change.parse("%% delete x\nlocal x\n")), "operation 1: delete takes nothing under it")
  spec.eq(select(2, change.parse("%% replace x\n")), "operation 1: replace needs the unit's source under it")
  spec.eq(select(2, change.parse("")), "the change has no operations")
end)

spec.test("a new unit goes before the module's return, a keyword into the keywords", function()
  local done = assert(change.apply(rows(), "%% add M.sum\nfunction M.sum(a, b) return sum(a, b) end\n"
    .. '%% add The sum is ${n}\nkeyword("The sum is ${n}", function(n) end)\n'))
  local code = src.body(done.rows.sections[3]) .. src.body(done.rows.sections[2])
  spec.ok(code:find("function M.sum(a, b) return sum(a, b) end\n\nreturn M", 1, true))
  spec.ok(code:find('keyword("The sum is ${n}"', 1, true))
  spec.same({ done.ops[2].kind, done.ops[2].lines }, { "keyword", 1 })
end)

spec.test("a test and a user keyword are added, replaced and removed by name, headers kept in place", function()
  local done = assert(change.apply(rows(), "%% test Zero first\nZero\n    I add 0 and 0\n"
    .. "%% keyword Add Thrice\nAdd Thrice\n    Add Twice\n    I add 1 and 1\n%% test Adding\n"))
  local text = src.body(done.rows.sections[1])
  spec.eq(text, "*** Test Cases ***\nZero\n    I add 0 and 0\n\n*** Keywords ***\nAdd Twice\n    I add 1 and 1\n"
    .. "    I add 1 and 1\nAdd Thrice\n    Add Twice\n    I add 1 and 1\n")
  spec.same({ done.ops[1].op, done.ops[1].kind, done.ops[1].lines }, { "test", "test", 1 })
  spec.same({ done.ops[3].op, done.ops[3].lines }, { "test", -2 })
end)

spec.test("a task goes after the tests and before the keywords, under its own header, and is removed by name", function()
  local done = assert(change.apply(rows(), "%% task Sum Two\nSum Two\n    I add 2 and 2\n"))
  spec.eq(src.body(done.rows.sections[1]), "*** Test Cases ***\nAdding\n    I add 2 and 3\n    See    5\n\n"
    .. "*** Tasks ***\nSum Two\n    I add 2 and 2\n\n*** Keywords ***\nAdd Twice\n    I add 1 and 1\n    I add 1 and 1\n")
  spec.same({ done.ops[1].op, done.ops[1].kind, done.ops[1].lines }, { "task", "task", 1 })
  local back = assert(change.apply(done.rows, done.reverse))
  spec.eq(src.body(back.rows.sections[1]), TESTS)
  spec.eq(select(2, change.apply(rows(), "%% task Adding\n")), 'operation 1 names no task "Adding"')
end)

spec.test("the reverse gives back the program byte for byte", function()
  local before = src.compile(rows())
  local done = assert(change.apply(rows(), "%% replace sum\n-- sums\nlocal function sum(a, b)\n  return a + b\nend\n"
    .. "%% delete M\n%% rename sum plus\n%% test More after Adding\n"
    .. "More\n    I add 1 and 1\n%% test Adding\n%% keyword Add Twice\n"))
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
  spec.eq(why("%% test Gone\n"), 'operation 1 names no test "Gone"')
  spec.eq(why("%% test Other\nDifferent\n    Log    x\n"), 'operation 1: its text should be the one test "Other"')
  spec.eq(why("%% test Zero after Nowhere\nZero\n    Log    x\n"), 'operation 1 names no test, task or keyword "Nowhere"')
  spec.ok(why("%% delete sum\n%% add x\nlocal x = sum(1, 2) +\n"):find("^operation 2 does not compile"))
  spec.eq(src.compile(r), before)
end)

spec.test("the columns of each unit", function()
  local shape = change.shape(rows())
  spec.same({ shape[3].name, shape[3].arity, shape[3].depth, shape[3].names }, { "sum", 2, 1, 0 })
  spec.same({ shape[4].name, shape[4].names }, { "return", 1 })
  spec.same({ shape[1].kind, shape[1].name, shape[1].arity, shape[1].depth }, { "keyword", "I add ${a} and ${b}", 2, 1 })
end)

spec.test("a file is changed by its kind: a module, a keyword file, a test file, an org page", function()
  spec.eq(assert(change.file("code/sums.lua", CODE, "%% rename sum plus\n")),
    "local M = {}\n\nlocal function plus(a, b) return a + b end\n\nreturn M\n")
  local kws = assert(change.file("code/keywords/sums.lua", KEYWORDS, "%% add The sum is ${n}\n"
    .. 'keyword("The sum is ${n}", function(n) end)\n'))
  spec.ok(kws:find("The sum is ${n}", 1, true) and kws:find("I add ${a}", 1, true))
  local tests = assert(change.file("tests/sums.robot", TESTS, "%% test Zero\nZero\n    I add 0 and 0\n"))
  spec.ok(tests:find("\nZero\n", 1, true) and tests:find("\nAdding\n", 1, true))
  spec.ok(tests:find("Zero\n    I add 0 and 0\n\n%*%*%* Keywords"), "a new test goes after the last test, before the keywords")
  local first = assert(change.file("tests/new.robot", nil, "%% test One\nOne\n    Log    hi\n"))
  spec.eq(first, "*** Test Cases ***\nOne\n    Log    hi\n")
  local new = assert(change.file("code/new.lua", nil, "%% add M\nlocal M = {}\n"))
  spec.eq(new, "local M = {}\n")
  local org = src.compile(src.from_files{ code = CODE })
  local page, done = change.file("ui/sums.org", org, "%% delete sum\n")
  spec.ok(page and not page:find("local function sum", 1, true))
  spec.same({ done.ops[1].op, done.ops[1].breaks }, { "delete", 0 })
  spec.eq(select(2, change.file("notes.txt", "x", "%% delete x\n")), "a change is to a .robot file, a .lua file or an org page: notes.txt")
  spec.eq(select(2, change.file("ui/none.org", nil, "%% delete x\n")), "ui/none.org does not exist yet: write the page whole")
end)

spec.run()
