-- The repairs of 2026-10-06 (claims/repairs.robot): a revision never loses a test, and a stall plans again. Each
-- rule broken once; bench/terminal/repairs_test.lua must fail for every one.
return {
  dir = "../tablua-local",
  cmd = "cd bench/terminal && luajit repairs_test.lua",
  { "bench/terminal/tests.lua", "if #now >= #was then return {} end", "if true then return {} end",
    "a shrinking suite let through" },
  { "bench/terminal/tests.lua", "if not have[n] then gone", "if have[n] then gone", "the wrong tests named as lost" },
  { "bench/terminal/policy.lua", "if since >= M.stall then", "if false then", "no stall switch" },
  { "bench/terminal/policy.lua", "(req.best_at or 0) + 1, -1", "1, -1", "steps before the last gain counted" },
  { "bench/terminal/policy.lua", "if steps[i].verb == \"plan_tests\" then break end", "",
    "planning does not reset the stall" },
}
