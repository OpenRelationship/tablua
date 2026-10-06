-- Unit cases for the harness (agent/init.lua): Jev decides every step, a close call goes to Mercury, the agent's own
-- verbs run here and a tool verb in the world, and the loop is a state machine a host drives with no coroutine.
local spec = require("spec")
local agent = require("agent")

-- Jev answers from a script of choices, each with its probabilities; it keeps every state and question it was given.
local function jev(script)
  local j = { calls = {} }
  function j.decide(_, state, questions)
    local next = table.remove(script, 1)
    j.calls[#j.calls + 1] = { state = state, questions = questions }
    return { next = next }
  end
  return j
end

local function mercury(replies)
  local m = { asked = {} }
  function m.chat(_, req)
    m.asked[#m.asked + 1] = req
    return table.remove(replies, 1) or ""
  end
  return m
end

local function world(acted)
  return {
    tools = { { name = "run", what = "Run a command." }, { name = "look", what = "Look at a page." } },
    question = function() return { kind = "choice", text = "What next?", options = { run = "Run.", answer = "Done." } } end,
    state = function(_, req, for_jev) return (for_jev and "jev: " or "mercury: ") .. req.text end,
    arbiter = function(_, _, a, b) return { kind = "arbiter", user = a .. " or " .. b } end,
    think = function() return { kind = "think" } end,
    ask = function() return { kind = "ask" } end,
    form = function(written) return { question = written, choices = {} } end,
    act = function(_, _, verb, step)
      acted[#acted + 1] = verb
      step.lines[1] = verb .. " ran"
      step.outcome = "complete"
      if verb == "look" then return { "wait", "the page" } end
    end,
  }
end

local function choice(c, probabilities) return { choice = c, probabilities = probabilities, confidence = 0.5 } end

spec.test("Jev picks each step; answer ends the request", function()
  local acted = {}
  local j = jev({ choice("run", { run = 0.9, answer = 0.1 }), choice("answer", { run = 0.2, answer = 0.8 }) })
  local a = agent.new({ jev = j, mercury = mercury({}) }, world(acted))
  local req = a:begin("list the files")
  local next = a:step(req)
  spec.eq(next[1], "act")
  spec.eq(next[2].verb, "run")
  spec.eq(next[2].sure.p, 0.9)
  spec.eq(a:perform(req, next[2]), nil)
  a:close(req, next[2])
  spec.eq(a:step(req)[1], "done")
  spec.same(acted, { "run" })
  spec.eq(#req.steps, 1)
  spec.eq(j.calls[1].state, "jev: list the files")
  spec.eq(j.calls[1].questions.next.text, "What next?")
end)

spec.test("a close call goes to Mercury, which may take Jev's second", function()
  local heard = {}
  local j = jev({ choice("answer", { answer = 0.40, run = 0.36 }) })
  local m = mercury({ "run" })
  local a = agent.new({ jev = j, mercury = m, decided = function(_, verb, _, how) heard[#heard + 1] = verb .. "/" .. how end },
    world({}))
  local next = a:step(a:begin("do it"))
  spec.eq(next[2].verb, "run")
  spec.eq(m.asked[1].user, "answer or run")
  spec.same(heard, { "run/arbiter" })
end)

spec.test("a world without an arbiter takes Jev's pick on a close call, asking no one", function()
  local heard, m = {}, mercury({ "answer" })
  local w = world({})
  w.arbiter = nil
  local a = agent.new({ jev = jev({ choice("run", { run = 0.41, answer = 0.40 }) }), mercury = m,
    decided = function(_, verb, _, how) heard[#heard + 1] = verb .. "/" .. how end }, w)
  spec.eq(a:step(a:begin("do it"))[2].verb, "run")
  spec.eq(#m.asked, 0)
  spec.same(heard, { "run/jev" })
end)

spec.test("every decision is heard with Jev's answer and how it was settled", function()
  local heard = {}
  local a = agent.new({ jev = jev({ choice("run", { run = 0.9, answer = 0.1 }) }), mercury = mercury({}),
    decided = function(_, verb, answer, how) heard[#heard + 1] = { verb, answer.probabilities.run, how } end }, world({}))
  a:step(a:begin("x"))
  spec.same(heard, { { "run", 0.9, "jev" } })
end)

spec.test("in rank mode TabPFN's best allowed move takes the step only on a clear lead over an unsure Jev", function()
  local a = agent.new({ jev = jev({}), mercury = mercury({}), rank = true }, world({}))
  local ranking = { { name = "write_steps", p = 0.40 }, { name = "rewrite", p = 0.10 }, { name = "think", p = 0.30 } }
  local function req(sure, all) return { ranking = ranking, ranked_all = all, sure = { p = sure } } end
  spec.eq(a:overrule(req(0.6, true), "rewrite"), "write_steps")
  spec.eq(a:overrule(req(0.6, true), "think"), nil)          -- 0.10 behind: not a clear lead
  spec.eq(a:overrule(req(0.95, true), "rewrite"), nil)       -- Jev was sure
  spec.eq(a:overrule(req(0.6, nil), "rewrite"), nil)         -- a ranking of every tool, not of the moves allowed
  spec.eq(a:overrule(req(0.6, true), "write_steps"), nil)    -- Jev already picked it
  a.env.rank = nil
  spec.eq(a:overrule(req(0.6, true), "rewrite"), nil)        -- rank mode off
end)

spec.test("exploration takes another allowed or held move now and then, with the chance it had", function()
  local rolls
  local a = agent.new({ jev = jev({}), mercury = mercury({}), explore = 0.1,
    random = function() return table.remove(rolls, 1) end }, world({}))
  local q = { options = { run = "r", think = "t", publish = "p" } }
  rolls = { 0.5 }
  local m, p = a:explore({}, "run", q)
  spec.same({ m, p }, { nil, 0.9 })
  -- held moves count; the pick and the moves that stop or hand on the work never do
  rolls = { 0.05, 0.99 }
  m, p = a:explore({ held = { "fix_failure" } }, "run", q)
  spec.same({ m, p }, { "think", 0.05 })
  rolls = { 0.05, 0.0 }
  spec.same({ a:explore({ held = { "fix_failure" } }, "run", q) }, { "fix_failure", 0.05 })
  spec.same({ a:explore({}, "publish", q) }, { nil, 1 })
  a.env.explore = nil
  spec.same({ a:explore({ held = { "fix_failure" } }, "run", q) }, { nil, 1 })
end)

spec.test("an explored step is heard as explore, with its propensity", function()
  local heard = {}
  local a = agent.new({ jev = jev({ choice("run", { run = 0.9, answer = 0.1 }) }), mercury = mercury({}), explore = 1,
    random = function() return 0 end,
    decided = function(req, verb, _, how, p) heard[#heard + 1] = { verb, how, p, req.explored } end }, world({}))
  a.world.question = function()
    return { kind = "choice", text = "What next?", options = { run = "Run.", look = "Look.", answer = "Done." } }
  end
  a:step(a:begin("x"))
  spec.same(heard[1], { "look", "explore", 1, true })
end)

-- a plants run (2026-10-05): TabPFN rated blocked 0.45, tied with four moves and first by name, and took it twice,
-- ending a run Jev gave blocked 0.01
spec.test("TabPFN never takes a move that stops the work, and Jev breaks its ties", function()
  local a = agent.new({ jev = jev({}), mercury = mercury({}), rank = true }, world({}))
  local ranking = { { name = "blocked", p = 0.45 }, { name = "look_at_app", p = 0.45 }, { name = "run_check", p = 0.45 },
    { name = "run_test", p = 0.44 }, { name = "rewrite", p = 0.01 } }
  local req = { ranking = ranking, ranked_all = true, sure = { p = 0.62 } }
  local jev_p = { blocked = 0.01, look_at_app = 0.05, run_check = 0.06, run_test = 0.01, rewrite = 0.62 }
  spec.eq(a:overrule(req, "rewrite", jev_p), "run_check")
  -- and with only a stopping move ahead, Jev's pick stands
  req.ranking = { { name = "publish", p = 0.9 }, { name = "rewrite", p = 0.1 } }
  spec.eq(a:overrule(req, "rewrite", jev_p), nil)
end)

spec.test("without Jev there is no step: the request is answered", function()
  local a = agent.new({ mercury = mercury({}) }, world({}))
  spec.eq(a:step(a:begin("x"))[1], "done")
end)

spec.test("Jev unreachable ends the request and says why", function()
  local a = agent.new({ jev = { decide = function() error("timeout") end }, mercury = mercury({}) }, world({}))
  local next = a:step(a:begin("x"))
  spec.eq(next[1], "done")
  spec.ok(next[2]:find("could not reach Jev", 1, true))
end)

spec.test("think, ask and plan are the agent's own; wait and done come from the world", function()
  local acted = {}
  local m = mercury({ "check the log first", "Which file?", '{"parts": [{"goal": "a"}, {"goal": "b"}]}' })
  local a = agent.new({ jev = jev({}), mercury = m }, world(acted))
  local req = a:begin("x")
  local think = { verb = "think", lines = {} }
  spec.eq(a:perform(req, think), nil)
  spec.eq(req.guidance, "check the log first")
  local ask = { verb = "ask", lines = {} }
  local asked = a:perform(req, ask)
  spec.eq(asked[1], "ask")
  spec.eq(asked[2].question, "Which file?")
  a:answered(ask, asked[2], { value = "notes.txt" })
  spec.eq(ask.note, 'Asked the person "Which file?"; they answered "notes.txt".')
  a:perform(req, { verb = "plan", lines = {} })
  spec.same(req.parts, { "a", "b" })
  spec.same(a:perform(req, { verb = "look", lines = {} }), { "wait", "the page" })
  spec.same(acted, { "look" })
end)

spec.test("thinking that says nothing is a failed step, and the guidance before it stands", function()
  local a = agent.new({ jev = jev({}), mercury = mercury({ "read the log", "  " }) }, world({}))
  local req = a:begin("x")
  a:perform(req, { verb = "think", lines = {} })
  local empty = { verb = "think", lines = {} }
  a:perform(req, empty)
  spec.same({ empty.outcome, empty.note, #empty.lines }, { "broken", "Thinking failed: Mercury said nothing", 0 })
  spec.eq(req.guidance, "read the log")
end)

spec.test("a world's own methods fall back to the agent's", function()
  local W = agent.mix({ greet = function(self) return "hello from " .. self.name end })
  W.__index = W
  local a = setmetatable({ env = { jev = jev({ choice("answer", { answer = 1 }) }) }, world = world({}), name = "Fern",
    history = require("agent.history").new() }, W)
  spec.eq(a:greet(), "hello from Fern")
  spec.eq(a:step(a:begin("x"))[1], "done")
end)

spec.run()
