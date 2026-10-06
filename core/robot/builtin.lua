-- The BuiltIn keywords the runner knows itself, by Robot Framework's names. Each gets the run's context first
-- (ctx: its scope, and ctx:call(name, args) to run a keyword) and then its arguments. A failure is an error with
-- Robot's message. Expressions (Evaluate, Should Be True, IF) are Lua after Robot's substitution: Python's
-- True/False/None and != read as Lua's, and $x reads the variable x itself.
--   local builtin = require("robot.builtin")
--   builtin.keywords -> { [normalized name] = { name, fn } }    builtin.eval(ctx, expression) -> value
local vars = require("robot.vars")

local M = {}

local function fail(msg) error({ robot = true, message = msg }, 0) end
M.fail = fail

local function norm(name) return (name:lower():gsub("[%s_]", "")) end
M.norm = norm

local function eq(a, b)
  if type(a) == "number" or type(b) == "number" then
    local x, y = tonumber(a), tonumber(b)
    if x and y then return x == y end
  end
  return vars.text(a) == vars.text(b)
end

function M.eval(ctx, expr)
  local env = { len = function(x) return type(x) == "table" and #x or #tostring(x) end, int = math.floor,
    str = vars.text, float = tonumber, math = math, string = string, tonumber = tonumber, tostring = tostring }
  local subst = expr:gsub("%$([%a_][%w_]*)", function(name)
    env["_v_" .. name] = (ctx.scope:get(name))
    return "_v_" .. name
  end)
  subst = vars.value(ctx.scope, subst)
  subst = subst:gsub("!=", "~="):gsub("%f[%w_]True%f[^%w_]", "true"):gsub("%f[%w_]False%f[^%w_]", "false")
    :gsub("%f[%w_]None%f[^%w_]", "nil")
  local f, why = load("return " .. subst, "=expression", "t", env)
  if not f then fail(("Evaluating expression '%s' failed: %s"):format(expr, tostring(why))) end
  local ok, v = pcall(f)
  if not ok then fail(("Evaluating expression '%s' failed: %s"):format(expr, tostring(v))) end
  return v
end

local function contains(container, item)
  if type(container) == "table" then
    for _, x in ipairs(container) do if eq(x, item) then return true end end
    return container[item] ~= nil
  end
  return tostring(container):find(vars.text(item), 1, true) ~= nil
end

local function length(x)
  if type(x) == "table" then
    local n = 0
    for _ in pairs(x) do n = n + 1 end
    return n
  end
  return #vars.text(x)
end

local K = {}

K["Log"] = function(ctx, msg) ctx:log(vars.text(msg)) end
K["Log Many"] = function(ctx, ...) for _, m in ipairs({ ... }) do ctx:log(vars.text(m)) end end
K["No Operation"] = function() end
K["Comment"] = function() end
K["Fail"] = function(_, msg) fail(msg and vars.text(msg) or "AssertionError") end
K["Skip"] = function(_, msg) error({ robot = true, skip = true, message = msg and vars.text(msg) or "Skipped" }, 0) end
K["Should Be Equal"] = function(_, a, b, msg)
  if not eq(a, b) then fail(msg or ("%s != %s"):format(vars.text(a), vars.text(b))) end
end
K["Should Not Be Equal"] = function(_, a, b, msg)
  if eq(a, b) then fail(msg or ("%s == %s"):format(vars.text(a), vars.text(b))) end
end
K["Should Be Equal As Numbers"] = function(_, a, b, msg)
  if tonumber(a) ~= tonumber(b) then fail(msg or ("%s != %s"):format(vars.text(a), vars.text(b))) end
end
K["Should Be Equal As Strings"] = function(_, a, b, msg)
  if vars.text(a) ~= vars.text(b) then fail(msg or ("%s != %s"):format(vars.text(a), vars.text(b))) end
end
K["Should Be True"] = function(ctx, expr, msg)
  local v = expr
  if type(expr) == "string" then v = M.eval(ctx, expr) end   -- not and/or: an expression may be false
  if not v then fail(msg or ("'%s' should be true."):format(vars.text(expr))) end
end
K["Should Not Be True"] = function(ctx, expr, msg)
  local v = expr
  if type(expr) == "string" then v = M.eval(ctx, expr) end   -- not and/or: an expression may be false
  if v then fail(msg or ("'%s' should not be true."):format(vars.text(expr))) end
end
K["Should Contain"] = function(_, c, item, msg)
  if not contains(c, item) then fail(msg or ("'%s' does not contain '%s'"):format(vars.text(c), vars.text(item))) end
end
K["Should Not Contain"] = function(_, c, item, msg)
  if contains(c, item) then fail(msg or ("'%s' contains '%s'"):format(vars.text(c), vars.text(item))) end
end
K["Should Be Empty"] = function(_, x, msg)
  if length(x) ~= 0 then fail(msg or ("'%s' should be empty."):format(vars.text(x))) end
end
K["Should Not Be Empty"] = function(_, x, msg)
  if length(x) == 0 then fail(msg or ("'%s' should not be empty."):format(vars.text(x))) end
end
K["Length Should Be"] = function(_, x, n, msg)
  if length(x) ~= tonumber(n) then
    fail(msg or ("Length of '%s' should be %s but is %d."):format(vars.text(x), vars.text(n), length(x)))
  end
end
K["Should Match Regexp"] = function(_, s, pattern, msg)
  if not vars.text(s):find(pattern) then fail(msg or ("'%s' does not match '%s'"):format(vars.text(s), pattern)) end
end
K["Get Length"] = function(_, x) return length(x) end
K["Set Variable"] = function(_, ...)
  local n = select("#", ...)
  if n == 1 then return (...) end
  return { ... }
end
K["Set Test Variable"] = function(ctx, name, ...) ctx.test_scope:set(name, select("#", ...) > 0 and (...) or ctx.scope:get(name)) end
K["Set Suite Variable"] = function(ctx, name, ...) ctx.scope:set_global(name, select("#", ...) > 0 and (...) or ctx.scope:get(name)) end
K["Set Global Variable"] = K["Set Suite Variable"]
K["Create List"] = function(_, ...) return { ... } end
K["Create Dictionary"] = function(_, ...)
  local d = {}
  for _, kv in ipairs({ ... }) do
    local k, v = tostring(kv):match("^(.-)=(.*)$")
    if k then d[k] = v end
  end
  return d
end
K["Append To List"] = function(_, list, ...) for _, x in ipairs({ ... }) do list[#list + 1] = x end end
K["Catenate"] = function(_, ...)
  local parts = { ... }
  local sep = " "
  if parts[1] and tostring(parts[1]):match("^SEPARATOR=") then sep = tostring(table.remove(parts, 1)):sub(11) end
  for i, p in ipairs(parts) do parts[i] = vars.text(p) end
  return table.concat(parts, sep)
end
K["Convert To Integer"] = function(_, x)
  local n = tonumber(x)
  if not n then fail(("'%s' cannot be converted to an integer."):format(vars.text(x))) end
  return n >= 0 and math.floor(n) or math.ceil(n)
end
K["Convert To Number"] = function(_, x)
  local n = tonumber(x)
  if not n then fail(("'%s' cannot be converted to a floating point number."):format(vars.text(x))) end
  return n
end
K["Convert To String"] = function(_, x) return vars.text(x) end
K["Evaluate"] = function(ctx, expr) return M.eval(ctx, expr) end
K["Run Keyword"] = function(ctx, name, ...) return ctx:call(name, { ... }) end
K["Run Keyword If"] = function(ctx, cond, name, ...)
  if M.eval(ctx, cond) then return ctx:call(name, { ... }) end
end
K["Run Keyword And Return Status"] = function(ctx, name, ...)
  local ok = pcall(ctx.call, ctx, name, { ... })
  return ok
end
K["Run Keyword And Ignore Error"] = function(ctx, name, ...)
  local ok, v = pcall(ctx.call, ctx, name, { ... })
  if ok then return { "PASS", v } end
  return { "FAIL", type(v) == "table" and v.message or tostring(v) }
end
K["Run Keyword And Expect Error"] = function(ctx, expected, name, ...)
  local ok, v = pcall(ctx.call, ctx, name, { ... })
  if ok then fail(("Expected error '%s' did not occur."):format(vars.text(expected))) end
  local msg = type(v) == "table" and v.message or tostring(v)
  local glob = "^" .. vars.text(expected):gsub("[%^%$%(%)%%%.%[%]%+%-%?]", "%%%0"):gsub("%*", ".*") .. "$"
  if expected ~= "*" and not msg:find(glob) then fail(("Expected error '%s' but got '%s'."):format(vars.text(expected), msg)) end
  return msg
end

M.keywords = {}
for name, fn in pairs(K) do M.keywords[norm(name)] = { name = name, fn = fn } end

return M
