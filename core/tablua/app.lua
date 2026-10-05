-- An app's files as the program's rows (issue #1 M6c): its features, step files, modules and pages become org files
-- (tablua.source), a page with the app's features and steps, each module one of its own, so the harness can put
-- them (t:put_app) and read what is broken in them (tablua_break) while the agent works, not only after.
--
--   app.program(files) -> { { name, rows, want }, ... }   files: path -> text (paths ending features/*.feature,
--                                                          code/steps/*.lua, code/*.lua, ui/*.org or ui/*.lui);
--                                                          want: each section's text, for a round-trip check
--   t:put_app(files) -> breaks                             every file's rows put, then t:breaks()
local src = require("tablua.source")

local M = {}

-- each file ends its line before the next begins ("...it was written" ran into "Feature: Note Jotter")
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
  local features, steps, modules, pages = {}, {}, {}, {}
  for path, text in pairs(files) do
    if path:match("features/.+%.feature$") then features[#features + 1] = text
    elseif path:match("code/steps/.+%.lua$") then steps[#steps + 1] = text
    elseif path:match("code/[^/]+%.lua$") then modules[path] = text
    elseif path:match("ui/.+%.lui$") or path:match("ui/.+%.org$") then pages[path] = text end
  end
  table.sort(features)
  table.sort(steps)
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
    -- the app's features and steps go with its first page
    if first then f.feature, f.steps, first = joined(features), joined(steps), false end
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
