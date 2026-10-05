-- Unit cases for the program as rows (M6a): a page decoded into sections, units, tests and keywords, compiled
-- to org, and the org decoded back to the same rows.
local spec = require("spec")
local src = require("tablua.source")

local PAGE = [[
<notes>
* Notes
  Jot notes, newest first.
</notes>

<tests>
*** Settings ***
Test Setup    Open    /

*** Test Cases ***
A note is written
    Add Note    Milk
    See    Milk

A note is deleted
    Add Note    Old
    Press For    Delete    Old
    Do Not See    Old

*** Keywords ***
Add Note
    [Arguments]    ${title}
    Type    title    ${title}
    Press    Add
</tests>

<keywords>
keyword("There is a note ${title}", function(title)
  require("notes").add(title, "")
end)
</keywords>

<lua>
local d = db.open("data/notes.dbl")
d:exec("create table if not exists notes (id integer primary key, title text)")
page.title = "Notes"

-- a note from the form
function post.add(req)
  if req.form.title ~= "" then
    d:exec("insert into notes (title) values (?)", req.form.title)
  end
end

function post.delete(req) d:exec("delete from notes where id = ?", req.form.id) end
</lua>

<h1>{{ page.title }}</h1>
<form post="add"><input name="title" placeholder="Title"/><button>Add</button></form>
]]

local function kinds(units)
  local out = {}
  for i, u in ipairs(units) do out[i] = u.kind .. ":" .. u.name end
  return out
end

local function section(rows, kind)
  for _, s in ipairs(rows.sections) do if s.kind == kind then return s end end
end

spec.test("a page's rows compile to org, which decodes to the same rows and compiles to the same org", function()
  local rows = src.from_lui(PAGE)
  local names = {}
  for i, s in ipairs(rows.sections) do names[i] = s.kind end
  spec.same(names, { "notes", "tests", "keywords", "code", "markup" })
  local text = src.compile(rows)
  local again = assert(src.decode(text))
  spec.eq(src.compile(again), text)
  for _, s in ipairs(rows.sections) do spec.eq(src.body(section(again, s.kind)), src.body(s)) end
end)

spec.test("a Lua section is its top-level statements, each with the comments above it", function()
  local lua = section(src.from_lui(PAGE), "code")
  spec.same(kinds(lua.units), { "local:d", "stmt:d:exec", "stmt:page.title", "action:post.add", "action:post.delete" })
  spec.ok(lua.units[4].source:find("^\n%-%- a note from the form\nfunction post.add"))
  spec.ok(lua.units[4].source:find("end\nend\n$"))
end)

spec.test("the tests are their head, then each test and user keyword with its calls", function()
  local t = section(assert(src.decode(src.compile(src.from_lui(PAGE)))), "tests")
  spec.ok(t.head:find("^%*%*%* Settings %*%*%*\nTest Setup"))
  local names = {}
  for i, it in ipairs(t.items) do names[i] = it.kind .. ":" .. it.name end
  spec.same(names, { "test:A note is written", "test:A note is deleted", "keyword:Add Note" })
  local calls = src.calls(t.items[2])
  spec.eq(#calls, 3)
  spec.same(calls[2], { path = "2", keyword = "Press For", args = { "Delete", "Old" } })
  spec.same(src.calls(t.items[3])[1], { path = "1", keyword = "Type", args = { "title", "${title}" } })
end)

spec.test("calls inside FOR and IF are found one level down, setup and teardown by s and t", function()
  local _, items = src.tests("*** Test Cases ***\nLoop\n    [Setup]    Open    /\n    FOR    ${x}    IN    a    b\n"
    .. "        Add Note    ${x}\n    END\n    IF    1 > 0\n        See    a\n    ELSE\n        Fail    no\n    END\n")
  local paths = {}
  for i, c in ipairs(src.calls(items[1])) do paths[i] = c.path .. " " .. c.keyword end
  spec.same(paths, { "s Open", "1.1 Add Note", "2.1.1 See", "2.e.1 Fail" })
end)

spec.test("strings, long strings and comments that say end or function do not cut a statement", function()
  local text = 'local s = "end function"\nlocal q = [[\nselect 1 -- end\nfunction\n]]\n--[[ end\nend ]]\n'
    .. 'local t = {\n  a = 1,\n  b = function() return 2 end,\n}\nprint(t\n  .a)\n'
  local units = src.units(text)
  spec.same(kinds(units), { "local:s", "local:q", "local:t", "stmt:print" })
  local joined = {}
  for i, u in ipairs(units) do joined[i] = u.source end
  spec.eq(table.concat(joined), text)
end)

spec.test("each row is an org heading with its columns in a drawer and its text in a source block", function()
  local text = src.compile(src.from_files({
    tests = "*** Test Cases ***\nOne\n    Open    /\n",
    keywords = 'keyword("A plant ${name}", function(name) end)\n',
    code = 'local d = db.open("data/plants.dbl")\nfunction post.water(req) end',
    markup = "<h1>Plants</h1>\n",
  }))
  spec.ok(text:find("^%* Tests\n%*%* Test: One\n#%+begin_src robot\n,%*%*%* Test Cases %*%*%*\nOne\n    Open    /\n#%+end_src\n"))
  spec.ok(text:find("\n%* Code\n%*%* d\n:PROPERTIES:\n:kind: local\n:name: d\n:END:\n#%+begin_src lua\n"))
  spec.ok(text:find("\n%*%* post.water\n:PROPERTIES:\n:kind: action\n"))
  spec.ok(text:find("\n%* Page\n#%+begin_src lui\n<h1>Plants</h1>\n#%+end_src\n$"))
  local again = assert(src.decode(text))
  spec.same(kinds(section(again, "keywords").units), { "keyword:A plant ${name}" })
  spec.same(kinds(section(again, "code").units), { "local:d", "action:post.water" })
end)

spec.test("a line org would read as a heading or keyword is escaped with a comma, and notes keep their headings", function()
  local lua = "local doc = [[\n* a list\n  #+not org\n,* already\n]]\n"
  local notes = "* Notes\n  Jot notes.\n** Later\n*bold* text\n"
  local text = src.compile(src.from_files({ notes = notes, code = lua }))
  spec.ok(text:find("\n,%* a list\n  ,#%+not org\n,,%* already\n"))
  spec.ok(text:find("^%* Notes\n%*%* Notes\n  Jot notes.\n%*%*%* Later\n%*bold%* text\n"))
  local again = assert(src.decode(text))
  spec.eq(src.body(section(again, "code")), lua)
  spec.eq(src.body(section(again, "notes")), notes)
end)

spec.test("org that is not the program's file is refused with why", function()
  local _, why = src.decode("* Plans\nsoon\n")
  spec.ok(why:find("one of Notes, Tests, Keywords, Code, Page"))
  _, why = src.decode("* Code\n#+begin_src lua\nlocal x = 1\n")
  spec.ok(why:find("never closed"))
end)

-- Lua is the harness's language, not the output's (owner, 2026-10-05): a block in another language is kept whole
spec.test("a code block in another language is one unit, kept with its language, and comes back byte for byte", function()
  local py = "def add(a, b):\n    return a + b\n\n\nclass Plant:\n    pass\n"
  local org = "* Code\n** block\n:PROPERTIES:\n:kind: block\n:END:\n#+begin_src python\n" .. py .. "#+end_src\n"
  local rows = assert(src.decode(org))
  local code = section(rows, "code")
  spec.eq(code.lang, "python")
  spec.eq(#code.units, 1)
  spec.eq(code.units[1].kind, "block")
  spec.eq(src.body(code), py)
  spec.eq(src.compile(rows), org)
  -- and from files, given the language
  spec.eq(src.compile(src.from_files({ code = py, lang = "python" })), org)
end)

spec.run()
