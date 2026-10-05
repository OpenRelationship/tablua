-- Tablua's test library: named cases, five checks and TAP output, in portable Lua.
--   local spec = require("spec")
--   spec.test("adds", function() spec.eq(1 + 1, 2) end)
--   spec.run()   -- prints TAP, exits non-zero on a failure
local S = { cases = {} }

function S.test(name, fn) S.cases[#S.cases + 1] = { name = name, fn = fn } end

-- A failed check is a table, so run() can print its message without a traceback into this file.
local function fail(msg)
  error(setmetatable({ spec = true, msg = msg }, { __tostring = function(e) return e.msg end }), 3)
end

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function S.eq(got, want, label)
  if got ~= want then
    fail(string.format("%sexpected %s, got %s", label and (label .. ": ") or "", show(want), show(got)))
  end
end

function S.ok(v, label)
  if not v then fail((label or "assertion") .. " is falsy") end
end

function S.err(fn, pattern)
  local okay, e = pcall(fn)
  if okay then fail("expected an error") end
  if pattern and not tostring(e):find(pattern) then
    fail(string.format("error %q does not match %q", tostring(e), pattern))
  end
end

-- Deep equality: tables match key for key, anything else by ==; the message names the first path that differs.
local function same(a, b, path)
  if type(a) ~= "table" or type(b) ~= "table" then
    if a ~= b then fail(string.format("%s: expected %s, got %s", path, show(b), show(a))) end
    return
  end
  for k, v in pairs(a) do same(v, b[k], path .. "." .. tostring(k)) end
  for k in pairs(b) do
    if a[k] == nil then fail(path .. "." .. tostring(k) .. " missing") end
  end
end

function S.same(a, b, path) same(a, b, path or "value") end

function S.run()
  local failed = 0
  io.stdout:write(string.format("TAP version 13\n1..%d\n", #S.cases))
  for i, c in ipairs(S.cases) do
    local okay, e = xpcall(c.fn, function(err)
      if type(err) == "table" and err.spec then return err.msg end
      return debug.traceback(tostring(err), 2)
    end)
    if okay then
      io.stdout:write(string.format("ok %d - %s\n", i, c.name))
    else
      failed = failed + 1
      io.stdout:write(string.format("not ok %d - %s\n", i, c.name))
      for line in tostring(e):gmatch("[^\n]+") do io.stdout:write("# ", line, "\n") end
    end
  end
  io.stdout:write(string.format("# %d passed, %d failed\n", #S.cases - failed, failed))
  if failed > 0 then os.exit(1) end
end

return S
