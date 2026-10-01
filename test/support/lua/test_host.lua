-- The test host's additions to the base state: mono.spec driven case by case,
-- the io.open, os.tmpname and os.remove the tests use
-- (tv-labs lua has no io library).
local spec = require("mono.spec")

-- mono.spec's run prints TAP and exits; the host reports each case instead.
spec.run = function() end

-- Runs one unit test file; every case as { name, ok, err }.
function arock.unit(name, src)
  local f = assert(load(src, "=" .. name))
  f()
  local out = {}
  for i, c in ipairs(spec.cases) do
    local ok, e = pcall(c.fn)
    out[i] = { name = c.name, ok = ok, err = (not ok) and (type(e) == "table" and e.msg or tostring(e)) or nil }
  end
  return out
end

io = {
  open = function(path, mode)
    local writing, buf = mode and mode:find("w"), {}
    if not writing then
      local s = __test.read(path)
      if not s then return nil, path .. ": No such file or directory" end
      buf[1] = s
    end
    return {
      write = function(self, s) buf[#buf + 1] = s; return self end,
      read = function() return table.concat(buf) end,
      close = function() if writing then __test.write(path, table.concat(buf)) end; return true end,
    }
  end,
}
os.tmpname = function() return __test.tmpname() end
os.remove = function(path) return __test.remove(path) end

-- One Jev choice through ports.jev over the host's fetch and key.
function arock.decide(state, id, text, options)
  local host = arock.host()
  local jev = require("ports.jev").new(host, { key = host.key("jev") })
  local answers, record = jev:decide(state, { [id] = { kind = "choice", text = text, options = options } })
  return answers[id].choice, record.tries, record.status
end
