-- Hindsight labels (M2; owner, 2026-10-04): after a run, Jev reads the whole trajectory and how it ended,
-- and says of each step whether it contributed to the app that was finally built. Progress, the label TabPFN
-- learns from at each step, is short-sighted (steps written before the code turn a run red, and are groundwork);
-- this is the long view. Each answer is Jev's chance of yes, kept as head "contrib" from source "jev_hindsight"
-- (t:label). It is a training target only: it knows what happened after the step, so it is never an input at
-- decision time, and never the ship label. Whether it helps is judged against real outcomes on held-out runs.
--
--   hindsight.steps(t, task) -> { { n, verb, outcome, note, stage, passed, total } }
--   hindsight.state(task, run, steps) -> text       hindsight.questions(steps, from, to) -> { s<n> = question }
--   hindsight.label(t, jev, task) -> labelled, cost   asks in batches of hindsight.batch steps
local M = {}

M.batch = 25
M.source = "jev_hindsight"

function M.steps(t, task)
  return t.db:exec([[select o.n, o.verb, o.outcome, o.note, o.passed, o.total, coalesce(s.stage, '') as stage
    from tablua_outcome o left join tablua_state s on s.task = o.task and s.n = o.n
    where o.task = ? order by o.n]], { task })
end

local function ended(run)
  if not run then return "The run's ending was not recorded." end
  local yes = function(v) return v == 1 and "yes" or v == 0 and "no" or "unknown" end
  return ("How it ended: shipped %s; the app worked when its person used it %s; it did what was asked %s.")
    :format(yes(run.shipped), yes(run.works), yes(run.right))
end

-- the trajectory as Jev reads it: the ask, how the run ended, then every step, one line each
function M.state(task, run, steps)
  local out = { "A run of an agent that built a small app on its own computer, read after it ended.",
    "Task: " .. task, ended(run), "Its steps:" }
  for _, s in ipairs(steps) do
    local tests = s.total and s.total ~= "" and (" (%s of %s scenarios passing after)"):format(s.passed or 0, s.total) or ""
    local note = (s.note or ""):gsub("%s+", " "):sub(1, 160)
    out[#out + 1] = ("%d. [%s] %s -> %s%s. %s"):format(s.n, s.stage, s.verb, s.outcome, tests, note)
  end
  return table.concat(out, "\n")
end

function M.questions(steps, from, to)
  local q = {}
  for i = from, math.min(to, #steps) do
    local s = steps[i]
    q["s" .. s.n] = { kind = "noul", optional = true,
      text = ("Did step %d (%s) contribute to the app this run finally built, or to what it got right? Groundwork"
        .. " that later steps built on counts; a step that was undone, repeated a failure or went nowhere does"
        .. " not. Read the whole run."):format(s.n, s.verb),
      yes = "it contributed", no = "it did not contribute" }
  end
  return q
end

-- labels every step of `task` not yet labelled, from its rows in t; jev is ports.jev (or anything with :decide)
function M.label(t, jev, task)
  local done = {}
  for _, r in ipairs(t.db:exec("select n from tablua_label where task = ? and head = 'contrib' and source = ?",
    { task, M.source })) do done[r.n] = true end
  local steps = {}
  for _, s in ipairs(M.steps(t, task)) do steps[#steps + 1] = s end
  if #steps == 0 then return 0, 0 end
  local run = t.db:exec("select shipped, works, right from tablua_run where task = ?", { task })[1]
  -- the person's words when the state kept them, else the task's address
  local ask = t.db:exec("select ask from tablua_state where task = ? and ask != '' limit 1", { task })[1]
  local state, labelled, cost = M.state(ask and ask.ask or task, run, steps), 0, 0
  for from = 1, #steps, M.batch do
    local q = M.questions(steps, from, from + M.batch - 1)
    for id in pairs(q) do if done[tonumber(id:sub(2))] then q[id] = nil end end
    if next(q) then
      local answers, record = jev:decide(state, q)
      cost = cost + (record and tonumber(record.cost) or 0)
      for id, a in pairs(answers) do
        t:label(task, tonumber(id:sub(2)), "contrib", a.noul, M.source)
        labelled = labelled + 1
      end
    end
  end
  return labelled, cost
end

return M
