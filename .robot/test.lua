-- The claims framework's own tests: the verdicts, the lock, the ledger's flags and the measures.
--   luajit .robot/test.lua
local root = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = root .. "/?.lua;" .. root .. "/../core/?.lua;" .. root .. "/../core/?/init.lua;" .. root
  .. "/../test/?.lua;" .. package.path

local spec = require("spec")
local robot = require("robot")
local sqlite = require("ports.sqlite")
local ledger = require("ledger")
local stats = require("stats")
local keywords = require("keywords")

local function run(text) return robot.run(robot.parse(text), { libraries = { keywords.library(root) } }) end
local function verdicts(text)
  local out = {}
  for _, v in ipairs(ledger.verdicts(run(text))) do out[v.name] = v.verdict end
  return out
end

local SHEET = [[
    Use Fixture    insert into tablua_term (todo, n, i, source, program, programs) values ('t', 1, 1, 'real', 'make', 'cd,make')
]]

spec.test("a claim holds only when its check passed and the same check failed on its red proof", function()
  local v = verdicts([[
*** Test Cases ***
Holds
]] .. SHEET .. [[
    No Setup Program
Holds (red)
    Use Fixture    insert into tablua_term (todo, n, i, source, program, programs) values ('t', 1, 1, 'real', 'cd', 'cd,make')
    No Setup Program
Killed
    Should Be True    1 == 2
Blind
    Should Be True    1 == 1
Blind (red)
    Should Be True    2 == 2
No Proof
    Should Be True    1 == 1
Red Breaks Early
    Should Be True    1 == 1
Red Breaks Early (red)
    Value Of    select nothing from nowhere
    Should Be True    1 == 2
Unknown
    Skip    not yet

*** Keywords ***
No Setup Program
    ${n}=    Count Of    select 1 from tablua_term where program = 'cd' and programs like '%,%'
    Should Be True    ${n} == 0
]])
  spec.same(v, { Holds = "holds", Killed = "KILLED", Blind = "BLIND", ["No Proof"] = "unproven",
    ["Red Breaks Early"] = "unproven", Unknown = "unknown" })
end)

spec.test("a claim's hash covers its text, its red proof and the keywords it names, not its neighbours'", function()
  local base = "*** Variables ***\n${X}    1\n\n*** Test Cases ***\nA\n    Check It\nA (red)\n    Check It\nB\n    Log    b\n\n"
    .. "*** Keywords ***\nCheck It\n    Should Be True    ${X} == 1\n"
  local h = ledger.hashes(base)
  local other = ledger.hashes(base:gsub("Log    b", "Log    c"))
  local kw = ledger.hashes(base:gsub("== 1", "== 2"))
  local var = ledger.hashes(base:gsub("%${X}    1", "${X}    2"))
  spec.eq(other.A, h.A)
  spec.ok(other.B ~= h.B, "B's own edit")
  spec.ok(kw.A ~= h.A, "the keyword A calls")
  spec.ok(var.A ~= h.A, "the variables")
  spec.eq(h["A (red)"], nil)
end)

spec.test("a claim edited after a counted run killed it is flagged; drafts and invalid runs do not count", function()
  local db = sqlite.open(":memory:")
  ledger.open(db)
  local killed = { { name = "C", verdict = "KILLED", status = "FAIL", message = "", tags = {} } }
  ledger.record(db, "claims/x", 1, "abc", true, killed, { C = "h1" })
  local flags = ledger.record(db, "claims/x", 2, "abc", false, killed, { C = "h2" })
  spec.eq(flags.C, nil)
  flags = ledger.record(db, "claims/x", 3, "abd", false, killed, { C = "h3" })
  spec.eq(flags.C, "edited after run 2 killed it")
  ledger.invalid(db, "claims/x", 2, "bug")
  ledger.invalid(db, "claims/x", 3, "bug")
  flags = ledger.record(db, "claims/x", 4, "abe", false, killed, { C = "h4" })
  spec.eq(flags.C, nil)
  spec.err(function() ledger.invalid(db, "claims/x", 9, "no such run") end)
end)

spec.test("AUROC and the gap match known values; shuffled labels are seeded, so a measure repeats", function()
  spec.eq(stats.auroc({ 1, 2, 3, 4 }, { 0, 0, 1, 1 }), 1)
  spec.eq(stats.auroc({ 1, 1, 1, 1 }, { 0, 1, 0, 1 }), 0.5)
  spec.eq(stats.auroc({ 1, 2 }, { 1, 1 }), nil)
  spec.eq(stats.gap({ 3, 1, 1 }, { 1, 0, 0 }), 2)
  local xs, ys = {}, {}
  for i = 1, 20 do xs[i], ys[i] = i, i > 10 and 1 or 0 end
  local a, b = stats.shuffled(stats.auroc, xs, ys, 200), stats.shuffled(stats.auroc, xs, ys, 200)
  spec.same(a, b)
  spec.ok(a.p < 0.01 and math.abs(a.null - 0.5) < 0.05, ("p %.3f null %.3f"):format(a.p, a.null))
  for i = 1, 20 do ys[i] = i % 2 end
  spec.ok(stats.shuffled(stats.auroc, xs, ys, 200).p > 0.2, "alternating labels are chance")
end)

spec.test("a measure with too few rows skips, so the claim is unknown rather than held or killed", function()
  local v = verdicts([[
*** Test Cases ***
Thin
    Use Fixture    create table x (score, label)    insert into x values (1, 0), (2, 1)
    ${r}=    AUROC Against Shuffled    select score, label from x
    Should Be True    $r[1] > 0.6
Thin Agreement
    Use Fixture    create table x (a, b)    insert into x values (1, 1)
    ${g}=    Agreement Of    select a, b from x
    Should Be True    ${g} > 0.9
Thin Mean
    Use Fixture    create table x (v)    insert into x values (1)
    ${m}=    Mean Of    select v from x    min=3
    Should Be True    ${m} > 0
Missing Sheet
    Use Sheet    runs/no-such.sqlite
]])
  spec.same(v, { Thin = "unknown", ["Thin Agreement"] = "unknown", ["Thin Mean"] = "unknown",
    ["Missing Sheet"] = "unknown" })
end)

spec.test("the measures read rows: agreement with an oracle, AUROC against shuffled, a mean", function()
  local rows = {}
  for i = 1, 30 do rows[#rows + 1] = ("(%d, %d)"):format(i, i > 15 and 1 or 0) end
  local res = run([[
*** Test Cases ***
Measures
    Use Fixture    create table x (score, label)    insert into x values ]] .. table.concat(rows, ", ") .. [[

    ${r}=    AUROC Against Shuffled    select score, label from x
    Should Be True    $r[1] == 1 and $r[3] < 0.01
    ${m}=    Mean Of    select label from x
    Should Be True    ${m} == 0.5
    Use Fixture    create table y (a, b)    insert into y values ]] .. ("('cd', 'cd'), "):rep(9) .. [[('make', 'cd')
    ${g}=    Agreement Of    select a, b from y
    Should Be True    ${g} == 0.9
    ${d}=    Disagreements Of    select a, b from y
    Should Be Equal    ${d}    make vs cd
]])
  spec.eq(res.tests[1].status, "PASS", res.tests[1].message)
end)

spec.test("Use Sheets pools many runs' rows, each todo named by its sheet; Needs At Least skips thin evidence", function()
  local dir = root .. "/runs"
  os.execute("mkdir -p '" .. dir .. "'")
  local paths = {}
  for k = 1, 2 do
    paths[k] = ("%s/zz-test-%d.sqlite"):format(dir, k)
    os.remove(paths[k])
    local t = require("tablua").open(sqlite.open(paths[k]))
    t.db:exec("insert into tablua_term (todo, n, i, source, program) values ('run', 1, 1, 'real', 'make')")
  end
  local res = run([[
*** Test Cases ***
Pooled
    Use Sheets    runs/zz-test-*.sqlite
    ${n}=    Count Of    select distinct todo from tablua_term
    Should Be True    ${n} == 2
    ${t}=    Value Of    select min(todo) from tablua_term
    Should Be Equal    ${t}    zz-test-1:run
Thin
    Needs At Least    3    20    rows with red text
    Fail    never reached
None
    Use Sheets    runs/zz-none-*.sqlite
]])
  for _, p in ipairs(paths) do os.remove(p) end
  spec.eq(res.tests[1].status, "PASS", res.tests[1].message)
  spec.same({ res.tests[2].status, res.tests[2].message }, { "SKIP", "rows with red text: 3 of 20 needed" })
  spec.eq(res.tests[3].status, "SKIP")
end)

spec.run()
