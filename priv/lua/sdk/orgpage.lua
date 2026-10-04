-- A page written in org and Lua (arock issue #2; owner, 2026-10-04): ui/<name>.org. Its Code section runs on every
-- request, where post.<name> and get.<name> define the page's actions and page.title its title; its Page section is
-- the body of the render, and returns the page's nodes built with ui (`result` is what an action returned, {} when
-- nothing). An element names an action by its bare name (post = "add").
--
--   * Code
--   #+begin_src lua
--   local d = db.open("data/notes.dbl")
--   function post.add(req) d:exec("insert into notes (title) values (?)", req.form.title) end
--   local notes = d:query("select * from notes order by id desc")
--   #+end_src
--   * Page
--   #+begin_src lua
--   local items = {}
--   for _, n in ipairs(notes) do items[#items + 1] = ui.li(n.title) end
--   return ui.main{ ui.h1"Notes", ui.form{ post = "add", ui.input{ name = "title" }, ui.button"Add" }, ui.ul(items) }
--   #+end_src
--
--   orgpage.compile(text, name) -> src, lines (lines[n]: the file's line for line n of src) | nil, why
--   orgpage.check(text, name) -> nil, or why the page does not compile (the build loop's check)
--   orgpage.answer(text, name, req) -> HTML or { status, body } / { redirect }; errors name the file's own lines
--   orgpage.template(app) -> a whole page to start from, as `new orgpage` gives it
local org = require("tablua.org")
local ui = require("shroomi")
local page = require("shroomi.page")

local M = {}

local function count(s)
  local n = 0
  for _ in s:gmatch("\n") do n = n + 1 end
  return n
end

function M.compile(text, name)
  local read, why = org.read(text)
  if not read then return nil, name .. ": " .. why end
  local code, view = { text = "", at = {} }, nil
  for _, s in ipairs(read) do
    if s.kind == "lua" then code = s elseif s.kind == "markup" then view = s end
  end
  if not view or view.text == "" then
    return nil, name .. ": a page has a * Page section: a lua block that returns its nodes, built with ui"
  end
  if view.lang ~= "lua" then return nil, name .. ": the * Page block is lua (#+begin_src lua), not " .. tostring(view.lang) end
  -- the header shares code's first line, and the render's opening shares the page's, so each line of the chunk is
  -- one line of the file
  local src = "local req, post, get, page, ui = ... " .. code.text .. "return function(result) " .. view.text .. "end"
  local lines, nc = {}, count(code.text)
  for i = 1, nc do lines[i] = code.at[i] end
  for i, at in ipairs(view.at) do lines[nc + i] = at end
  lines[#lines + 1] = view.at[#view.at]
  return src, lines
end

-- the error with each line of the chunk as the file's line
local function placed(e, name, lines)
  e = tostring(e)
  local pat = "^" .. name:gsub("%p", "%%%0") .. ":(%d+):"
  return (e:gsub(pat, function(n) return name .. ":" .. (lines[tonumber(n)] or n) .. ":" end))
end

local function chunk(text, name)
  local src, lines = M.compile(text, name)
  if not src then return nil, lines end
  local fn, why = load(src, "@" .. name, "t")
  if not fn then return nil, placed(why, name, lines) end
  return fn, lines
end

function M.check(text, name)
  local fn, why = chunk(text, name)
  if not fn then return why end
end

function M.answer(text, name, req)
  local run, lines = chunk(text, name)
  if not run then error(lines, 0) end
  local def = function(r, post, get, meta)
    -- the page is already the document: ui.page{ title = ..., ... } in a Page gives its title to the page and its
    -- children to the body, rather than a document inside the document
    local pui = setmetatable({ page = function(p)
      if type(p) ~= "table" then return p end
      meta.title, meta.dark = p.title or meta.title, p.dark
      local kids = {}
      for i = 1, ui.maxn(p) do kids[i] = p[i] end
      return kids
    end }, { __index = ui })
    local render = run(r, post, get, meta, pui)
    if type(render) ~= "function" then error(name .. ": the page's Code returned before its Page", 0) end
    return function(result) return page.wire(render(result), r, post, get, name) end
  end
  local ok, res = pcall(page.answer, def, req)
  if not ok then error(placed(res, name, lines), 0) end
  return res
end

-- a whole page to start from: a table, a list, an action that adds and one that removes
function M.template(app)
  return (string.gsub([==[
* Code
#+begin_src lua
local d = db.open("data/APP.dbl")
d:exec("create table if not exists item (id integer primary key, name text not null)")
page.title = "<A title>"

function post.add(req)
  if (req.form.name or "") ~= "" then d:exec("insert into item (name) values (?)", req.form.name) end
end

function post.remove(req) d:exec("delete from item where id = ?", tonumber(req.form.id)) end

local items = d:query("select * from item order by name")
#+end_src
* Page
#+begin_src lua
local rows = {}
for _, it in ipairs(items) do
  rows[#rows + 1] = ui.li{ class = "flex items-center justify-between", it.name,
    ui.button{ size = "sm", variant = "ghost", post = "remove", vals = { id = it.id }, ui.icon{ name = "trash" } } }
end
return ui.container{
  ui.card{ title = "<A title>", description = "<what it is for>",
    #items == 0 and ui.empty{ title = "Nothing yet", description = "Add the first one." } or nil,
    ui.ul{ class = "space-y-2", rows },
    ui.form{ post = "add", class = "flex gap-2",
      ui.input{ name = "name", placeholder = "New", required = true },
      ui.button"Add" } } }
#+end_src
]==], "APP", app or "items"))
end

return M
