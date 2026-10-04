-- A page written in org and Lua (arock issue #2; owner, 2026-10-04): ui/<name>.org. Its Code section runs on every
-- request, where post.<name> and get.<name> define the page's actions and page.title its title; its Page section is
-- the body of the render, and returns the page's nodes built with ui (`result` is what an action returned, {} when
-- nothing). An element names an action by its bare name (post = "add"), as a .lui page's elements do.
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
    local render = run(r, post, get, meta, ui)
    if type(render) ~= "function" then error(name .. ": the page's Code returned before its Page", 0) end
    return function(result) return page.wire(render(result), r, post, get, name) end
  end
  local ok, res = pcall(page.answer, def, req)
  if not ok then error(placed(res, name, lines), 0) end
  return res
end

return M
