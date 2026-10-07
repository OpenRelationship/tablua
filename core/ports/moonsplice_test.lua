-- Unit cases for the Moonsplice engine port with a fake host: each command line as the engine takes it, paths
-- quoted, patches written to a file first, JSON read back, and a failed command an error with its stderr.
local spec = require("spec")
local moonsplice = require("ports.moonsplice")
local json = require("ports.json")

local function host(replies)
  local h = { ran = {}, wrote = {} }
  function h.exec(cmd, timeout)
    h.ran[#h.ran + 1] = { cmd = cmd, timeout = timeout }
    return table.remove(replies, 1)
  end
  function h.write(path, text) h.wrote[path] = text end
  return h
end

local function ok(v) return { code = 0, stdout = json.encode(v), stderr = "" } end

spec.test("rows, lint, check and sheet are one command each, their JSON read back", function()
  local h = host({ ok({ schema = "msr/1", tables = { node = { { id = "a", kind = "rect" } } }, digest = "d0" }),
    ok({ findings = { { tier = "lint", id = "a", code = "off_frame", severity = "error" } } }), ok({ findings = {} }),
    ok({ picks = { 0, 6 }, seconds = 2.5 }) })
  local m = moonsplice.new(h, { bin = "/m/bin/moonsplice" })
  local rows = m:rows("/w/comp's.lua")
  local lint, check, sheet = m:lint("/w/c.lua"), m:check("/w/c.lua"), m:sheet("/w/c.lua", "/w/s.png")
  spec.same({ rows.digest, lint[1].code, #check, sheet.seconds }, { "d0", "off_frame", 0, 2.5 })
  spec.same({ h.ran[1].cmd, h.ran[2].cmd, h.ran[4].cmd }, { [['/m/bin/moonsplice' rows '/w/comp'\''s.lua' --json]],
    "'/m/bin/moonsplice' lint '/w/c.lua' --json", "'/m/bin/moonsplice' sheet '/w/c.lua' '/w/s.png' --json" })
end)

spec.test("a patch list goes to a file, then to the engine, and its result comes back whole", function()
  local result = { applied = { { move = "set_prop", id = "a", name = "y", value = 220 } }, rejected = {},
    touched = { { id = "a", name = "y" } }, digest_before = "d0", digest_after = "d1", findings = {} }
  local h = host({ ok(result) })
  local m = moonsplice.new(h, { bin = "moonsplice", tmp = "/tmp/t" })
  local got = m:patch("/w/c.lua", { { move = "set_prop", id = "a", name = "y", value = 220 } })
  spec.same({ got.digest_after, got.touched[1].name, json.decode(h.wrote["/tmp/t/patches-1.json"])[1].value },
    { "d1", "y", 220 })
  spec.eq(h.ran[1].cmd, "'moonsplice' patch '/w/c.lua' '/tmp/t/patches-1.json' --json")
end)

spec.test("a command that failed is an error with what it said; output that is not JSON is one too", function()
  local m = moonsplice.new(host({ { code = 2, stdout = "", stderr = "no such comp" }, { code = 0, stdout = "oops" } }), {})
  spec.err(function() m:rows("/x.lua") end, "no such comp")
  spec.err(function() m:rows("/x.lua") end)
end)

spec.run()
