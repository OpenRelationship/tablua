-- An edit to one unit of a program (M6b): the agent names a file and one of its units, and gives that
-- unit's new source; the file is read as rows (tablua.source), the unit replaced (or added when the file has none of
-- that name) and the file written back whole from the rows. A unit is a top-level Lua statement named as the rows
-- name it (post.add, a local's or a function's name, a step's text), or "page", a page's Page section. A module or
-- step file (.lua) stays plain Lua; a page (ui/*.org) stays org. The new source must be Lua that compiles.
--
--   edit.apply(path, text, unit, source) -> new text | nil, why     text nil when the file does not exist yet
--   edit.index(path, text) -> { name... }                           the units an edit can name, in file order
local src = require("tablua.source")

local M = {}

local function ends(s) return (s ~= "" and s:sub(-1) ~= "\n") and s .. "\n" or s end

-- nil when the Lua compiles, else why (only compiled, never run)
function M.lua_error(source)
  local f, why = load(source, "=unit", "t")
  if f then return nil end
  return tostring(why)
end

-- the blank and comment lines a unit's source starts with (the rows give a statement the lines above it)
local function lead(source)
  local out, at = {}, 1
  while at <= #source do
    local line = source:match("^[^\n]*\n?", at)
    if not (line:match("^%s*$") or line:match("^%s*%-%-")) then break end
    out[#out + 1], at = line, at + #line
  end
  return table.concat(out)
end

-- the unit named `name` in units replaced by source (keeping the lines above it unless the source brings its own),
-- or source added at the end
local function splice(units, name, source)
  local kind, n = src.classify(source:sub(#lead(source) + 1))
  for i, u in ipairs(units) do
    if u.name == name then
      if lead(source) == "" then source = lead(u.source) .. source end
      units[i] = { kind = kind, name = n, source = source }
      return units
    end
  end
  units[#units + 1] = { kind = kind, name = n, source = source }
  return units
end

function M.apply(path, text, unit, source)
  if type(unit) ~= "string" or unit == "" then return nil, "an edit names the unit it replaces" end
  source = ends(tostring(source or ""))
  local bad = M.lua_error(source)
  if bad then return nil, ("the new %s does not compile: %s"):format(unit, bad) end
  if path:match("%.lua$") then
    local units = splice(text and src.units(text) or {}, unit, source)
    local parts = {}
    for i, u in ipairs(units) do parts[i] = u.source end
    return table.concat(parts)
  end
  if not path:match("%.org$") then return nil, "an edit changes a .lua file or a page in ui/*.org: " .. path end
  if not text then return nil, path .. " does not exist yet: write_page writes a new page whole" end
  local rows, why = src.decode(text)
  if not rows then return nil, path .. " does not read as org: " .. tostring(why) end
  local code, page
  for _, s in ipairs(rows.sections) do
    if s.kind == "code" then code = s elseif s.kind == "markup" then page = s end
  end
  if unit == "page" then
    if not page then
      page = { kind = "markup", lang = "lua" }
      rows.sections[#rows.sections + 1] = page
    end
    page.body = source
  else
    if not code then
      code = { kind = "code", units = {} }
      rows.sections[#rows.sections + 1] = code
    end
    code.units = splice(code.units or src.units(src.body(code)), unit, source)
    code.body = nil
  end
  local out = src.compile(rows)
  local again, err = src.decode(out)
  if not again then return nil, "the edited page no longer reads as org: " .. tostring(err) end
  return out
end

function M.index(path, text)
  local out = {}
  if not text then return out end
  if path:match("%.lua$") then
    for _, u in ipairs(src.units(text)) do if u.name ~= "" then out[#out + 1] = u.name end end
    return out
  end
  local rows = src.decode(text)
  for _, s in ipairs(rows and rows.sections or {}) do
    if s.kind == "code" then
      for _, u in ipairs(s.units or {}) do if u.name ~= "" then out[#out + 1] = u.name end end
    elseif s.kind == "markup" then
      out[#out + 1] = "page"
    end
  end
  return out
end

return M
