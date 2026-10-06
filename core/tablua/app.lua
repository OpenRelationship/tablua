-- An app's files as the program's rows (M6c): its tests, keyword files, modules and pages become org files
-- (tablua.source), a page with the app's tests and keywords, each module one of its own, so the harness can put
-- them (t:put_app) and read what is broken in them (tablua_break) while the agent works, not only after.
--
--   app.program(files) -> { { name, rows, want }, ... }   files: path -> text (paths ending tests/*.robot, tasks/*.robot,
--                                                          code/keywords/*.lua, code/*.lua, ui/*.org or ui/*.lui);
--                                                          want: each section's text, for a round-trip check
--   t:put_app(files) -> breaks                             every file's rows put, then t:breaks()
local src = require("tablua.source")

local M = {}

-- each file ends its line before the next begins (a file's last line would run into the next one's first)
-- a table's keys in order: pairs' order is not the same from run to run, and what is written from it must be
local function keys(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local function joined(t)
  local out = {}
  for i, x in ipairs(t) do out[i] = (x ~= "" and x:sub(-1) ~= "\n") and x .. "\n" or x end
  return table.concat(out)
end

local function index_first(a, b)
  local ia, ib = a:match("index") ~= nil, b:match("index") ~= nil
  if ia ~= ib then return ia end
  return a < b
end

function M.program(files)
  local tests, keywords, modules, pages = {}, {}, {}, {}
  for _, path in ipairs(keys(files)) do
    local text = files[path]
    if path:match("tests/.+%.robot$") or path:match("tasks/.+%.robot$") then tests[#tests + 1] = text
    elseif path:match("code/keywords/.+%.lua$") then keywords[#keywords + 1] = text
    elseif path:match("code/[^/]+%.lua$") then modules[path] = text
    elseif path:match("ui/.+%.lui$") or path:match("ui/.+%.org$") then pages[path] = text end
  end
  table.sort(tests)
  table.sort(keywords)
  local names = {}
  for path in pairs(pages) do names[#names + 1] = path end
  table.sort(names, index_first)
  local out, first = {}, true
  for _, path in ipairs(names) do
    -- a page in org and Lua is read as it is; a .lui one by its tagged sections
    local page = path:match("%.org$") and (src.decode(pages[path]) or { sections = {} }) or src.from_lui(pages[path])
    local code, markup, lang = "", "", "lui"
    for _, s in ipairs(page.sections) do
      if s.kind == "code" then code = src.body(s) elseif s.kind == "markup" then markup, lang = src.body(s), s.lang end
    end
    local f = { code = code, markup = markup }
    -- the app's tests and keywords go with its first page
    if first then f.tests, f.keywords, first = joined(tests), joined(keywords), false end
    local rows = src.from_files(f)
    for _, s in ipairs(rows.sections) do if s.kind == "markup" then s.lang = lang end end
    out[#out + 1] = { name = path, rows = rows, want = f }
  end
  local mods = {}
  for path in pairs(modules) do mods[#mods + 1] = path end
  table.sort(mods)
  for _, path in ipairs(mods) do
    out[#out + 1] = { name = path, rows = src.from_files({ code = modules[path] }), want = { code = modules[path] } }
  end
  return out
end

M.install = function(T)
  function T:put_app(files)
    local now = {}
    for _, f in ipairs(M.program(files)) do self:put_program(f.name, f.rows); now[f.name] = true end
    -- a file the app no longer has keeps no rows: its exports would hide a break
    for _, name in ipairs(self:files()) do
      if not now[name] then self:put_program(name, { sections = {} }) end
    end
    return self:breaks()
  end
end

return M
