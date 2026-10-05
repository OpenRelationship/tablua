-- Unit cases for tablua.app: an app's files put as the program's rows while the agent works, and what is broken in
-- them read back (tablua_break), a call into the app's own module that the module does not define among them.
local spec = require("spec")
local tablua = require("tablua")
local sqlite = require("ports.sqlite")

-- a plants run's page and module (2026-10-05): the page lists plants.list(), which the module never defined
local PAGE = [[* Code
#+begin_src lua
local plants = require("plants")
page.title = "House Plants"
function post.add(req) plants.add(req.form.name) end
#+end_src
* Page
#+begin_src lua
local rows = {}
for _, p in ipairs(plants.list()) do rows[#rows + 1] = ui.li{ p.name } end
return ui.main{ ui.form{ post = "add", ui.input{ name = "name" }, ui.button("Add") }, ui.ul(rows) }
#+end_src
]]
local MODULE = [[local d = db.open("data/plants.dbl")
local M = {}
function M.add(name) d:exec("INSERT INTO plant (name) VALUES (?)", name) end
function M.find(name) return d:one("SELECT * FROM plant WHERE name = ?", name) end
return M
]]

local function calls(breaks)
  local out = {}
  for _, b in ipairs(breaks) do if b.kind == "calls" then out[#out + 1] = b.target end end
  return out
end

spec.test("a page's call into the app's module that the module does not define is a break", function()
  local t = tablua.open(sqlite.open(":memory:"))
  local breaks = t:put_app({ ["/home/ui/index.org"] = PAGE, ["/home/code/plants.lua"] = MODULE })
  spec.same(calls(breaks), { "plants.list" })
  -- the module given list: nothing is broken in the calls
  breaks = t:put_app({ ["/home/ui/index.org"] = PAGE,
    ["/home/code/plants.lua"] = MODULE:gsub("return M", "function M.list() return {} end\nreturn M") })
  spec.same(calls(breaks), {})
end)

spec.test("a call into a library the app does not hold is not a break, and a file gone keeps no rows", function()
  local t = tablua.open(sqlite.open(":memory:"))
  local page = PAGE:gsub('require%("plants"%)', 'require("date")')
  spec.same(calls(t:put_app({ ["/home/ui/index.org"] = page, ["/home/code/plants.lua"] = MODULE })), {})
  t:put_app({ ["/home/ui/index.org"] = PAGE, ["/home/code/plants.lua"] = MODULE })
  spec.same(calls(t:put_app({ ["/home/ui/index.org"] = PAGE })), {})   -- no module now: nothing known to miss
  spec.same(t:files(), { "/home/ui/index.org" })
end)

spec.test("a module that returns a table literal exports what it names there", function()
  local t = tablua.open(sqlite.open(":memory:"))
  local mod = "local function add() end\nlocal function list() return {} end\nreturn { add = add, list = list }\n"
  spec.same(calls(t:put_app({ ["/home/ui/index.org"] = PAGE, ["/home/code/plants.lua"] = mod })), {})
end)

spec.run()
