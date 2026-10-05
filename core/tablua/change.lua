-- Change blocks: an edit to a program is a
-- short script of operations on its rows (tablua.source), applied the way a migration is: all of them or none,
-- with the change that undoes it given back. Each operation is a row of columns TabPFN reads (what it did, to
-- what kind of unit, how many code lines it added, how many units named what it touched, how many it left naming
-- nothing). Org stays the file; a change is how it changes.
--
-- An operation starts on a line beginning `%% ` (Ragel's section mark: no Lua line starts so); the lines under
-- it, to the next, are its body. `!` after the verb takes the body as the unit's whole source, verbatim (the
-- reverse is written so); without it a replace keeps the old unit's blank and comment lines above it.
--
--   %% add <name> [after <unit> | first]     the unit's source       refused when the name is taken
--   %% replace <name>                        its new source          refused when nothing has the name
--   %% delete <name>
--   %% rename <old> <new>                    every reference in the file's Lua, never a string or a comment
--   %% test <name> [after <other> | first]       the test's text (Robot), or none to remove it
--   %% keyword <name> [after <other> | first]    a user keyword's text (Robot), or none to remove it
--   %% set, put, drop, move, wrap, unwrap ...    a page's elements by path (tablua.element)
--
--   local change = require("tablua.change")
--   change.parse(text) -> ops | nil, why
--   change.apply(rows, text) -> { rows, reverse, ops = { { op, kind, name, lines, named_by, breaks } } } | nil, why
--                                     (an element's op: its kind is its call, its name its path, named_by 0, and
--                                     breaks the posts and reads it left with nothing at their end)
--   change.shape(rows) -> { { section, n, kind, name, lines, arity, depth, names } }     a column row per unit
--   change.file(path, text, block) -> text, result | nil, why   one file changed: a .robot test file, a keyword
--                                     file (a keywords/ path), a .lua module, or an org page; text nil when new
local src = require("tablua.source")
local lexer = require("tablua.lexer")
local element = require("tablua.element")
local links = require("tablua.links")

local M = {}

M.verbs = { add = true, replace = true, delete = true, rename = true, test = true, keyword = true }
local ITEM = { test = true, keyword = true }
for verb in pairs(element.verbs) do M.verbs[verb] = true end

-- Parsing ----------------------------------------------------------------------------------------------------------

local function place(op, rest)
  local name, other = rest:match("^(.-)%s+after%s+(.+)$")
  if name then op.name, op.after = name, other return end
  name = rest:match("^(.-)%s+first$")
  if name then op.name, op.first = name, true return end
  op.name = rest
end

function M.parse(text)
  local ops, cur = {}, nil
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local verb, bang, rest = line:match("^%%%%%s+(%a+)(!?)%s*(.-)%s*$")
    if verb then
      local n = #ops + 1
      if not M.verbs[verb] then
        return nil, ("operation %d: there is no %q (add, replace, delete, rename, test, keyword; a page's set, put, drop, move, wrap, unwrap)"):format(n, verb)
      end
      cur = { op = verb, n = n, exact = bang == "!", lines = {} }
      if verb == "add" or ITEM[verb] then place(cur, rest)
      elseif verb == "rename" then cur.name, cur.to = rest:match("^(%S+)%s+(%S+)$")
      else cur.name = rest end
      if not cur.name or cur.name == "" then
        return nil, ("operation %d: %s needs %s"):format(n, verb, verb == "rename" and "an old and a new name"
          or "a name")
      end
      ops[n] = cur
    elseif cur then
      cur.lines[#cur.lines + 1] = line
    elseif not line:match("^%s*$") then
      return nil, "a change starts with an operation: a line beginning %% and its verb"
    end
  end
  if #ops == 0 then return nil, "the change has no operations" end
  for i, op in ipairs(ops) do
    local lines = op.lines
    if i == #ops and lines[#lines] == "" then lines[#lines] = nil end   -- the newline the text ends with
    if not op.exact then while #lines > 0 and lines[#lines]:match("^%s*$") do lines[#lines] = nil end end
    op.body, op.lines = #lines > 0 and table.concat(lines, "\n") .. "\n" or "", nil
    local wants = op.op == "add" or op.op == "replace"
    if wants and op.body == "" then return nil, ("operation %d: %s needs the unit's source under it"):format(i, op.op) end
    if (op.op == "delete" or op.op == "rename") and op.body ~= "" then
      return nil, ("operation %d: %s takes nothing under it"):format(i, op.op)
    end
  end
  return ops
end

-- The program -------------------------------------------------------------------------------------------------------

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

-- the Lua sections, whose units the operations name
local function lua_sections(rows)
  local out = {}
  for i, s in ipairs(rows.sections) do
    if s.units and src.lua(s) then out[#out + 1] = { i = i, s = s } end
  end
  return out
end

local function find(rows, name)
  for _, x in ipairs(lua_sections(rows)) do
    for k, u in ipairs(x.s.units) do if u.name == name then return x.s, k, x.i end end
  end
end

-- a section cut again from its text, so its units are what decoding its org would give
local function recut(s)
  s.body = src.body(s)
  if s.units then s.units = src.units(s.body) end
  if s.items then s.head, s.items = src.tests(s.body) end
end

local function code_lines(source) return source and lexer.columns(source).lines or 0 end

-- the units other than the one named that use the name
local function named_by(rows, name)
  local n = 0
  for _, x in ipairs(lua_sections(rows)) do
    for _, u in ipairs(x.s.units) do
      if u.name ~= name and lexer.refs(u.source)[name] then n = n + 1 end
    end
  end
  return n
end

local function lead(source)
  local out, at = {}, 1
  while at <= #source do
    local line = source:match("^[^\n]*\n?", at)
    if not (line:match("^%s*$") or line:match("^%s*%-%-")) then break end
    out[#out + 1], at = line, at + #line
  end
  return table.concat(out)
end

local function op_line(verb, name, where) return "%% " .. verb .. " " .. name .. (where or "") .. "\n" end

local function where(list, k, key)
  return k > 1 and " after " .. list[k - 1][key] or " first"
end

-- the body's one unit, or why it is not one
local function one_unit(op)
  local why = select(2, load(op.body, "=operation", "t"))
  if why then return nil, ("operation %d does not compile: %s"):format(op.n, tostring(why)) end
  local units = src.units(op.body)
  if #units ~= 1 or units[1].name ~= op.name then
    local names = {}
    for i, u in ipairs(units) do names[i] = u.name ~= "" and u.name or u.kind end
    return nil, ("operation %d: its source should be the one unit %s, and is %s"):format(op.n, op.name,
      #names > 0 and table.concat(names, ", ") or "empty")
  end
  return units[1]
end

-- Operations: each changes rows in place and gives back the operation that undoes it, the kind of what it
-- touched and the code lines it took away and added, or nil and why

local DO = {}

function DO.add(rows, op)
  if find(rows, op.name) then return nil, ("operation %d: there is already a unit %s"):format(op.n, op.name) end
  local unit, why = one_unit(op)
  if not unit then return nil, why end
  local kind = unit.kind == "keyword" and "keywords" or "code"
  local s, k
  if op.after then
    s, k = find(rows, op.after)
    if not s then return nil, ("operation %d names no unit %q"):format(op.n, op.after) end
    k = k + 1
  else
    for _, x in ipairs(lua_sections(rows)) do if x.s.kind == kind then s = x.s end end
    if not s then
      s = { kind = kind, units = {} }
      local at = #rows.sections + 1
      for i, other in ipairs(rows.sections) do
        if other.kind == "markup" or (kind == "keywords" and other.kind == "code") then at = i break end
      end
      table.insert(rows.sections, at, s)
    end
    local last = s.units[#s.units]
    k = op.first and 1 or (last and last.name == "return" and #s.units or #s.units + 1)
  end
  table.insert(s.units, k, { kind = unit.kind, name = unit.name, source = op.body })
  recut(s)
  return op_line("delete", op.name), unit.kind, 0, code_lines(op.body)
end

function DO.replace(rows, op)
  local s, k = find(rows, op.name)
  if not s then return nil, ("operation %d names no unit %q"):format(op.n, op.name) end
  local unit, why = one_unit(op)
  if not unit then return nil, why end
  local old = s.units[k]
  local source = (op.exact or lead(op.body) ~= "") and op.body or lead(old.source) .. op.body
  s.units[k] = { kind = unit.kind, name = unit.name, source = source }
  recut(s)
  return op_line("replace!", op.name) .. old.source, old.kind, code_lines(old.source), code_lines(source)
end

function DO.delete(rows, op)
  local s, k = find(rows, op.name)
  if not s then return nil, ("operation %d names no unit %q"):format(op.n, op.name) end
  local old = s.units[k]
  local undo = op_line("add!", op.name, where(s.units, k, "name")) .. old.source
  table.remove(s.units, k)
  recut(s)
  return undo, old.kind, code_lines(old.source), 0
end

function DO.rename(rows, op)
  local s, k = find(rows, op.name)
  if not s then return nil, ("operation %d names no unit %q"):format(op.n, op.name) end
  local kind = s.units[k].kind
  for _, x in ipairs(lua_sections(rows)) do
    for _, u in ipairs(x.s.units) do
      if u.name == op.to or lexer.refs(u.source)[op.to] then
        return nil, ("operation %d: %s is already a name in the code"):format(op.n, op.to)
      end
    end
  end
  for _, x in ipairs(lua_sections(rows)) do
    for _, u in ipairs(x.s.units) do u.source = lexer.rename(u.source, op.name, op.to) end
    recut(x.s)
  end
  return op_line("rename", op.to .. " " .. op.name), kind, 0, 0
end

require("tablua.change_tests")(DO, { recut = recut, op_line = op_line })

-- Applying ------------------------------------------------------------------------------------------------------------

-- the posts to no action and the reads of no field sent, as a set
local function dangling(rows)
  local out, actions, have = {}, {}, {}
  for _, s in ipairs(rows.sections) do
    for _, u in ipairs(s.units or {}) do if u.kind == "action" then actions[u.name] = true end end
  end
  local found = links.scan(rows)
  for _, l in ipairs(found) do have[l.kind .. " " .. l.target] = true end
  for _, l in ipairs(found) do
    if (l.kind == "post" and not actions[l.target] and not have["defines " .. l.target])
      or (l.kind == "reads" and not have["sends " .. l.target]) then
      out[l.kind .. " " .. l.target] = true
    end
  end
  return out
end

-- an operation on the page's elements, as apply records it
local function on_element(rows, op)
  local was = dangling(rows)
  local back, kind, name, before, after = element.apply(rows, op)
  if not back then return nil, kind end
  local breaks = 0
  for k in pairs(dangling(rows)) do if not was[k] then breaks = breaks + 1 end end
  return back, { op = op.op, kind = kind, name = name, lines = after - before, named_by = 0, breaks = breaks }
end

function M.apply(rows, text)
  local ops, why = M.parse(text)
  if not ops then return nil, why end
  rows = copy(rows)
  local undo, out = {}, {}
  for i, op in ipairs(ops) do
    if element.verbs[op.op] then
      local back, row = on_element(rows, op)
      if not back then return nil, row end
      undo[#ops - i + 1], out[i] = back, row
    else
      local by = ITEM[op.op] and 0 or named_by(rows, op.name)
      local back, kind, before, after = DO[op.op](rows, op)
      if not back then return nil, kind end
      local breaks = 0
      if not ITEM[op.op] and not find(rows, op.name) then breaks = named_by(rows, op.name) end
      undo[#ops - i + 1] = back
      out[i] = { op = op.op, kind = kind, name = op.name, lines = after - before, named_by = by, breaks = breaks }
    end
  end
  for _, x in ipairs(lua_sections(rows)) do
    local bad = select(2, load(src.body(x.s), "=" .. x.s.kind, "t"))
    if bad then return nil, ("the change leaves the %s not compiling: %s"):format(x.s.kind, tostring(bad)) end
  end
  return { rows = rows, reverse = table.concat(undo), ops = out }
end

-- a file's text as rows, and back: the kind of section its path holds, or org
local function kind_of(path)
  if path:match("%.robot$") then return "tests" end
  if path:match("%.lua$") then return path:match("keywords/") and "keywords" or "code" end
end

function M.file(path, text, block)
  local kind = kind_of(path)
  local rows, why
  if kind then rows = src.from_files{ [kind] = text or "" }
  elseif path:match("%.org$") then
    if not text then return nil, path .. " does not exist yet: write the page whole" end
    rows, why = src.decode(text)
    if not rows then return nil, path .. " does not read as org: " .. tostring(why) end
  else
    return nil, "a change is to a .robot file, a .lua file or an org page: " .. path
  end
  local done, err = M.apply(rows, block)
  if not done then return nil, err end
  if not kind then return src.compile(done.rows), done end
  -- a plain file is its sections' text: a keyword file's helper lands in a code section of its own
  local parts = {}
  for _, s in ipairs(done.rows.sections) do parts[#parts + 1] = src.body(s) end
  return table.concat(parts), done
end

-- Columns -------------------------------------------------------------------------------------------------------------

function M.shape(rows)
  local out, defined = {}, {}
  for _, x in ipairs(lua_sections(rows)) do
    for _, u in ipairs(x.s.units) do if u.name ~= "" then defined[u.name] = true end end
  end
  for _, x in ipairs(lua_sections(rows)) do
    for k, u in ipairs(x.s.units) do
      local c, names = lexer.columns(u.source), 0
      for name in pairs(lexer.refs(u.source)) do
        if defined[name] and name ~= u.name then names = names + 1 end
      end
      out[#out + 1] = { section = x.i, n = k, kind = u.kind, name = u.name, lines = c.lines, arity = c.arity,
        depth = c.depth, names = names }
    end
  end
  return out
end

return M
