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

spec.test("the steps read from Tablua: Jev's probability for the move taken, and how the step ended", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"))
  t:candidates("r1", 1, { { move = "apps", jev_p = 0.8 }, { move = "press", jev_p = 0.1 } })
  t:decision{ task = "r1", n = 1, chosen = "apps", by = "jev" }
  t:outcome{ task = "r1", n = 1, verb = "apps", outcome = "complete" }
  t:decision{ task = "r1", n = 2, chosen = "press", by = "jev" }   -- no probability from Jev
  t:outcome{ task = "r1", n = 2, verb = "press", outcome = "broken" }
  local steps = calibrate.steps(t)
  spec.eq(#steps, 1)
  spec.eq(steps[1].p, 0.8)
  spec.eq(steps[1].outcome, "complete")
end)

spec.run()
