-- Unit cases for robot.run and robot.result: keywords found in the suite, a Lua library and BuiltIn; arguments,
-- variables and embedded arguments; FOR and IF; failures recorded as a tree with NOT RUN after them; setup and
-- teardown; the summary's reach and the rows.
local spec = require("spec")
local robot = require("robot")

local function lib()
  local plants = {}
  local l = robot.library()
  l:add("Open App", function() plants = {} end)
  l:add("Add Plant", function(name) plants[#plants + 1] = name end)
  l:add('The list holds ${n} plants', function(n)
    if #plants ~= tonumber(n) then error(("the list holds %d plants, not %s"):format(#plants, n), 0) end
  end)
  l:add("Plants", function() return plants end)
  l:add("Break", function() error("app/code.lua:12: attempt to index a nil value", 0) end)
  return l
end

local function run(text, opts)
  opts = opts or {}
  opts.libraries = opts.libraries or { lib() }
  return robot.run(robot.parse(text), opts)
end

spec.test("a passing test, Given/When/Then read off, embedded arguments from a library", function()
  local res = run([[
*** Test Cases ***
Adding
    Given Open App
    When Add Plant    Fern
    And Add Plant    Ivy
    Then the list holds 2 plants
]])
  spec.eq(res.status, "PASS")
  spec.eq(res.passed, 1)
  local body = res.tests[1].body
  spec.eq(body[1].name, "Open App")
  spec.same(body[2].args, { "Fern" })
  spec.eq(body[4].name, "The list holds ${n} plants")
end)

spec.test("a failure fails its keyword and test; what comes after is NOT RUN", function()
  local res = run([[
*** Test Cases ***
Counting
    Open App
    Add Plant    Fern
    The list holds 3 plants
    Add Plant    Ivy
]])
  local t = res.tests[1]
  spec.eq(t.status, "FAIL")
  spec.eq(t.message, "the list holds 1 plants, not 3")
  spec.eq(t.body[3].status, "FAIL")
  spec.eq(t.body[4].status, "NOT RUN")
  local s = robot.summary(res)
  spec.eq(#s.failing, 1)
  spec.eq(s.failing[1].path, "3")
  spec.eq(s.failing[1].reach, 2)
end)

spec.test("a user keyword is a subtree; its failure fails the test at the deepest keyword", function()
  local res = run([[
*** Test Cases ***
Through a keyword
    Plant Two    Fern    Ivy

*** Keywords ***
Plant Two
    [Arguments]    ${a}    ${b}
    Open App
    Add Plant    ${a}
    Break
    Add Plant    ${b}
]])
  local s = robot.summary(res)
  spec.eq(s.failing[1].path, "1.3")
  spec.eq(s.failing[1].keyword, "Break")
  spec.eq(s.failing[1].why, "app/code.lua:12: attempt to index a nil value")
  spec.eq(s.failing[1].reach, 2)
  local top = res.tests[1].body[1]
  spec.eq(top.status, "FAIL")
  spec.eq(top.children[4].status, "NOT RUN")
end)

spec.test("msg= names a library keyword's message, as Robot reads it, not text of its own", function()
  local res = run([[
*** Test Cases ***
Named
    Should Be Equal As Numbers    1    2    msg=no overfull boxes
]])
  spec.eq(res.tests[1].message, "no overfull boxes")
end)

spec.test("an unknown keyword fails as Robot words it, and the summary lists it as undefined", function()
  local res = run("*** Test Cases ***\nT\n    Water The Fern\n")
  spec.eq(res.tests[1].message, "No keyword with name 'Water The Fern' found.")
  spec.same(robot.summary(res).undefined, { "Water The Fern" })
end)

spec.test("variables, assignment, RETURN, FOR over a list and a range, IF/ELSE", function()
  local res = run([[
*** Variables ***
@{NAMES}    Fern    Ivy    Moss

*** Test Cases ***
Loops
    Open App
    FOR    ${n}    IN    @{NAMES}
        Add Plant    ${n}
    END
    ${all}=    Plants
    Length Should Be    ${all}    3
    ${total}=    Set Variable    ${0}
    FOR    ${i}    IN RANGE    4
        ${total}=    Evaluate    ${total} + ${i}
    END
    Should Be Equal    ${total}    ${6}
    IF    ${total} > 10
        Fail    too many
    ELSE IF    $total == 6
        Log    six
    ELSE
        Fail    never
    END
    ${got}=    Echo    hi
    Should Be Equal    ${got}    hi

*** Keywords ***
Echo
    [Arguments]    ${x}
    RETURN    ${x}
]])
  spec.eq(res.tests[1].status, "PASS", res.tests[1].message)
end)

spec.test("BuiltIn: expected errors, status, contains, numbers and strings", function()
  local res = run([[
*** Test Cases ***
Built in
    Run Keyword And Expect Error    *nil value    Break
    ${ok}=    Run Keyword And Return Status    Break
    Should Not Be True    ${ok}
    Should Contain    Rosemary    mary
    Should Be Equal As Numbers    2.0    2
    ${s}=    Catenate    SEPARATOR=-    a    b
    Should Be Equal    ${s}    a-b
]])
  spec.eq(res.tests[1].status, "PASS", res.tests[1].message)
end)

spec.test("an expression that is false fails Should Be True and passes Should Not Be True", function()
  local res = run([[
*** Test Cases ***
False is false
    Should Be True    1 == 2    one is not two
Not true holds
    Should Not Be True    1 == 2
]])
  spec.eq(res.tests[1].status, "FAIL")
  spec.eq(res.tests[1].message, "one is not two")
  spec.eq(res.tests[2].status, "PASS", res.tests[2].message)
end)

spec.test("setup and teardown run around a test; a failing setup leaves the body NOT RUN", function()
  local res = run([[
*** Settings ***
Test Setup       Break
Test Teardown    Log    done

*** Test Cases ***
Never runs
    Add Plant    Fern
]])
  local t = res.tests[1]
  spec.eq(t.status, "FAIL")
  spec.eq(t.setup.status, "FAIL")
  spec.eq(t.body[1].status, "NOT RUN")
  spec.eq(t.teardown.status, "PASS")
end)

spec.test("rows: one per keyword, with path, parent, depth, args and status", function()
  local res = run([[
*** Test Cases ***
Rows
    Plant    Fern

*** Keywords ***
Plant
    [Arguments]    ${x}
    Open App
    Add Plant    ${x}
]])
  local rows = robot.rows(res)
  spec.eq(#rows, 4)
  spec.same({ rows[1].type, rows[1].path, rows[1].status }, { "test", "", "PASS" })
  spec.same({ rows[2].keyword, rows[2].path, rows[2].depth, rows[2].args }, { "Plant", "1", 1, "Fern" })
  spec.same({ rows[4].keyword, rows[4].path, rows[4].parent, rows[4].depth }, { "Add Plant", "1.2", "1", 2 })
end)

spec.test("is_builtin knows BuiltIn's names, with or without a Given in front", function()
  spec.ok(robot.is_builtin("Should Be Equal"))
  spec.ok(robot.is_builtin("Then should be equal"))
  spec.ok(not robot.is_builtin("Add Plant"))
end)

spec.test("tasks run only with rpa, the tests only without it, and a task's row is type task", function()
  local text = [[
*** Test Cases ***
Checks
    Open App

*** Tasks ***
Plant Two
    Open App
    Add Plant    Fern
    Add Plant    Ivy
    The list holds 2 plants
]]
  local tests = run(text)
  spec.same({ tests.total, tests.tests[1].kind }, { 1, "test" })
  local tasks = run(text, { rpa = true })
  spec.same({ tasks.total, tasks.passed, tasks.tests[1].name, tasks.tests[1].kind }, { 1, 1, "Plant Two", "task" })
  spec.eq(robot.rows(tasks)[1].type, "task")
end)

spec.test("record: a passing test becomes a task that does it again, loops unrolled, values as they ran", function()
  local text = [[
*** Variables ***
@{NAMES}    Fern    Ivy

*** Test Cases ***
Planting
    [Setup]    Open App
    FOR    ${n}    IN    @{NAMES}
        Add Plant    ${n}
    END
    ${all}=    Plants
    Then the list holds 2 plants
    Plant One    Moss

*** Keywords ***
Plant One
    [Arguments]    ${x}
    Add Plant    ${x}
]]
  local res = run(text)
  spec.eq(res.status, "PASS", res.tests[1] and res.tests[1].message)
  local task = robot.record(res.tests[1], "Plant The Usual")
  spec.eq(task, table.concat({ "*** Tasks ***", "Plant The Usual", "    [Setup]    Open App", "    Add Plant    Fern",
    "    Add Plant    Ivy", "    Plants", "    Then the list holds 2 plants", "    Plant One    Moss" }, "\n") .. "\n")
  -- replayed with the suite's keywords, it does the same and passes
  local again = run(task .. "\n*** Keywords ***\nPlant One\n    [Arguments]    ${x}\n    Add Plant    ${x}\n",
    { rpa = true })
  spec.same({ again.passed, again.total }, { 1, 1 })
  spec.eq(again.tests[1].body[5].children[1].name, "Add Plant")
end)

spec.test("record refuses a failing test, and a value it cannot write as a cell", function()
  local failing = run("*** Test Cases ***\nT\n    Break\n")
  spec.eq(robot.record(failing.tests[1]), nil)
  local odd = run("*** Test Cases ***\nT\n    Open App\n    Add Plant    ${SPACE}${SPACE}two\n")
  local text, why = robot.record(odd.tests[1])
  spec.eq(text, nil)
  spec.ok(why:find("cannot be written"), why)
end)

spec.run()
