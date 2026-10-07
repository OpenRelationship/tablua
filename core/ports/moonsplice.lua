-- The Moonsplice engine port: the commands of cadence/docs/ROWS.md ("The engine commands tablua calls"), each run
-- through the host's exec and read back as JSON. Outside the Studio this shells out to bin/moonsplice; inside it, the
-- engine's Session serves the same ops, and a host gives a port with these methods instead.
--
--   local m = require("ports.moonsplice").new(host, { bin = ".../bin/moonsplice", tmp = dir, timeout? })
--     host.exec(cmd, timeout) -> { code, stdout, stderr }   host.write(path, text) (patch files)
--   m:rows(comp) -> { schema, tables, digest }      m:brief(comp) -> text   the comp as a model reads it
--   m:patch(comp, patches) -> { applied, rejected = { { patch, why } }, touched, digest_before, digest_after, findings }
--   m:expect(comp, rows) -> { added, rejected = { { row, why } }, digest_before, digest_after, findings }   the ask as
--                         predicates (ROWS.md, "Expectations"), added once by the harness: no patch move touches them
--   m:lint(comp) -> findings      m:check(comp) -> findings      m:sheet(comp, out_png) -> { picks, seconds }
--
-- Every command prints JSON and exits 0 when it ran; any other exit is the command failing, raised with its stderr.
-- A rejected patch is data. COMP is written back in rows form by patch.
local json = require("ports.json")

local M = {}
local P = {}
P.__index = P

M.timeout = 300

local function quote(s) return "'" .. tostring(s):gsub("'", [['\'']]) .. "'" end

function M.new(host, opts)
  assert(host and host.exec, "moonsplice needs a host with exec")
  opts = opts or {}
  return setmetatable({ host = host, bin = opts.bin or "bin/moonsplice", tmp = opts.tmp or "/tmp",
    timeout = opts.timeout or M.timeout, n = 0 }, P)
end

function P:run(...)
  local parts = { quote(self.bin) }
  for i, a in ipairs({ ... }) do parts[i + 1] = i == 1 and a or quote(a) end
  parts[#parts + 1] = "--json"
  local cmd = table.concat(parts, " ")
  local r = self.host.exec(cmd, self.timeout)
  if not r or r.code ~= 0 then
    error(("moonsplice %s failed (%s): %s"):format(parts[2], tostring(r and r.code), tostring(r and r.stderr or "")), 0)
  end
  local ok, v = pcall(json.decode, r.stdout or "")
  if not ok or type(v) ~= "table" then
    error(("moonsplice %s printed no JSON: %s"):format(parts[2], tostring(r.stdout):sub(1, 200)), 0)
  end
  return v
end

function P:rows(comp) return self:run("rows", comp) end

-- the comp as a model reads it (ROWS.md: rows --brief), text rather than JSON
function P:brief(comp)
  local cmd = ("%s rows %s --brief"):format(quote(self.bin), quote(comp))
  local r = self.host.exec(cmd, self.timeout)
  if not r or r.code ~= 0 then
    error(("moonsplice rows --brief failed (%s): %s"):format(tostring(r and r.code), tostring(r and r.stderr or "")), 0)
  end
  return r.stdout or ""
end
function P:lint(comp) return self:run("lint", comp).findings or {} end
function P:check(comp) return self:run("check", comp).findings or {} end
function P:sheet(comp, out) return self:run("sheet", comp, out) end

function P:patch(comp, patches)
  assert(self.host.write, "moonsplice patch needs a host with write")
  self.n = self.n + 1
  local path = ("%s/patches-%d.json"):format(self.tmp, self.n)
  self.host.write(path, json.encode(json.array(patches)))
  return self:run("patch", comp, path)
end

function P:expect(comp, rows)
  assert(self.host.write, "moonsplice expect needs a host with write")
  self.n = self.n + 1
  local path = ("%s/expect-%d.json"):format(self.tmp, self.n)
  self.host.write(path, json.encode(json.array(rows)))
  return self:run("expect", comp, path)
end

return M
