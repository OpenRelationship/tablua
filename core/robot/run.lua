-- Runs a suite (robot.parse) against keyword libraries, in portable Lua, and keeps every keyword's result as a
-- tree: what ran, with which arguments, whether it passed, failed or never ran, why, and how long it took.
--
--   local run = require("robot.run")
--   local lib = run.library()
--   lib:add("Add Plant", function(name) ... end)             a keyword in Lua: an error fails it
--   lib:add('The list holds "${n}" items', function(n) ... end)   embedded arguments in the name
--   run.suite(suite, { libraries = { lib }, clock?, variables?, only? }) -> result
--     result { status, passed, failed, skipped, total, setup?, teardown?, tests = { test } }
--     test   { name, status, message, ms, tags, line, setup?, teardown?, body = { node } }
--     node   { type, name, args, status, message, ms, line, children = { node }, undefined? }
--       type: keyword | for | iteration | if | branch | return; status: PASS | FAIL | SKIP | NOT RUN
--
-- A keyword is found among the suite's own keywords, then the libraries, then BuiltIn (robot.builtin), by name
-- with case, spaces and underscores ignored; a name that matches none is tried again without a leading Given,
-- When, Then, And or But, as Robot does. After a failure the rest of its body is recorded as NOT RUN.
local vars = require("robot.vars")
local builtin = require("robot.builtin")

local M = {}

local norm, fail = builtin.norm, builtin.fail
local unpack_ = function(t) return (table.unpack or unpack)(t, 1, t.n or #t) end
local PREFIX = { given = true, ["when"] = true, ["then"] = true, ["and"] = true, but = true }

-- Libraries --------------------------------------------------------------------------------------------------------

local Lib = {}
Lib.__index = Lib

function M.library() return setmetatable({ exact = {}, embedded = {} }, Lib) end

-- a name with ${arg} parts as a Lua pattern over the lowercased called name: each argument is captured by the
-- positions around it, so it is cut from the call as written, not lowercased
local function embedded(name)
  if not name:find("%${") then return nil end
  local out, at = { "^" }, 1
  while true do
    local s, e = name:find("%${[^}]+}", at)
    local lit = name:sub(at, (s or #name + 1) - 1):lower():gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    out[#out + 1] = lit
    if not s then break end
    out[#out + 1] = "()(.-)()"
    at = e + 1
  end
  out[#out + 1] = "$"
  return table.concat(out)
end
M.embedded = embedded

-- the arguments a called name gives an embedded pattern, or nil when it does not match
local function captures(pattern, name)
  local m = { name:lower():match(pattern) }
  if #m == 0 then return nil end
  local out = {}
  for i = 1, #m, 3 do out[#out + 1] = name:sub(m[i], m[i + 2] - 1) end
  return out
end
M.captures = captures

function Lib:add(name, fn)
  local pat = embedded(name)
  if pat then self.embedded[#self.embedded + 1] = { name = name, pattern = pat, fn = fn }
  else self.exact[norm(name)] = { name = name, fn = fn } end
end

function Lib:find(name)
  local k = self.exact[norm(name)]
  if k then return k end
  for _, e in ipairs(self.embedded) do
    local caps = captures(e.pattern, name)
    if caps then return { name = e.name, fn = e.fn, captured = caps } end
  end
end

function Lib:names()
  local out = {}
  for _, k in pairs(self.exact) do out[#out + 1] = k.name end
  for _, e in ipairs(self.embedded) do out[#out + 1] = e.name end
  table.sort(out)
  return out
end

-- Running ------------------------------------------------------------------------------------------------------------

local Ctx = {}
Ctx.__index = Ctx

local function now(ctx) return ctx.clock and ctx.clock() or 0 end

local function message(err)
  if type(err) == "table" then return err.message or "error", err.skip end
  return tostring(err), false
end

function Ctx:log(text) self.logs[#self.logs + 1] = text end

-- the suite's keywords first, then each library's, then BuiltIn
function Ctx:find(name)
  local user = self.user[norm(name)]
  if user then return { user = user, name = user.name } end
  for _, e in ipairs(self.user_embedded) do
    local caps = captures(e.pattern, name)
    if caps then return { user = e.kw, name = e.kw.name, captured = caps } end
  end
  for _, lib in ipairs(self.libraries) do
    local k = lib:find(name)
    if k then return k end
  end
  local b = builtin.keywords[norm(name)]
  if b then return { name = b.name, fn = b.fn, ctx = true } end
end

function Ctx:resolve(name)
  local k = self:find(name)
  if k then return k end
  local first, rest = name:match("^(%a+)%s+(.+)$")
  if first and PREFIX[first:lower()] then return self:find(rest) end
end

local exec_body

-- runs one keyword by name with argument values; its node is a child of the current one
function Ctx:call(name, args, line)
  local node = { type = "keyword", name = name, args = {}, status = "PASS", line = line, children = {} }
  for i = 1, args.n or #args do node.args[i] = vars.text(args[i]) end
  local parent = self.node
  parent.children[#parent.children + 1] = node
  local t0 = now(self)
  self.node = node
  local k = self:resolve(name)
  local ok, ret = pcall(function()
    if not k then
      node.undefined = true
      fail(("No keyword with name '%s' found."):format(name))
    end
    node.name = k.name
    local list = {}
    for i, c in ipairs(k.captured or {}) do list[i] = c end
    for i = 1, args.n or #args do list[#list + 1] = args[i] end
    if k.user then return self:user_keyword(k.user, list) end
    if k.ctx then return k.fn(self, unpack_(list)) end
    return k.fn(unpack_(list))
  end)
  self.node = parent
  node.ms = (now(self) - t0) * 1000
  if not ok then
    local msg, skip = message(ret)
    node.status, node.message = skip and "SKIP" or "FAIL", msg
    error({ robot = true, message = msg, skip = skip, reported = true }, 0)
  end
  return ret
end

function Ctx:user_keyword(kw, list)
  local saved = self.scope
  self.scope = vars.scope(self.test_scope or self.suite_scope)
  local n = 0
  for _, a in ipairs(kw.args) do
    local name, default = a:match("^([%$@&]{[^}]+})=(.*)$")
    name = name or a
    if name:sub(1, 1) == "@" then
      local rest = {}
      for i = n + 1, #list do rest[#rest + 1] = list[i] end
      self.scope:set(name, rest)
      n = #list
    else
      n = n + 1
      local v = list[n]
      if v == nil then
        if default == nil then
          self.scope = saved
          fail(("Keyword '%s' expected %d arguments, got %d."):format(kw.name, #kw.args, #list))
        end
        v = vars.value(self.scope, default)
      end
      self.scope:set(name, v)
    end
  end
  local ok, err = pcall(exec_body, self, kw.body)
  local ret
  if ok and type(err) == "table" and err.returned then ret = err.value end
  if ok and kw.returns then
    local vals = vars.args(self.scope, kw.returns)
    ret = vals.n == 1 and vals[1] or vals
  end
  self.scope = saved
  if not ok then error(err, 0) end
  return ret
end

-- the items of a body not run after a failure, as NOT RUN nodes
local function skipped(ctx, items, from)
  for i = from, #items do
    local it = items[i]
    if it.kind == "call" then
      ctx.node.children[#ctx.node.children + 1] = { type = "keyword", name = it.keyword, args = it.args,
        status = "NOT RUN", line = it.line, children = {} }
    end
  end
end

local function block(ctx, typ, name, line)
  local node = { type = typ, name = name, args = {}, status = "PASS", line = line, children = {} }
  ctx.node.children[#ctx.node.children + 1] = node
  return node
end

local function exec_item(ctx, it)
  if it.kind == "call" then
    local v = ctx:call(vars.value(ctx.scope, it.keyword), vars.args(ctx.scope, it.args), it.line)
    if it.assign then
      if #it.assign == 1 then ctx.scope:set(it.assign[1], v)
      else for i, a in ipairs(it.assign) do ctx.scope:set(a, type(v) == "table" and v[i] or nil) end end
    end
  elseif it.kind == "return" then
    local vals = vars.args(ctx.scope, it.values)
    return { returned = true, value = vals.n == 1 and vals[1] or (vals.n > 0 and vals or nil) }
  elseif it.kind == "break" or it.kind == "continue" then
    return { [it.kind] = true }
  elseif it.kind == "for" then
    local node = block(ctx, "for", "FOR " .. table.concat(it.vars, " ") .. " " .. it.flavor:upper(), it.line)
    local values = vars.args(ctx.scope, it.values)
    local list = {}
    if it.flavor == "range" then
      local a, b, step = tonumber(values[1]), tonumber(values[2]), tonumber(values[3]) or 1
      if not b then a, b = 0, a end
      for i = a, b - (step > 0 and 1 or -1), step do list[#list + 1] = i end
    else
      for i = 1, values.n do list[i] = values[i] end
    end
    local parent = ctx.node
    for i = 1, #list, #it.vars do
      local iter = { type = "iteration", name = "", args = {}, status = "PASS", line = it.line, children = {} }
      node.children[#node.children + 1] = iter
      for j, v in ipairs(it.vars) do ctx.scope:set(v, list[i + j - 1]) end
      ctx.node = iter
      local ok, sig = pcall(exec_body, ctx, it.body)
      ctx.node = parent
      if not ok then iter.status, node.status = "FAIL", "FAIL"; error(sig, 0) end
      if sig and sig.returned then return sig end
      if sig and sig["break"] then break end
    end
  elseif it.kind == "if" then
    local node = block(ctx, "if", "IF", it.line)
    local parent = ctx.node
    local chosen
    for _, b in ipairs(it.branches) do
      if builtin.eval(ctx, b.cond) then chosen = b.body break end
    end
    chosen = chosen or it.otherwise
    if chosen then
      ctx.node = node
      local ok, sig = pcall(exec_body, ctx, chosen)
      ctx.node = parent
      if not ok then node.status = "FAIL"; error(sig, 0) end
      return sig
    end
  end
end

exec_body = function(ctx, items)
  for i, it in ipairs(items) do
    local ok, sig = pcall(exec_item, ctx, it)
    if not ok then
      skipped(ctx, items, i + 1)
      error(sig, 0)
    end
    if sig then return sig end
  end
end

-- a setup or teardown: one keyword, its node kept apart from the body
local function fixture(ctx, f, typ)
  if not f or not f.keyword or f.keyword == "" or f.keyword:upper() == "NONE" then return nil, true end
  local holder = { type = typ, children = {} }
  local saved = ctx.node
  ctx.node = holder
  local ok, err = pcall(ctx.call, ctx, vars.value(ctx.scope, f.keyword), vars.args(ctx.scope, f.args))
  ctx.node = saved
  local node = holder.children[1]
  if node then node.type = typ end
  return node, ok, err
end

local function run_test(ctx, t, settings)
  local res = { name = t.name, status = "PASS", tags = {}, line = t.line, body = {} }
  for _, x in ipairs(settings.tags or {}) do res.tags[#res.tags + 1] = x end
  for _, x in ipairs(t.tags or {}) do res.tags[#res.tags + 1] = x end
  ctx.test_scope = vars.scope(ctx.suite_scope)
  ctx.scope = ctx.test_scope
  local t0 = now(ctx)
  local setup, ok, err = fixture(ctx, t.setup or settings.test_setup, "setup")
  res.setup = setup
  if ok then
    ctx.node = { children = res.body }
    ok, err = pcall(exec_body, ctx, t.body)
  else
    ctx.node = { children = res.body }
    skipped(ctx, t.body, 1)
  end
  if not ok then
    local msg, skip = message(err)
    res.status, res.message = skip and "SKIP" or "FAIL", msg
  end
  local teardown, tok, terr = fixture(ctx, t.teardown or settings.test_teardown, "teardown")
  res.teardown = teardown
  if not tok and res.status == "PASS" then res.status, res.message = "FAIL", "Teardown failed: " .. message(terr) end
  res.ms = (now(ctx) - t0) * 1000
  return res
end

function M.suite(suite, opts)
  opts = opts or {}
  local ctx = setmetatable({ libraries = opts.libraries or {}, clock = opts.clock, logs = {}, user = {},
    user_embedded = {} }, Ctx)
  for _, kw in ipairs(suite.keywords) do
    local pat = embedded(kw.name)
    if pat then ctx.user_embedded[#ctx.user_embedded + 1] = { pattern = pat, kw = kw }
    else ctx.user[norm(kw.name)] = kw end
  end
  ctx.suite_scope = vars.scope()
  ctx.scope = ctx.suite_scope
  for name, v in pairs(suite.variables or {}) do
    ctx.suite_scope:set(name, type(v) == "table" and vars.args(ctx.scope, v) or vars.value(ctx.scope, v))
  end
  for name, v in pairs(opts.variables or {}) do ctx.suite_scope:set(name, v) end
  local result = { status = "PASS", passed = 0, failed = 0, skipped = 0, total = 0, tests = {}, logs = ctx.logs }
  local setup, ok, err = fixture(ctx, suite.settings.setup, "setup")
  result.setup = setup
  for _, t in ipairs(suite.tests) do
    if not opts.only or opts.only[t.name] then
      local res
      if ok then res = run_test(ctx, t, suite.settings)
      else res = { name = t.name, status = "FAIL", message = "Parent suite setup failed: " .. message(err), body = {},
        tags = {}, line = t.line, ms = 0 } end
      result.tests[#result.tests + 1] = res
      result.total = result.total + 1
      if res.status == "PASS" then result.passed = result.passed + 1
      elseif res.status == "SKIP" then result.skipped = result.skipped + 1
      else result.failed = result.failed + 1 end
    end
  end
  ctx.scope = ctx.suite_scope
  result.teardown = fixture(ctx, suite.settings.teardown, "teardown")
  if result.failed > 0 then result.status = "FAIL" end
  return result
end

return M
