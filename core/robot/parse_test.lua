-- Unit cases for robot.parse: sections, cells, tests and keywords with their settings and bodies, FOR and IF
-- blocks, continuations, and the cut that gives the text back byte for byte.
local spec = require("spec")
local parse = require("robot.parse")

local SUITE = [[
*** Settings ***
Documentation    A house-plants app.
Test Setup       Open App
Library          Browse

*** Variables ***
${NAME}          Rosemary
@{PLANTS}        Fern    Ivy

*** Test Cases ***
Adding a plant
    [Tags]    plants    add
    Given the list is empty
    When I add "${NAME}"
    Then the list holds 1 plant

Watering
    ${count}=    Get Length    ${PLANTS}
    FOR    ${p}    IN    @{PLANTS}
        Add Plant    ${p}
    END
    IF    ${count} > 1
        Log    many
    ELSE
        Log    few
    END
    Should Be Equal    ${count}
    ...    ${2}

*** Keywords ***
Add Plant
    [Arguments]    ${name}    ${room}=kitchen
    Type    ${name}    name
    Press    Add
    RETURN    ${name}
]]

spec.test("cells split on two spaces or a tab, an indent is an empty first cell, # ends the line", function()
  spec.same(parse.cells("    Type  Rosemary\tname   # a comment"), { "", "Type", "Rosemary", "name" })
  spec.same(parse.cells("Adding a plant"), { "Adding a plant" })
  spec.same(parse.cells("    Log    \\"), { "", "Log", "" })
end)

spec.test("headers are read whatever their case and number", function()
  spec.eq(parse.header("*** Test Cases ***"), "tests")
  spec.eq(parse.header("*** tasks ***"), "tasks")
  spec.eq(parse.header("***Keyword***"), "keywords")
  spec.eq(parse.header("    *** not a header"), nil)
end)

spec.test("settings and variables are the suite's", function()
  local s = parse.suite(SUITE)
  spec.eq(s.settings.test_setup.keyword, "Open App")
  spec.same(s.settings.libraries, { "Browse" })
  spec.eq(s.variables["${NAME}"], "Rosemary")
  spec.same(s.variables["@{PLANTS}"], { "Fern", "Ivy" })
end)

spec.test("a test is its calls, its tags kept, Given/When/Then left on the keyword", function()
  local t = parse.suite(SUITE).tests[1]
  spec.eq(t.name, "Adding a plant")
  spec.same(t.tags, { "plants", "add" })
  spec.eq(#t.body, 3)
  spec.eq(t.body[2].keyword, 'When I add "${NAME}"')
  spec.eq(t.body[1].line, 13)
end)

spec.test("assignments, FOR, IF/ELSE and continued lines", function()
  local b = parse.suite(SUITE).tests[2].body
  spec.same(b[1].assign, { "${count}" })
  spec.eq(b[1].keyword, "Get Length")
  spec.eq(b[2].kind, "for")
  spec.same(b[2].values, { "@{PLANTS}" })
  spec.eq(b[2].body[1].keyword, "Add Plant")
  spec.eq(b[3].kind, "if")
  spec.eq(b[3].branches[1].cond, "${count} > 1")
  spec.eq(b[3].otherwise[1].args[1], "few")
  spec.same(b[4].args, { "${count}", "${2}" })
end)

spec.test("a keyword's arguments, defaults and RETURN", function()
  local k = parse.suite(SUITE).keywords[1]
  spec.eq(k.name, "Add Plant")
  spec.same(k.args, { "${name}", "${room}=kitchen" })
  spec.eq(k.body[3].kind, "return")
end)

spec.test("cut gives every test and keyword its text, and the whole back byte for byte", function()
  local head, items = parse.cut(SUITE)
  local names = {}
  for i, it in ipairs(items) do names[i] = it.kind .. ":" .. it.name end
  spec.same(names, { "test:Adding a plant", "test:Watering", "keyword:Add Plant" })
  spec.ok(head:find("%*%*%* Variables"), "the settings and variables are the head")
  spec.ok(items[1].text:find("^%*%*%* Test Cases %*%*%*\n"), "a header goes with the item after it")
  spec.ok(items[3].text:find("^%*%*%* Keywords %*%*%*\n"))
  local parts = { head }
  for _, it in ipairs(items) do parts[#parts + 1] = it.text end
  spec.eq(table.concat(parts), SUITE)
end)

spec.test("a file with no tests is all head; one with no trailing newline round-trips too", function()
  local head, items = parse.cut("*** Settings ***\nLibrary  X\n")
  spec.eq(#items, 0)
  spec.eq(head, "*** Settings ***\nLibrary  X\n")
  local text = "*** Test Cases ***\nOne\n    Log    hi"
  local h2, it2 = parse.cut(text)
  spec.eq(h2 .. it2[1].text, text)
end)

spec.test("tasks are their own kind: a suite's tasks apart from its tests, and cut as kind task", function()
  local text = "*** Test Cases ***\nChecks\n    Log    a\n\n*** Tasks ***\nFile Receipts\n    Log    b\n"
    .. "\n*** Keywords ***\nHelper\n    Log    c\n"
  local s = parse.suite(text)
  spec.same({ #s.tests, #s.tasks, #s.keywords }, { 1, 1, 1 })
  spec.eq(s.tasks[1].name, "File Receipts")
  spec.eq(s.tasks[1].kind, "task")
  local _, items = parse.cut(text)
  local kinds = {}
  for i, it in ipairs(items) do kinds[i] = it.kind end
  spec.same(kinds, { "test", "task", "keyword" })
  spec.ok(items[2].text:find("^%*%*%* Tasks %*%*%*\n"))
end)

spec.run()
