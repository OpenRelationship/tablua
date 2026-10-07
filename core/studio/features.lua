-- What TabICL reads of a comp at each decision (cadence/docs/ROWS.md, level 7): the comp's size by table, its open
-- findings, the critic's last scores, where the work stands, and the move; read from the sheet's rows as the
-- decision is made, kept as feature rows of that step (form "studio"), and the training table built from them.
--
--   features.read(t, todo, n, extra?) -> { name = number }   the comp step n is decided on (the newest snapshot
--                                         before n), its findings, the critic's newest scores; extra adds the world's
--   features.record(t, todo, n, values)   kept as step n's rows (tablua_feature, form "studio")
--   features.learner(t) -> { schema, training = fn() -> table, labels, rows = fn(ctx, moves) -> table }
--                                         for learn.new{ step = ... }: a row per decided step, labelled by progress
local M = {}

M.form = "studio"
M.dims = { "rule", "relationship", "defaults", "rhythm", "memory", "craft" }
-- the columns, the move and the state's first (categorical: 0-based), then the comp's numbers
M.columns = { "move", "stage", "last_verb", "last_outcome", "pass", "stalls", "n", "game", "nodes", "keys", "motions",
  "systems", "assets", "facts", "bound", "errors", "warnings", "check_errors", "critic_low", "critic_mean",
  "rule", "relationship", "defaults", "rhythm", "memory", "craft", "render_s", "since_look" }
M.categorical = { 0, 1, 2, 3 }
M.numbers = 5          -- the first column read from the feature rows (1-based)
M.schema = "studio-1"  -- a fit's schema: changes when the columns do

local function one(t, sql, args)
  local r = t.db:exec(sql, args)[1]
  if not r then return nil end
  local _, v = next(r)
  return v
end

-- the newest snapshot before step n (0 before any step)
local function snapshot(t, todo, n)
  return one(t, "select max(n) as m from tablua_msr_node where todo = ? and n < ?", { todo, n })
    or one(t, "select max(n) as m from tablua_msr_comp where todo = ? and n < ?", { todo, n }) or 0
end

function M.read(t, todo, n, extra)
  local s = snapshot(t, todo, n)
  local function count(tbl, where)
    return one(t, ("select count(*) as c from tablua_msr_%s where todo = ? and n = ?%s"):format(tbl, where or ""),
      { todo, s }) or 0
  end
  local f = { nodes = count("node"), keys = count("key"), motions = count("motion"), systems = count("system"),
    assets = count("asset"), facts = count("fact"),
    -- keys whose time is a fact reference (ROWS.md: a comp says what it is computed from)
    bound = count("key", " and typeof(t) = 'text' and t like '%:%'"),
    errors = count("finding", " and severity = 'error'"), warnings = count("finding", " and severity != 'error'"),
    check_errors = count("finding", " and severity = 'error' and tier = 'check'") }
  local last = one(t, "select max(n) as m from tablua_score where todo = ? and judge = 'critic' and n < ?", { todo, n })
  f.critic_low, f.critic_mean = -1, -1
  for _, d in ipairs(M.dims) do f[d] = -1 end
  if last then
    local lo, sum, k = nil, 0, 0
    for _, r in ipairs(t.db:exec("select dim, value from tablua_score where todo = ? and n = ? and judge = 'critic'",
      { todo, last })) do
      f[r.dim] = r.value
      lo = (lo == nil or r.value < lo) and r.value or lo
      sum, k = sum + r.value, k + 1
    end
    f.critic_low, f.critic_mean = lo or -1, k > 0 and sum / k or -1
  end
  f.since_look = last and (n - last) or n
  for k, v in pairs(extra or {}) do f[k] = v end
  return f
end

function M.record(t, todo, n, values) t:features(todo, n, values, M.form) end

-- one row in the columns: the move and the state's words, then the numbers (-1 where missing)
local function row(move, s, f)
  local r = { move, s.stage or "", s.last_verb or "", s.last_outcome or "" }
  r[5], r[6], r[7] = s.pass or -1, s.stalls or 0, s.n or 0
  for j = 8, #M.columns do
    local v = f[M.columns[j]]
    r[j] = tonumber(v) or -1
  end
  return r
end

local function values(t, todo, n, src)
  local f = {}
  for _, r in ipairs(t.db:exec(("select name, value from %s.tablua_feature where todo = ? and n = ? and form = ?")
    :format(src or "main"), { todo, n, M.form })) do f[r.name] = r.value end
  return f
end

function M.learner(t)
  local L = { schema = M.schema }
  function L.training()
    local rows, labels = {}, {}
    -- every attached file's steps (earlier trials), then this one's, each oldest first
    for i = #t.sources, 1, -1 do
      local src = t.sources[i]
      for _, r in ipairs(t.db:exec(([[select d.todo, d.n, d.chosen, s.stage, s.pass, s.stalls, s.last_verb,
          s.last_outcome, o.progress from %s.tablua_decision d join %s.tablua_state s using (todo, n)
          join %s.tablua_outcome o using (todo, n) order by d.todo, d.n]]):format(src, src, src))) do
        local f = values(t, r.todo, r.n, src)
        if next(f) then
          rows[#rows + 1] = row(r.chosen, { stage = r.stage, pass = r.pass, stalls = r.stalls,
            last_verb = r.last_verb, last_outcome = r.last_outcome, n = r.n }, f)
          labels[#labels + 1] = r.progress
        end
      end
    end
    return { columns = M.columns, rows = rows, categorical = M.categorical }, labels
  end
  function L.rows(ctx, moves)
    local f = values(t, ctx.todo, ctx.n)
    local test = { columns = M.columns, rows = {} }
    for i, m in ipairs(moves) do test.rows[i] = row(m, ctx, f) end
    return test
  end
  return L
end

return M
