-- Jev's fan-out (Tablua issue #1, M2): questions asked in the same call as the move, whose answers become feature
-- columns of the step (library/tablua's t:features), never a decision. What kind of ask it is, asked once a
-- request as yes-or-no questions on the task alone (each answer Jev's chance of yes); and, while building or
-- ready, how much of the task the app does now, as a score whose mean over the levels is kept.
--
--   features.questions(req) -> { id = question }    merged into the world's questions
--   features.answered(req, answers)                  sets req.features, a map of name to number
--
-- And, while building or ready, Jev's own forecast of the step's effects (Tablua's behaviour model,
-- tablua.effects): for each of a few, its chance of yes that the effect follows the move it chooses, kept as
-- feature "jev_effect:<Keyword>" and graded by the effects the harness records after the step. These are not
-- among the columns TabPFN reads; the eval's fit scores them against TabPFN's own heads for the same effects.
local M = {}

M.ask = {
  ask_dates = "dates or days (when something was or is due)",
  ask_counts = "counts, totals or sums",
  ask_groups = "things kept in groups or categories",
  ask_delete = "removing things that were added",
  ask_edit = "changing things that were added",
}

M.effects = {
  ["Scenario Turned Green"] = "a scenario that fails now will pass",
  ["Same Line Failing"] = "a failing scenario will fail again at the same line for the same reason",
  ["Check Failed"] = "check will find something wrong with the app",
  ["Step Broken"] = "the step will leave something broken",
}

local function slug(k) return "effect_" .. k:lower():gsub("%s+", "_") end

M.levels = { "nothing the task asks works yet", "a little of it works", "most of it works", "all of it works as asked" }

function M.questions(req)
  local q = {}
  if not req.ask_features then
    for id, what in pairs(M.ask) do
      q[id] = { kind = "noul", optional = true, text = "Does the task ask for " .. what .. "? Read only the task.",
        yes = "the task asks for it", no = "the task does not ask for it" }
    end
  end
  if req.stage == "building" or req.stage == "ready" then
    q.done = { kind = "score", optional = true, levels = M.levels,
      text = "How much of what the task asks does the app do now? Read the facts and the checks that pass." }
    for k, what in pairs(M.effects) do
      q[slug(k)] = { kind = "noul", optional = true,
        text = "If the agent makes the move you choose now, will " .. what .. " right after it?",
        yes = "it will", no = "it will not" }
    end
  end
  return q
end

-- the score's mean over its levels, 0 to 1: probabilities keyed by level text or by position
local function mean(a)
  local p, total, sum = a.probabilities or {}, 0, 0
  for i, level in ipairs(M.levels) do
    local v = tonumber(p[level] or p[i] or p[tostring(i)] or p[tostring(i - 1)])
    if v then total, sum = total + v, sum + v * (i - 1) / (#M.levels - 1) end
  end
  if total > 0 then return sum / total end
  for i, level in ipairs(M.levels) do if a.score == level then return (i - 1) / (#M.levels - 1) end end
end

function M.answered(req, answers)
  if not req.ask_features then
    local f, any = {}, false
    for id in pairs(M.ask) do
      local a = answers[id]
      if a and tonumber(a.noul) then f[id], any = tonumber(a.noul), true end
    end
    if any then req.ask_features = f end
  end
  local out = {}
  for k, v in pairs(req.ask_features or {}) do out[k] = v end
  if answers.done then out.done = mean(answers.done) end
  for k in pairs(M.effects) do
    local a = answers[slug(k)]
    if a and tonumber(a.noul) then out["jev_effect:" .. k] = tonumber(a.noul) end
  end
  req.features = out
end

return M
