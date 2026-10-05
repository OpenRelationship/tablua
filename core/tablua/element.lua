-- Change blocks on a page's elements (tablua.tree; context/projects/arock/features/change-blocks, page-elements):
-- the operations tablua.change gives a page written as Lua, each naming elements by path, each giving back the
-- operations that undo it. A body is trimmed; with `!` it is taken as given but for the newline that ends it.
--
--   %% set <path> <prop>                    its value under it; none takes the prop away
--   %% put before|after <path>              the element's source under it
--   %% put in <path> [at <k>] | first in <path>
--   %% drop <path>                          (drop in <path> at <k>: an item by its place)
--   %% move <path> before|after <path> | in <path> [at <k>] | first in <path>
--   %% wrap <path>                          the wrapper's source under it, with ... where the element goes
--   %% unwrap <path>                        a wrapper holding one element gives way to it
--
--   local element = require("tablua.element")
--   element.verbs                          the verbs above
--   element.apply(rows, op) -> undo, kind, name, lines before, lines after | nil, why
--     op as tablua.change parses it ({ op, n, exact, name = all after the verb, body }), on the program's page:
--     its markup section in Lua
local tree = require("tablua.tree")
local lexer = require("tablua.lexer")

local M = {}

M.verbs = { set = true, put = true, drop = true, move = true, wrap = true, unwrap = true }

local function body(op)
  if op.exact then return (op.body:gsub("\n$", "")) end
  return (op.body:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function line(verb, rest) return "%% " .. verb .. " " .. rest .. "\n" end
local function exact(verb, rest, text) return line(verb .. "!", rest) .. text .. "\n" end
local function refuse(op, fmt, ...) return nil, ("operation %d" .. fmt):format(op.n, ...) end

local function get(t, path, op)
  local el = tree.find(t, path)
  if not el then return refuse(op, " names no element %q", path) end
  return el
end

-- the source of one element, or why it is not one
local function one(op, source)
  local why = select(2, load("return " .. source, "=operation", "t"))
  if why then return refuse(op, " does not compile: %s", tostring(why)) end
  local t = tree.cut(source)
  if #t.roots ~= 1 or t.roots[1].a ~= 1 or t.roots[1].b ~= #source then
    return refuse(op, ": its source should be one element, a call such as ui.p{ ... }")
  end
  return true
end

-- where an element goes: the parent and the place among its items
local function spot(t, rest, op)
  local how, path = rest:match("^(%a+)%s+(%S+)$")
  if how == "before" or how == "after" then
    local el, why = get(t, path, op)
    if not el then return nil, why end
    if not el.parent then return refuse(op, ": %s is the page's root; put it inside an element", path) end
    local k = tree.index(el.parent, el)
    return el.parent, how == "after" and k + 1 or k
  end
  local first = rest:match("^first%s+in%s+(%S+)$")
  local p, k = rest:match("^in%s+(%S+)%s+at%s+(%d+)$")
  p = first or p or rest:match("^in%s+(%S+)$")
  if not p then return refuse(op, ": where? before <path>, after <path>, in <path> or first in <path>") end
  local el, why = get(t, p, op)
  if not el then return nil, why end
  if not el.items then return refuse(op, ": %s holds no table to put into", p) end
  k = first and 1 or tonumber(k) or #el.items + 1
  if k < 1 or k > #el.items + 1 then return refuse(op, ": %s has %d items", p, #el.items) end
  return el, k
end

local function inside(el, of)
  while el do
    if el == of then return true end
    el = el.parent
  end
end

local DO = {}

function DO.set(text, t, op, rest)
  local path, prop = rest:match("^(%S+)%s+([%a_][%w_]*)$")
  if not path then return refuse(op, ": set <path> <prop>, its value under it") end
  local el, why = get(t, path, op)
  if not el then return nil, why end
  if not el.items then return refuse(op, ": %s holds no table to set %s in", path, prop) end
  local v = body(op)
  for k, it in ipairs(el.items) do
    if it.key == prop then
      if v == "" then
        local new, removed = tree.remove(text, el, k)
        return new, exact("put", ("in %s at %d"):format(path, k), removed), el
      end
      return text:sub(1, it.va - 1) .. v .. text:sub(it.b + 1), exact("set", path .. " " .. prop, text:sub(it.va, it.b)), el
    end
  end
  if v == "" then return refuse(op, ": %s has no %s", path, prop) end
  return (tree.insert(text, el, #el.items + 1, prop .. " = " .. v)), line("set", path .. " " .. prop), el
end

function DO.put(text, t, op, rest)
  local parent, k = spot(t, rest, op)
  if not parent then return nil, k end
  local v = body(op)
  if op.exact then
    return (tree.insert(text, parent, k, v, true)), line("drop", ("in %s at %d"):format(parent.path, k)), parent
  end
  local ok, why = one(op, v)
  if not ok then return nil, why end
  local new, a = tree.insert(text, parent, k, v)
  local el = tree.at(tree.cut(new), a)
  return new, line("drop", el.path), el
end

function DO.drop(text, t, op, rest)
  if op.body:find("%S") then return refuse(op, ": drop takes nothing under it") end
  local parent, el, k
  local p, at = rest:match("^in%s+(%S+)%s+at%s+(%d+)$")
  if p then
    local why
    parent, why = get(t, p, op)
    if not parent then return nil, why end
    k = tonumber(at)
    if not parent.items or k < 1 or k > #parent.items then return refuse(op, ": %s has no item %d", p, k) end
  else
    local why
    el, why = get(t, rest, op)
    if not el then return nil, why end
    parent = el.parent
    if not parent then return refuse(op, ": %s is the page's root; change the unit instead", rest) end
    k = tree.index(parent, el)
    if not k then return refuse(op, ": %s is not an item of %s's table", rest, parent.path) end
  end
  local new, removed = tree.remove(text, parent, k)
  return new, exact("put", ("in %s at %d"):format(parent.path, k), removed), el or parent
end

function DO.move(text, t, op, rest)
  local path, where = rest:match("^(%S+)%s+(.+)$")
  if not path then return refuse(op, ": move <path> before|after <path>, or in <path>") end
  local el, why = get(t, path, op)
  if not el then return nil, why end
  if not el.parent then return refuse(op, ": %s is the page's root", path) end
  local parent, k = spot(t, where, op)
  if not parent then return nil, k end
  if inside(parent, el) then return refuse(op, ": %s cannot move into itself", path) end
  local was = tree.index(el.parent, el)
  local mid, removed, bare, x = tree.remove(text, el.parent, was)
  local lead = tree.indent(text, el.a)   -- its lines go where it goes, indented as there
  if lead ~= "" then bare = bare:gsub("\n" .. lead, "\n") end
  local function shift(a) return a > x and a - #removed or a end
  local t2 = tree.cut(mid)
  if parent == el.parent and k > was then k = k - 1 end
  local undo = exact("put", ("in %s at %d"):format(tree.at(t2, shift(el.parent.a)).path, was), removed)
  local new, a = tree.insert(mid, tree.at(t2, shift(parent.a)), k, bare)
  local moved = tree.at(tree.cut(new), a)
  return new, line("drop", moved.path) .. undo, moved
end

function DO.wrap(text, t, op, rest)
  local el, why = get(t, rest, op)
  if not el then return nil, why end
  local v, mark = body(op), nil
  for _, tk in ipairs(tree.tokens(v)) do if tk.s == "..." then mark = tk break end end
  if not mark then return refuse(op, ": the wrapper's source needs ... where %s goes", rest) end
  local pre, post = v:sub(1, mark.a - 1), v:sub(mark.b + 1)
  if not op.exact then
    local ok, err = one(op, pre .. "nil" .. post)
    if not ok then return nil, err end
  end
  local new = text:sub(1, el.a - 1) .. pre .. text:sub(el.a, el.b) .. post .. text:sub(el.b + 1)
  local w = tree.at(tree.cut(new), el.a)
  return new, line("unwrap", w.path), w
end

function DO.unwrap(text, t, op, rest)
  local w, why = get(t, rest, op)
  if not w then return nil, why end
  if #w.kids ~= 1 then return refuse(op, ": %s holds %d elements; unwrap takes a wrapper of one", rest, #w.kids) end
  local c = w.kids[1]
  local outer = text:sub(w.a, c.a - 1) .. "..." .. text:sub(c.b + 1, w.b)
  local new = text:sub(1, w.a - 1) .. text:sub(c.a, c.b) .. text:sub(w.b + 1)
  local c2 = tree.at(tree.cut(new), w.a)
  return new, exact("wrap", c2.path, outer), c2
end

-- the program's page: its markup section in Lua
local function page(rows)
  for _, s in ipairs(rows.sections) do
    if s.kind == "markup" and s.lang == "lua" then return s end
  end
end

function M.apply(rows, op)
  local s = page(rows)
  if not s then return refuse(op, ": the program has no page written in Lua") end
  local text = s.body or ""
  local bad = select(2, load(text, "=page", "t"))
  if bad then return refuse(op, ": the page does not compile (%s); write it whole", tostring(bad)) end
  local new, undo, el = DO[op.op](text, tree.cut(text), op, op.name)
  if not new then return nil, undo end
  bad = select(2, load(new, "=page", "t"))
  if bad then return refuse(op, " leaves the page not compiling: %s", tostring(bad)) end
  s.body = new
  return undo, el.call, el.path, lexer.columns(text).lines, lexer.columns(new).lines
end

return M
