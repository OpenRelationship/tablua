-- Arock's agent (PROJECT.md §1, §11): Jev decides, Mercury fills. At each step Jev picks the verb from the world's
-- tools and the agent's own (answer, ask, think, plan, next_part), with probabilities; a close call goes to a
-- careful Mercury; TabPFN's ranking from past outcomes reaches Jev after failed steps (checkpoint.lua). The world
-- (the person's Mac, or the agent's own computer) does what a tool verb means and says how it went.
--
-- The loop is an explicit state machine, not a coroutine, so it runs on every Lua Arock targets (Moss's has no
-- coroutines): the host calls step() and does what it returns.
--
--   local agent = require("agent")
--   local a = agent.new(env, world)           env = { name?, jev, mercury, learn?, memory?, trace?, log?, refused?,
--                                               stepping?, decided? }   (or agent.mix(A) for a world's own methods)
--   local req = a:begin(text)                 a request in the person's words
--   a:step(req)    -> { "act", step } | { "done", why? }       Jev decides the next verb
--   a:perform(req, step) -> nil (the step is over) | { "ask", form } | { "wait", what } | { "done", said }
--   a:answered(step, form, reply)              the person's reply to { "ask", form }
--   a:close(req, step)                         the step is recorded and its outcome learned from
--
-- A world is a table: tools ({ name, what } in the order Jev is offered them), question(a) (Jev's choice of the
-- next verb), state(a, req, for_jev) (what both minds read), arbiter(a, req, first, second) (optional: a close
-- call's careful Mercury), think(a, req) and ask(a, req) (Mercury's requests), form(written) (the person's form
-- from Mercury's reply), act(a, req, verb, step) (a tool verb: nil when the step is over, { "wait", what } when it
-- waits on the world, { "done", said } to end the request), and optionally questions(a, req) and
-- answered(a, req, answers) (more questions in Jev's same call), after(a, req, step) and judged(a, req, label)
-- (checkpoint.lua).
-- env.decided(req, verb, answer, how), when given, hears every decision: Jev's answer with its probabilities, and
-- how it was settled ("jev", or "arbiter" when the close call went to Mercury).
local history = require("agent.history")
local parts = require("agent.parts")
local checkpoint = require("agent.checkpoint")
local clip = require("agent.clip").clip

local M = {}
local A = {}
A.__index = A
M.methods = A

M.close = 0.1   -- Jev's best two within this of each other go to a careful Mercury (arbiter.feature)

-- The agent's methods on a world's own table of methods: A falls back to them.
function M.mix(methods)
  return setmetatable(methods, { __index = A })
end

function M.new(env, world)
  return setmetatable({ env = env, world = world, name = env.name or "Arock", history = history.new() }, A)
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Mercury's text, or nil and why.
function A:mercury(req)
  local ok, text = pcall(self.env.mercury.chat, self.env.mercury, req)
  if not ok then return nil, tostring(text) end
  return trim(text)
end

-- A refusal from Arock's service (401 signed out, 402 not subscribed) is said as the service worded it, and the
-- host hears it for the console's account row. nil for any other failure.
function A:refusal(err)
  if type(err) ~= "table" or not err.status or err.status < 401 or err.status > 402 then return nil end
  if self.env.refused then self.env.refused(err) end
  -- a link is shown, not spoken: the console has the subscribe button
  return (tostring(err):gsub("%s*Subscribe at %S+$", " You can subscribe in my console."))
end

function A:decide(req)
  local w = self.world
  if not self.env.jev then return "answer" end
  local questions = { next = w.question(self) }
  if w.questions then for id, q in pairs(w.questions(self, req)) do questions[id] = q end end
  local ok, answers = pcall(self.env.jev.decide, self.env.jev, w.state(self, req, true), questions)
  if not ok then
    return nil, self:refusal(answers) or ("I could not reach Jev, who decides what I do: " .. clip(tostring(answers), 160))
  end
  if w.answered then w.answered(self, req, answers) end
  -- how sure Jev was of it, kept with the step it becomes (calibrate.lua)
  local n = answers.next
  req.sure = n.probabilities and n.choice and tonumber(n.probabilities[n.choice])
    and { p = tonumber(n.probabilities[n.choice]), confidence = tonumber(n.confidence) } or nil
  -- a close call: Jev's best two go to a careful Mercury, which picks one of them, for a world that has an arbiter
  -- (the desktop's); Tablua's has none, its close calls left to TabPFN in rank mode (issue #1 M4)
  local second, p2 = nil, -1
  for v, p in pairs(n.probabilities or {}) do
    p = tonumber(p)
    if v ~= n.choice and p and p > p2 then second, p2 = v, p end
  end
  if second and req.sure and req.sure.p - p2 < M.close and self.env.mercury and w.arbiter then
    local okm, pick = pcall(self.env.mercury.chat, self.env.mercury, w.arbiter(self, req, n.choice, second))
    pick = okm and tostring(pick):lower():match("[%a_]+")
    if pick == second then
      if self.env.decided then self.env.decided(req, second, n, "arbiter") end
      return second
    end
  end
  -- rank mode: TabPFN's best allowed move takes the step when it clearly beats Jev's pick and Jev was not sure
  local over = self:overrule(req, n.choice, n.probabilities)
  if over then
    if self.env.decided then self.env.decided(req, over, n, "tabpfn") end
    return over
  end
  if self.env.decided then self.env.decided(req, n.choice, n, "jev") end
  return n.choice
end

M.margin, M.jev_sure = 0.15, 0.9   -- TabPFN's lead over Jev's pick, and Jev's sureness above which it is kept
M.tie = 0.02                     -- TabPFN's chances this close are a tie, which Jev's probabilities break
-- the moves that stop the work or hand it on are Jev's alone: TabPFN once took blocked twice, tied at 0.45 with four
-- moves and first by name, and ended a run Jev gave blocked 0.01 (2026-10-05)
M.jev_only = { blocked = true, publish = true, answer_task = true, answer = true, wait_for_agreement = true,
  wait_for_yes = true }

-- The move to take in Jev's place, or nil: only with env.rank, a ranking of the allowed moves (checkpoint.lua), and
-- TabPFN's best ahead of Jev's pick by M.margin while Jev gave its pick less than M.jev_sure. Its best is never one of
-- M.jev_only, and among moves it rates within M.tie of each other the one Jev gave most.
function A:overrule(req, choice, jev)
  if not self.env.rank or not req.ranking or not req.ranked_all then return nil end
  local best, mine = nil, nil
  local function jp(r) return tonumber((jev or {})[r.name]) or 0 end
  for _, r in ipairs(req.ranking) do
    if r.name == choice then mine = r end
    if not M.jev_only[r.name] then
      if not best or r.p > best.p + M.tie or (r.p >= best.p - M.tie and jp(r) > jp(best)) then best = r end
    end
  end
  if not best or not mine or best.name == choice then return nil end
  if req.sure and req.sure.p >= M.jev_sure then return nil end
  if best.p - mine.p < M.margin then return nil end
  return best.name
end

-- Whoever watches the steps (env.stepping: the messenger's tool cards) hears each start, once more when its calls
-- are known (step.title), and its end; a listener that fails never stops the agent.
function A:stepping(phase, step) if self.env.stepping then pcall(self.env.stepping, phase, step) end end

-- A row in the request's memory and in the trace, where there are.
function A:rows(keyword, args)
  local task = self.req and self.req.task
  if self.env.memory and task then pcall(self.env.memory.log, self.env.memory, task, keyword, args, "agent") end
  if self.env.trace then self.env.trace:row(keyword, args) end
end

function A:begin(text)
  local req = { text = text, steps = {} }
  req.task = self.env.memory and self.env.memory:begin(text)
  self.req = req
  self.history:begin()
  self.history:person(text)
  return req
end

-- Jev decides the next verb: { "act", step } for a step to perform, { "done", why } when the request is finished
-- (Jev answered), or could not go on (why says so).
function A:step(req)
  checkpoint.before(self, req)
  local verb, why = self:decide(req)
  if not verb or verb == "answer" then return { "done", why } end
  return { "act", { verb = verb, lines = {}, sure = req.sure } }
end

-- The step's verb is done: the agent's own verbs here, a tool verb by the world.
function A:perform(req, step)
  local verb = step.verb
  if verb == "think" then
    local guidance, err = self:mercury(self.world.think(self, req))
    if guidance then step.lines[1] = "guidance: " .. guidance else step.note = "Thinking failed: " .. tostring(err) end
    req.guidance = guidance or req.guidance
  elseif verb == "ask" then
    local written, err = self:mercury(self.world.ask(self, req))
    if not written then step.note = "Writing the question failed: " .. tostring(err) return nil end
    return { "ask", self.world.form(written) }
  elseif verb == "plan" or verb == "next_part" then
    parts[verb == "plan" and "plan" or "next"](self, req, step)
  else
    return self.world.act(self, req, verb, step)
  end
end

function A:answered(step, f, reply)
  step.note = reply.value and ("Asked the person %q; they answered %q."):format(f.question, reply.value)
    or ("Asked the person %q; they said something else, just above."):format(f.question)
end

-- A step is part of the request and of the conversation once it is over, so what was asked and answered on
-- the way comes before it.
function A:record(req, step)
  step.n = #req.steps + 1
  req.steps[step.n] = step
  self.history:step(step)
  self:stepping("done", step)
  if self.env.log then
    for _, l in ipairs(step.lines) do self.env.log(l) end
    if step.note then self.env.log(step.note) end
  end
end

function A:close(req, step)
  self:record(req, step)
  checkpoint.after(self, req, step)
end

return M
