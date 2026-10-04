-- Unit cases for the program as rows (issue #2, M6a): a page decoded into sections, units and scenarios, compiled
-- to org, and the org decoded back to the same rows.
local spec = require("mono.spec")
local src = require("tablua.source")

local PAGE = [[
<notes>
* Notes
  Jot notes, newest first.
</notes>

<feature>
Feature: Notes

  Scenario: a note is written
    When I open the page
    And I type "Milk" into "Title"
    And I press "Add"
    Then I see "Milk"

  Scenario: a note is deleted
    When I open the page
    And I type "Old" into "Title"
    And I press "Add"
    And I press "Delete" for "Old"
    Then I do not see "Old"
</feature>

<steps>
test.step("there is a note {string}", function(w, t)
  require("notes").add(t, "")
end)
</steps>

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
  spec.same(names, { "notes", "feature", "steps", "lua", "markup" })
  local text = src.compile(rows)
  local again = assert(src.decode(text))
  spec.eq(src.compile(again), text)
  for _, s in ipairs(rows.sections) do spec.eq(src.body(section(again, s.kind)), src.body(s)) end
end)

spec.test("a Lua section is its top-level statements, each with the comments above it", function()
  local lua = section(src.from_lui(PAGE), "lua")
  spec.same(kinds(lua.units), { "local:d", "stmt:d:exec", "stmt:page.title", "action:post.add", "action:post.delete" })
  spec.ok(lua.units[4].source:find("^\n%-%- a note from the form\nfunction post.add"))
  spec.ok(lua.units[4].source:find("end\nend\n$"))
end)

spec.test("a feature is its header and its scenarios, each with its step lines", function()
  local f = section(assert(src.decode(src.compile(src.from_lui(PAGE)))), "feature")
  spec.ok(f.head:find("^Feature: Notes"))
  spec.eq(#f.scenarios, 2)
  spec.eq(f.scenarios[2].name, "a note is deleted")
  spec.eq(#f.scenarios[2].lines, 5)
  spec.same(f.scenarios[2].lines[4], { keyword = "And", text = 'I press "Delete" for "Old"' })
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
    feature = "Feature: Plants\n\n  Scenario: one\n    When I open the page\n",
    steps = 'test.step("a plant {string}", function(w, n) end)\n',
    lua = 'local d = db.open("data/plants.dbl")\nfunction post.water(req) end',
    markup = "<h1>Plants</h1>\n",
  }))
  spec.ok(text:find("^%* Feature\n#%+begin_src feature\nFeature: Plants\n\n#%+end_src\n%*%* Scenario: one\n"))
  spec.ok(text:find("\n%* Code\n%*%* d\n:PROPERTIES:\n:kind: local\n:name: d\n:END:\n#%+begin_src lua\n"))
  spec.ok(text:find("\n%*%* post.water\n:PROPERTIES:\n:kind: action\n"))
  spec.ok(text:find("\n%* Page\n#%+begin_src lui\n<h1>Plants</h1>\n#%+end_src\n$"))
  local again = assert(src.decode(text))
  spec.same(kinds(section(again, "steps").units), { "step:a plant {string}" })
  spec.same(kinds(section(again, "lua").units), { "local:d", "action:post.water" })
end)

spec.test("a line org would read as a heading or keyword is escaped with a comma, and notes keep their headings", function()
  local lua = "local doc = [[\n* a list\n  #+not org\n,* already\n]]\n"
  local notes = "* Notes\n  Jot notes.\n** Later\n*bold* text\n"
  local text = src.compile(src.from_files({ notes = notes, lua = lua }))
  spec.ok(text:find("\n,%* a list\n  ,#%+not org\n,,%* already\n"))
  spec.ok(text:find("^%* Notes\n%*%* Notes\n  Jot notes.\n%*%*%* Later\n%*bold%* text\n"))
  local again = assert(src.decode(text))
  spec.eq(src.body(section(again, "lua")), lua)
  spec.eq(src.body(section(again, "notes")), notes)
end)

spec.test("org that is not the program's file is refused with why", function()
  local _, why = src.decode("* Plans\nsoon\n")
  spec.ok(why:find("one of Notes, Feature, Steps, Code, Page"))
  _, why = src.decode("* Code\n#+begin_src lua\nlocal x = 1\n")
  spec.ok(why:find("never closed"))
end)

spec.run()
