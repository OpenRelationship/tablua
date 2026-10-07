-- The agent: Jev decides, Mercury fills. At each step Jev picks the verb from the world's
-- tools and the agent's own (answer, ask, think, plan, next_part), with probabilities; a close call goes to a
-- careful Mercury; TabPFN's ranking from past outcomes reaches Jev after failed steps (checkpoint.lua). The world
-- (whatever the host gives it: a person's computer, a computer of the agent's own) does what a tool verb means and says how it went.
--
-- The loop is an explicit state machine, not a coroutine, so it runs on every Lua a host may embed (some have no
-- coroutines): the host calls step() and does what it returns.
--
--   local agent = require("agent")
--   local a = agent.new(env, world)           env = { name?, jev, mercury, learn?, memory?, trace?, log?, refused?,
--                                               stepping?, decided?, rank?, explore?, random? }
--                                               (or agent.mix(A) for a world's own methods)
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
-- env.decided(req, verb, answer, how, propensity), when given, hears every decision: Jev's answer with its
-- probabilities, how it was settled ("jev"; "arbiter" when the close call went to Mercury; "tabpfn" in rank mode;
-- "explore", A:explore) and the chance the step had of taking that move.
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
  return setmetatable({ env = env, world = world, name = env.name or "the agent", history = history.new() }, A)
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- Mercury's text, or nil and why. An empty reply is no answer: Mercury thinking hard can spend all its tokens
-- reasoning and say nothing, and thinking that said nothing was once taken for guidance, step after step
-- (a terminal run thought 150 times running, 2026-10-05).
function A:mercury(req)
  local ok, text = pcall(self.env.mercury.chat, self.env.mercury, req)
  if not ok then return nil, tostring(text) end
  text = trim(text)
  if text == "" then return nil, "Mercury said nothing" end
  return text
end

-- A port's refusal (an error with status 401, not signed in, or 402, not paid for) is said as the port worded it,
-- and the host hears it (env.refused). nil for any other failure.
function A:refusal(err)
  if type(err) ~= "table" or not err.status or err.status < 401 or err.status > 402 then return nil end
  if self.env.refused then self.env.refused(err) end
  return tostring(err)
end

function A:decide(req)
  local w = self.world
  if not self.env.jev then return "answer" end
  local questions = { next = w.question(self) }
  -- one option is no decision (a decision model needs two: OpenAI Decisions answered 400, 2026-10-06): it is taken
  local only, count = nil, 0
  for name in pairs(questions.next.options or {}) do only, count = name, count + 1 end
  if count == 1 then
    req.sure, req.explored, req.propensity, req.how = nil, false, 1, "only"
    if self.env.decided then self.env.decided(req, only, { choice = only, probabilities = { [only] = 1 } }, "only", 1) end
    return only
  end
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
  -- a close call: Jev's best two go to a careful Mercury, which picks one of them, for a world that has an
  -- arbiter; a world without one leaves its close calls to TabPFN in rank mode (M4)
  local second, p2 = nil, -1
  for v, p in pairs(n.probabilities or {}) do
    p = tonumber(p)
    if v ~= n.choice and p and p > p2 then second, p2 = v, p end
  end
  local pick, how = n.choice, "jev"
  if second and req.sure and req.sure.p - p2 < M.close and self.env.mercury and w.arbiter then
    local okm, said = pcall(self.env.mercury.chat, self.env.mercury, w.arbiter(self, req, n.choice, second))
    said = okm and tostring(said):lower():match("[%a_]+")
    if said == second then pick, how = second, "arbiter" end
  end
  -- rank mode: TabPFN's best allowed move takes the step when it clearly beats Jev's pick and Jev was not sure
  local over = how == "jev" and self:overrule(req, n.choice, n.probabilities)
  if over then pick, how = over, "tabpfn" end
  -- now and then a move the policy would not take, so what it avoids can be measured too
  local tried, propensity = self:explore(req, pick, questions.next)
  if tried then pick, how = tried, "explore" end
  req.explored, req.propensity, req.how = tried ~= nil, propensity, how
  if self.env.decided then self.env.decided(req, pick, n, how, propensity) end
  return pick
end

-- Exploration (env.explore, a rate such as 0.05; env.random, math.random by default): with that chance a step takes,
-- uniformly, one of the moves offered or held back by a gate the world lets be tried (req.held), other than the
-- policy's pick, so a move's effect can be estimated where the policy never takes it. Never when the pick stops the
-- work or hands it on, and never one of those moves (M.jev_only). Gives the move or nil, and the chance the step
-- had of taking what it took: 1 - rate for the policy's pick, rate / #moves for an explored one, 1 with nothing to try.
function A:explore(req, pick, question)
  local rate = tonumber(self.env.explore) or 0
  if rate <= 0 or M.jev_only[pick] then return nil, 1 end
  local pool, seen = {}, { [pick] = true }
  local function add(name)
    if not seen[name] and not M.jev_only[name] then seen[name], pool[#pool + 1] = true, name end
  end
  for name in pairs(question and question.options or {}) do add(name) end
  for _, name in ipairs(req.held or {}) do add(name) end
  if #pool == 0 then return nil, 1 end
  table.sort(pool)
  local random = self.env.random or math.random
  if random() >= rate then return nil, 1 - rate end
  return pool[math.min(math.floor(random() * #pool) + 1, #pool)], rate / #pool
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
  local todo = self.req and self.req.todo
  if self.env.memory and todo then pcall(self.env.memory.log, self.env.memory, todo, keyword, args, "agent") end
  if self.env.trace then self.env.trace:row(keyword, args) end
end

function A:begin(text)
  local req = { text = text, steps = {} }
  req.todo = self.env.memory and self.env.memory:begin(text)
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
  -- how it was settled (jev, arbiter, tabpfn, explore) and the chance it had, for the step's decision row
  return { "act", { verb = verb, lines = {}, sure = req.sure, by = req.how, propensity = req.propensity } }
end

-- The step's verb is done: the agent's own verbs here, a tool verb by the world.
function A:perform(req, step)
  local verb = step.verb
  if verb == "think" then
    local guidance, err = self:mercury(self.world.think(self, req))
    if guidance then
      step.lines[1] = "guidance: " .. guidance
    else
      step.note, step.outcome = "Thinking failed: " .. tostring(err), "broken"
    end
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
