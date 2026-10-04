-- Unit cases for agent/checkpoint.lua: a step's outcome to memory and to the world, TabPFN asked only once Jev is
-- stuck, and Jev's judgement of a finished request.
local spec = require("mono.spec")
local checkpoint = require("agent.checkpoint")

local function agent(opts)
  local log = {}
  local a = { name = "Fern", log = log,
    world = { tools = { { name = "run" }, { name = "look" } }, state = function() return "state" end,
      after = function(_, _, step) log[#log + 1] = "after " .. step.verb end,
      judged = function(_, _, label) log[#log + 1] = "judged " .. label end },
    env = { memory = { step = function(_, _, s) log[#log + 1] = "step " .. s.verb .. " " .. s.outcome end,
      sure = function(_, _, n) log[#log + 1] = "sure " .. n end,
      outcome = function(_, _, label) log[#log + 1] = "outcome " .. label end },
      learn = opts.learn, jev = opts.jev } }
  return a, log
end

spec.test("a step's outcome goes to memory, its sureness, then the world", function()
  local a, log = agent({})
  local req = { task = "t", steps = {} }
  local step = { n = 1, verb = "run", outcome = "complete", sure = { p = 0.8 } }
  req.steps[1] = step
  checkpoint.after(a, req, step)
  spec.same(log, { "step run complete", "sure 1", "after run" })
  spec.ok(req.acted)
end)

spec.test("TabPFN ranks the world's tools only after enough failed steps", function()
  local ranked = 0
  local learn = { rank = function(_, _, _, names) ranked = ranked + 1; return { { name = names[2], p = 0.7 } } end,
    record_line = function() return "not scored yet" end }
  local a = agent({ learn = learn })
  local req = { text = "x", steps = { { verb = "run", outcome = "broken" } } }
  checkpoint.before(a, req)
  spec.eq(ranked, 0)
  req.steps[2] = { verb = "run", outcome = "no_effect" }
  checkpoint.before(a, req)
  spec.eq(ranked, 1)
  spec.ok(checkpoint.card(req):find("look 0.70", 1, true))
end)

spec.test("in rank mode every building decision ranks the allowed moves, and the step keeps where it stood", function()
  local seen
  local learn = { rank = function(_, _, ctx, names) seen = { ctx = ctx, names = names }; return { { name = names[1], p = 0.6 } } end,
    record_line = function() return "not scored yet" end }
  local a, log = agent({ learn = learn })
  a.env.rank = true
  a.world.allowed = function() return { "write_steps", "rewrite" } end
  local req = { task = "t", text = "x", steps = {}, stage = "building", pass = 0.5 }
  checkpoint.before(a, req)
  spec.same(seen.names, { "write_steps", "rewrite" })
  spec.eq(seen.ctx.stage, "building")
  spec.eq(seen.ctx.pass, 0.5)
  spec.ok(req.ranked_all)
  -- the step this decision becomes is remembered with the stage it was taken in
  local m
  a.env.memory.step = function(_, _, s) m = s end
  local step = { n = 1, verb = "write_steps", outcome = "complete" }
  req.steps[1] = step
  checkpoint.after(a, req, step)
  spec.eq(m.stage, "building")
  spec.eq(m.pass, 0.5)
  -- and outside the ranked stages it waits for failures as before
  seen, req.stage = nil, "ready"
  checkpoint.before(a, req)
  spec.eq(seen, nil)
  spec.eq(req.ranked_all, nil)
end)

spec.test("shadow mode ranks every building decision for the record, and Jev never reads it", function()
  local learn = { rank = function(_, _, _, names) return { { name = names[2], p = 0.9 }, { name = names[1], p = 0.1 } } end,
    record_line = function() return "not scored yet" end }
  local a = agent({ learn = learn })
  a.env.shadow = true
  a.world.allowed = function() return { "write_steps", "rewrite" } end
  local req = { task = "t", text = "x", steps = {}, stage = "building" }
  checkpoint.before(a, req)
  spec.eq(req.ranking[1].name, "rewrite")
  spec.ok(req.ranked_all)
  spec.eq(checkpoint.card(req, a.env), nil)
  spec.ok(checkpoint.card(req, { rank = true }):find("rewrite 0.90", 1, true))
end)

spec.test("Jev judges a finished request, and the world hears the label", function()
  local a, log = agent({ jev = { decide = function() return { ended = { choice = "complete" } } end } })
  a.judging = { req = { task = "t", steps = {} }, said = "Done." }
  checkpoint.judge(a)
  spec.same(log, { "outcome complete", "judged complete" })
end)

spec.run()
