-- A page's elements (context/projects/arock/features/change-blocks, page-elements): Lua that builds a page is one
-- expression of nested calls, ui.page{ ui.card{ ui.form{ ... } } }, and cut as a tree each call is an element a
-- change can name. An element is a call through a dotted name (not Lua's own libraries: string, table, math, ...)
-- given a table or a string, as f{...}, f"..." or f({...}) / f("..."); its children are the elements in its
-- arguments. It knows Lua's calls, not any host's ui module.
--
-- A path names an element by its call's last name from the root down: page/card/form/button, and button[2] for the
-- second of that name among its siblings (button is button[1]).
--
--   local tree = require("tablua.tree")
--   tree.cut(text) -> { roots, all }     each element: { call, seg, path, parent, kids, a, b (its bytes),
--                                        open, close (its table's braces), items (its table's items: { a, b, key,
--                                        va (where a key's value starts), str }), str (its string argument) }
--   tree.find(t, path) -> element | nil  tree.at(t, a) -> the element starting at byte a
--   tree.index(parent, el) -> k          which of the parent's items holds el
--   tree.insert(text, el, k, item, exact) -> text, a   item put in as the k-th of el's table (exact: as given,
--                                        else with the separator the table uses); a, where the item starts
--   tree.remove(text, el, k) -> text, removed, bare, x   the k-th item taken out with its separator (removed:
--                                        the bytes taken, which an exact insert at k puts back); bare: the item;
--                                        x, the byte the taking began at
--   tree.indent(text, a) -> the blanks that start the line byte a is on
--   tree.rows(text) -> { { path, call, parent, depth, children, props, text } }   one row per element
local lexer = require("tablua.lexer")

local M = {}

M.std = { string = true, table = true, math = true, os = true, io = true, coroutine = true, debug = true,
  utf8 = true, package = true }

local OPEN = { ["("] = true, ["{"] = true, ["["] = true }
local CLOSE = { [")"] = true, ["}"] = true, ["]"] = true }
local BLOCK = { ["function"] = 1, ["if"] = 1, ["do"] = 1, ["repeat"] = 1, ["end"] = -1, ["until"] = -1 }

-- the code tokens with their bytes (a, b), each opening bracket with the token that closes it (match)
function M.tokens(text)
  local toks, at = {}, 1
  for _, tk in ipairs(lexer.tokens(text)) do
    if tk.t ~= "space" and tk.t ~= "comment" then toks[#toks + 1] = { t = tk.t, s = tk.s, a = at, b = at + #tk.s - 1 } end
    at = at + #tk.s
  end
  local stack = {}
  for k, tk in ipairs(toks) do
    if tk.t == "op" and OPEN[tk.s] then stack[#stack + 1] = k
    elseif tk.t == "op" and CLOSE[tk.s] then
      local o = table.remove(stack)
      if o then toks[o].match = k end
    end
  end
  return toks
end

-- a table's items, split at its own commas and semicolons (not those in brackets or in a function's body)
local function items(toks, o)
  local out, first, last, depth, k, c = {}, nil, nil, 0, o + 1, toks[o].match
  local function close()
    if not first then return end
    local f, it = toks[first], { a = toks[first].a, b = toks[last].b }
    if f.t == "name" and toks[first + 1] and toks[first + 1].s == "=" and first + 1 < last then
      it.key, it.va = f.s, toks[first + 2].a
    elseif first == last and f.t == "string" then
      it.str = f.s
    end
    out[#out + 1], first = it, nil
  end
  while k < c do
    local tk = toks[k]
    if depth == 0 and tk.t == "op" and (tk.s == "," or tk.s == ";") then
      close()
    else
      first = first or k
      if tk.t == "name" then depth = depth + (BLOCK[tk.s] or 0) end
      if tk.match then k = tk.match end
      last = k
    end
    k = k + 1
  end
  close()
  return out
end

-- the element a call at token k makes, and the token it ends at, or nil
local function element(toks, k)
  local tk, prev = toks[k], toks[k - 1]
  if tk.t ~= "name" or lexer.keywords[tk.s] or M.std[tk.s] or (prev and (prev.s == "." or prev.s == ":")) then return end
  local call, j = tk.s, k + 1
  while toks[j] and toks[j].s == "." and toks[j + 1] and toks[j + 1].t == "name" do
    call, j = call .. "." .. toks[j + 1].s, j + 2
  end
  local arg = toks[j]
  if not call:find(".", 1, true) or not arg then return end
  local el = { call = call, seg = call:match("([%w_]+)$"), a = tk.a, kids = {} }
  local last
  if arg.s == "{" and arg.match then el.table, last = j, arg.match
  elseif arg.t == "string" then el.str, last = arg.s, j
  elseif arg.s == "(" and arg.match and toks[j + 1] then
    local inner = toks[j + 1]
    if inner.s == "{" and inner.match then el.table = j + 1
    elseif inner.t == "string" then el.str = inner.s
    else return end
    last = arg.match
  else
    return
  end
  el.b = toks[last].b
  if el.table then
    el.open, el.close, el.items = toks[el.table].a, toks[toks[el.table].match].a, items(toks, el.table)
  end
  return el
end

local function name_kids(list, prefix)
  local count = {}
  for _, el in ipairs(list) do
    count[el.seg] = (count[el.seg] or 0) + 1
    local seg = count[el.seg] > 1 and ("%s[%d]"):format(el.seg, count[el.seg]) or el.seg
    el.path = prefix and prefix .. "/" .. seg or seg
    name_kids(el.kids, el.path)
  end
end

function M.cut(text)
  local toks, roots, all, stack = M.tokens(text), {}, {}, {}
  for k = 1, #toks do
    local el = element(toks, k)
    if el then
      while #stack > 0 and stack[#stack].b < el.a do stack[#stack] = nil end
      el.parent = stack[#stack]
      local into = el.parent and el.parent.kids or roots
      into[#into + 1], all[#all + 1] = el, el
      stack[#stack + 1] = el
    end
  end
  name_kids(roots)
  return { roots = roots, all = all }
end

function M.find(t, path)
  for _, el in ipairs(t.all) do
    if el.path == path or el.path == path:gsub("%[1%]", "") then return el end
  end
end

function M.at(t, a)
  for _, el in ipairs(t.all) do if el.a == a then return el end end
end

function M.index(parent, el)
  for k, it in ipairs(parent.items or {}) do
    if it.a <= el.a and el.b <= it.b then return k end
  end
end

-- the leading blanks of the line byte a is on
function M.indent(text, a)
  local from = a
  while from > 1 and text:sub(from - 1, from - 1) ~= "\n" do from = from - 1 end
  return text:match("^[ \t]*", from)
end

function M.insert(text, el, k, item, exact)
  local its, m = el.items, #el.items
  local function at(pos, s, start) return text:sub(1, pos - 1) .. s .. text:sub(pos), pos + (start or 0) end
  if exact then
    if k <= m then return at(its[k].a, item) end
    return at(m > 0 and its[m].b + 1 or el.open + 1, item)
  end
  local sep = m >= 2 and text:sub(its[1].b + 1, its[2].a - 1) or ", "
  if k <= m then return at(its[k].a, item:gsub("\n", "\n" .. M.indent(text, its[k].a)) .. sep) end
  if m > 0 then
    local body = item:gsub("\n", "\n" .. M.indent(text, its[m].a))
    return at(its[m].b + 1, sep .. body, #sep)
  end
  return at(el.open + 1, " " .. item .. " ", 1)
end

function M.remove(text, el, k)
  local its, m = el.items, #el.items
  local x, y
  if k < m then x, y = its[k].a, its[k + 1].a - 1
  elseif k > 1 then x, y = its[k - 1].b + 1, its[k].b
  else x, y = el.open + 1, el.close - 1 end
  return text:sub(1, x - 1) .. text:sub(y + 1), text:sub(x, y), text:sub(its[k].a, its[k].b), x
end

-- a string token's text without its quotes
local function unquote(s)
  if s:sub(1, 1) == "[" then return (s:gsub("^%[=*%[\n?", ""):gsub("%]=*%]$", "")) end
  return s:sub(2, -2)
end

function M.rows(text)
  local out = {}
  for _, el in ipairs(M.cut(text).all) do
    local props, words, depth, p = {}, {}, 1, el.parent
    while p do depth, p = depth + 1, p.parent end
    if el.str then words[1] = unquote(el.str) end
    for _, it in ipairs(el.items or {}) do
      if it.key then props[#props + 1] = it.key end
      if it.str then words[#words + 1] = unquote(it.str) end
    end
    out[#out + 1] = { path = el.path, call = el.call, parent = el.parent and el.parent.path or "", depth = depth,
      children = #el.kids, props = table.concat(props, ","), text = table.concat(words, " ") }
  end
  return out
end

return M
