-- Where the agent learns: each tool step's outcome goes to memory, a finished
-- request is judged by Jev, and after failed steps TabPFN's ranking of the world's tools (learn.lua) reaches Jev as
-- evidence on its card, every option still open. A world may add checkpoints of its own (a desktop world narrows the
-- controls of a crowded window) and record more of a step (world.after) or of a request Jev judged (world.judged).
--
--   checkpoint.before(a, req)          before Jev decides: once M.stuck steps have failed, TabPFN's ranking of the tools;
--                                      with env.rank (or env.shadow, which only records it), at every decision of a
--                                      stage in M.ranked, of the moves allowed
--                                      (world.allowed), which A:decide may take over Jev's (init.lua)
--   checkpoint.after(a, req, step)     a tool step is over: its outcome (to memory, and with env.tablua as Tablua's
--                                      rows), then world.after(a, req, step)
--   checkpoint.judge(a)                a request is over: Jev says how it ended (run when the agent is idle), then
--                                      world.judged(a, req, label)
--   checkpoint.card(req, env) -> text|nil  what Jev reads of the ranking (nothing in shadow mode)
local M = {}

M.shown = 6          -- tools shown on Jev's card
M.stuck = 2          -- failed steps in a request before TabPFN ranks the tools: a ranking takes seconds the person
                     -- waits through, so it is asked for only when Jev is stuck, not after every slip
M.ranked = { building = true }   -- with env.rank: stages whose every decision is ranked (where Jev's picks of
                                 -- rewrite and think moved a scenario 7% and 2% of the time, offline study)
M.judgements = {
  complete = "The steps did what the person asked, and the answer says so truly.",
  partial = "Some of what was asked was done, not all of it.",
  failed = "What was asked was not done.",
  hallucination = "The answer claims something the steps do not show was done or found.",
}

local function note(a, why) if a.env.log and why then a.env.log("(learning) " .. why) end end

local function last_step(req)
  for i = #req.steps, 1, -1 do if req.steps[i].outcome then return req.steps[i] end end
end

function M.fails(req)
  local n = 0
  for _, s in ipairs(req.steps) do if s.outcome == "broken" or s.outcome == "no_effect" then n = n + 1 end end
  return n
end

function M.before(a, req)
  req.ranking, req.record, req.ranked_all = nil, nil, nil
  -- where the work stands as this decision is made (a world that keeps stages sets req.stage and req.pass), kept for
  -- the step it becomes
  local learn, last = a.env.learn, last_step(req)
  -- the moves allowed now, read first: reading them reads the facts again, and with them the stage
  local allowed = (a.env.rank or a.env.shadow) and a.world.allowed and a.world.allowed(a, req)
  req.standing = { stage = req.stage or "", pass = req.pass }
  if not learn then return end
  local every = allowed and M.ranked[req.stage or ""]
  if not every then
    if not last or (last.outcome ~= "broken" and last.outcome ~= "no_effect") then return end
    if M.fails(req) < M.stuck then return end
  end
  local names = every and allowed or {}
  if not every then for _, t in ipairs(a.world.tools) do names[#names + 1] = t.name end end
  local ranked, why = learn:rank("step", { request = req.text, app = last and last.app or "", n = #req.steps + 1,
    fails = M.fails(req), last_verb = last and last.verb or "", last_outcome = last and last.outcome or "",
    stage = req.standing.stage, pass = req.standing.pass, todo = req.todo, at = #req.steps + 1,
    -- what a world that keeps them knows besides (Tablua's columns before Jev answers, learn's rows)
    stalls = req.repeats or 0, cause = req.cause and req.cause.choice or "",
    own_checks = req.facts and req.facts.tests and #(req.facts.tests.checked or {}) or 0 }, names)
  if not ranked then req.unranked = why; note(a, why) return end
  req.ranking, req.record, req.unranked = ranked, learn:record_line("step"), nil
  req.ranked_all = every and true or nil
end

function M.card(req, env)
  -- shadow mode scores the moves for the record only: Jev decides as if no ranking were made
  if env and env.shadow and not env.rank then return nil end
  if req.ranking then
    local parts = {}
    for i = 1, math.min(M.shown, #req.ranking) do
      parts[i] = ("%s %.2f"):format(req.ranking[i].name, req.ranking[i].p)
    end
    return "From past outcomes (TabPFN, " .. req.record .. "), the chance each tool's step works now: "
      .. table.concat(parts, ", ") .. ". It is evidence, not a rule: every option is still open."
  end
  if req.unranked == "no past outcomes to learn from yet" then return "(There are no past outcomes to learn from yet.)" end
end

-- With env.tablua (a world whose own harness does not write them), the step as Tablua's rows too: where
-- the work stood, how sure Jev was of the move, the move, and how it ended; what TabPFN learns from (learn.lua).
local function rows(a, req, step, prev)
  local t, s = a.env.tablua, req.standing or {}
  t:state{ todo = req.todo, n = step.n, stage = s.stage, pass = s.pass, stalls = req.repeats, last_verb = prev and prev.verb,
    last_outcome = prev and prev.outcome, cause = req.cause and req.cause.choice }
  -- a host that wrote the decision itself (every move offered, what the decider said) keeps its rows
  local written = #t.db:exec("select 1 from tablua_decision where todo = ? and n = ?", { req.todo, step.n }) > 0
  if not written then
    t:candidates(req.todo, step.n, { { move = step.verb, jev_p = step.sure and step.sure.p,
      jev_conf = step.sure and step.sure.confidence } })
    t:decision{ todo = req.todo, n = step.n, chosen = step.verb, by = step.by or "jev" }
  end
  t:outcome{ todo = req.todo, n = step.n, verb = step.verb, outcome = step.outcome, note = step.note }
end

function M.after(a, req, step)
  local m = a.env.memory
  if not m or not req.todo or not step.outcome then return end
  local prev = req.steps[step.n - 1]
  m:step(req.todo, { n = step.n, verb = step.verb, app = step.app or "", fails = M.fails(req) - ((step.outcome == "broken"
    or step.outcome == "no_effect") and 1 or 0), last_verb = prev and prev.verb or "", last_outcome = prev and
    prev.outcome or "", outcome = step.outcome, evidence = step.note or "",
    stage = req.standing and req.standing.stage, pass = req.standing and req.standing.pass })
  if a.env.tablua then rows(a, req, step, prev) end
  if a.world.after then a.world.after(a, req, step) end
  if step.outcome ~= "denied" then req.acted = true end
end

function M.judge(a)
  local j = a.judging
  a.judging = nil
  if not j or not a.env.memory then return end
  if not a.env.jev then return end
  local state = a.world.state(a, j.req, true) .. "\n\nWhat " .. a.name .. " told the person at the end: " .. j.said
  local ok, answers = pcall(a.env.jev.decide, a.env.jev, state, { ended = { kind = "choice", options = M.judgements,
    text = "How did this request end? Read the steps and what was said at the end." } })
  if not ok then note(a, "Jev could not judge how the request ended: " .. tostring(answers)) return end
  local label = answers.ended and answers.ended.choice
  if M.judgements[label] then a.env.memory:outcome(j.req.todo, label, "judged by Jev") end
  if M.judgements[label] and a.world.judged then a.world.judged(a, j.req, label) end
end

return M
