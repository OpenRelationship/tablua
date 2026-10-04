-- Unit cases for agent/calibrate.lua: Jev's sureness set beside how steps turned out.
local spec = require("mono.spec")
local calibrate = require("agent.calibrate")

spec.test("bands, Brier and the calibration error, with a no left out", function()
  local r = calibrate.report({ { p = 0.9, outcome = "complete" }, { p = 0.9, outcome = "broken" },
    { p = 0.1, outcome = "broken" }, { p = 0.5, outcome = "denied" } })
  spec.eq(r.n, 3)
  spec.eq(r.denied, 1)
  spec.ok(math.abs(r.brier - (0.01 + 0.81 + 0.01) / 3) < 1e-9)
  spec.eq(r.bands[5].n, 2)
  spec.eq(r.bands[5].worked, 0.5)
  spec.ok(calibrate.render(r):find("too sure by 0.40", 1, true))
end)

spec.test("no probabilities yet", function()
  spec.eq(calibrate.render(calibrate.report({})), "No step has a probability from Jev yet.")
end)

spec.run()
