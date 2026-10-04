-- What the computer's agent writes of each step as Tablua's typed rows (core/tablua, issue #1), in its own
-- computer's file through __host.agent_sql: where the work stood, every move it could have made with Jev's (and
-- TabPFN's) numbers, the move taken and by whom, and how the step turned out. It changes no decision; a failure to
-- write is said once and the run goes on.
--
--   local r = record.new(task, log)    task: the run's address (one computer may run several)
--   r.decided(req, verb, answer, how)  before the step: state, candidates, decision
--   r.gates(run)                       the harness's gates, once a run, each with whether the run turned it off
--   r.after(req, step, facts, stage)   after it: the outcome, with the facts as they are now, the step's effects
--                                      (tablua.effects: the facts at the decision against these, its commands) and
--                                      its calls as action rows (step.actions, world.lua)
local M = {}

local function port()
  return { exec = function(_, sql, params)
    local rows, why = __host.agent_sql(sql, params or {})
    if rows == nil then error(why or "tablua: refused", 2) end
    return rows
  end }
end

local function tests(f) return f and f.tests or nil end

function M.new(task, log)
  local ok, t = pcall(function() return require("tablua").open(port()) end)
  local r, said = {}, false
  local function try(f, ...)
    if not ok then return end
    local fine, why = pcall(f, ...)
    if not fine and not said then said = true; (log or print)("tablua: " .. tostring(why)) end
  end
  if not ok then (log or print)("tablua: " .. tostring(t)) end

  -- the run's Tablua handle for learning from its rows, the shared experience attached when given; nil when the
  -- tables could not be opened
  function r.tablua(experience)
    if not ok then return nil end
    if experience and experience ~= "" and not t.sources[2] then try(t.attach, t, "shared", experience) end
    return t
  end

  function r.decided(req, verb, answer, how)
    try(function()
      local n, f, last = #req.steps + 1, req.facts or {}, req.steps[#req.steps]
      local tt = tests(f)
      t:state{ task = task, n = n, stage = req.stage, passed = tt and tt.passed, total = tt and tt.total,
        stalls = req.repeats or 0, last_verb = last and last.verb or "", last_outcome = last and last.outcome or "",
        cause = req.cause and req.cause.choice or "", own_checks = tt and #(tt.checked or {}) or 0,
        pages_ok = f.pages and (function()
          for _, p in ipairs(f.pages) do if p.status ~= 200 then return false end end
          return #f.pages > 0
        end)() }
      local probs, ranked, list = answer.probabilities or {}, {}, {}
      for _, x in ipairs(req.ranking or {}) do ranked[x.name] = x.p end
      local ps = {}
      for move, p in pairs(probs) do ps[#ps + 1] = tonumber(p) or 0; list[#list + 1] = { move = move, jev_p = tonumber(p) } end
      table.sort(ps, function(a, b) return a > b end)
      for _, c in ipairs(list) do
        c.jev_conf, c.p_progress = tonumber(answer.confidence), ranked[c.move]
        c.jev_margin = c.jev_p and (c.jev_p - (c.jev_p == ps[1] and (ps[2] or 0) or ps[1])) or nil
      end
      t:candidates(task, n, list)
      t:decision{ task = task, n = n, chosen = verb, by = how, propensity = 1 }
      if req.features then t:features(task, n, req.features, "jev") end
    end)
  end

  -- the harness's gates as rows, once a run: each, and whether this run turned it off (world/gates.lua)
  function r.gates(run)
    try(function()
      local gates = require("moss.world.gates")
      local off = gates.off(run)
      for _, g in ipairs(gates.list) do
        t:gate{ name = g.name, predicate = g.what, retired_by = (off[g.name] and not g.fixed) and "gates_off" or false }
      end
    end)
  end

  function r.after(req, step, facts, stage)
    try(function()
      local effects = require("tablua.effects")
      local list = effects.compare(effects.snapshot(req.facts, req.stage), effects.snapshot(facts, stage),
        { verb = step.verb, outcome = step.outcome, regressed = req.regressed and true or false,
          same_failure = (step.note or ""):find("same failure", 1, true) ~= nil }, effects.commands(step.lines))
      t:effects(task, step.n, list)
      -- an undo is the step before it undone
      if step.verb == "undo" and step.n > 1 then
        local prev = t.db:exec("select keyword, arg from tablua_effect where task = ? and n = ? and keyword != ''",
          { task, step.n - 1 })
        prev[#prev + 1] = { keyword = "Undone Next", arg = "" }
        t:effects(task, step.n - 1, prev)
      end
    end)
    -- each call the move made as an action row: a unit spliced in (edit_unit, file#unit), a file written whole
    -- (write_file) or a command alone (run), with the command's exit
    try(function()
      for i, a in ipairs(step.actions or {}) do
        t:action{ task = task, n = step.n, i = i, cmd = a.cmd, file_kind = a.kind or "", op = a.op,
          target = a.target, bytes = a.bytes, exit = a.exit }
      end
    end)
    try(function()
      local tt = tests(facts)
      local note = step.note or ""
      t:outcome{ task = task, n = step.n, verb = step.verb, outcome = step.outcome or "",
        passed = tt and tt.passed, total = tt and tt.total, regressed = req.regressed and true or false,
        same_failure = note:find("same failure", 1, true) ~= nil, note = note }
    end)
  end

  return r
end

return M
