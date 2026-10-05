-- Variables for the runner: scopes (suite, test, keyword) and substitution in cells, as Robot Framework does it.
-- A cell that is one ${x} gives x's value as it is; ${x} inside text gives its string; @{x} as a whole cell
-- spreads a list into several arguments. ${1} and ${2.5} are numbers; ${True}, ${False}, ${None}, ${EMPTY} and
-- ${SPACE} are what they say. ${x}[i] reads an item (1-based for lists, as in Lua).
--   local vars = require("robot.vars")
--   local scope = vars.scope(parent?)  scope:get(name) scope:set(name, v) scope:set_global(name, v)
--   vars.value(scope, cell) -> v         vars.args(scope, cells) -> { n, ... }   vars.text(v) -> string
local M = {}

M.NONE = setmetatable({}, { __tostring = function() return "None" end })

local Scope = {}
Scope.__index = Scope

function M.scope(parent) return setmetatable({ parent = parent, values = {} }, Scope) end

local function key(name) return (name:gsub("^[%$@&]{", ""):gsub("}$", ""):lower():gsub("[%s_]", "")) end
M.key = key

function Scope:get(name)
  local k = key(name)
  local s = self
  while s do
    if s.values[k] ~= nil then return s.values[k], true end
    s = s.parent
  end
  return nil, false
end

function Scope:set(name, v) self.values[key(name)] = v end

-- set in the outermost scope (the suite): Set Suite Variable
function Scope:set_global(name, v)
  local s = self
  while s.parent do s = s.parent end
  s.values[key(name)] = v
end

function M.text(v)
  if v == nil or v == M.NONE then return "None" end
  if v == true then return "True" end
  if v == false then return "False" end
  if type(v) == "number" and v == math.floor(v) and v >= -1e15 and v <= 1e15 then return string.format("%d", v) end
  if type(v) == "table" then
    local parts = {}
    for i, x in ipairs(v) do parts[i] = M.text(x) end
    return "[" .. table.concat(parts, ", ") .. "]"
  end
  return tostring(v)
end

local SPECIAL = { ["true"] = true, ["false"] = false, ["none"] = M.NONE, ["empty"] = "", ["space"] = " " }

-- the value of the variable named inside ${...}
local function lookup(scope, inner)
  local k = inner:lower():gsub("[%s_]", "")
  if SPECIAL[k] ~= nil then return SPECIAL[k] end
  local n = tonumber(inner)
  if n then return n end
  local v, found = scope:get(inner)
  if not found then error({ robot = true, message = ("Variable '${%s}' not found."):format(inner) }, 0) end
  return v
end

local function item(v, index)
  local i = tonumber(index)
  if type(v) ~= "table" then error({ robot = true, message = "Cannot read an item of a value that is not a list" }, 0) end
  if i then return v[i] end
  return v[index]
end

-- a cell's value: the variable itself when the cell is exactly one, else the text with each replaced
function M.value(scope, cell)
  if type(cell) ~= "string" then return cell end
  local whole, idx = cell:match("^%${([^{}]+)}%[([^%]]+)%]$")
  if whole then return item(lookup(scope, whole), idx) end
  whole = cell:match("^[%$&]{([^{}]+)}$")
  if whole then return lookup(scope, whole) end
  return (cell:gsub("%${([^{}]+)}", function(inner) return M.text(lookup(scope, inner)) end))
end

-- the arguments of a call: each cell's value, with a whole-cell @{list} spread; { n = count, ... }
function M.args(scope, cells)
  local out = { n = 0 }
  for _, c in ipairs(cells or {}) do
    local list = type(c) == "string" and c:match("^@{([^{}]+)}$")
    if list then
      local v = lookup(scope, list)
      for _, x in ipairs(type(v) == "table" and v or { v }) do out.n = out.n + 1; out[out.n] = x end
    else
      out.n = out.n + 1
      out[out.n] = M.value(scope, c)
    end
  end
  return out
end

return M
