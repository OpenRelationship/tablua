-- Tablua, the continual tabular agent harness (issue #1): the agent's work as typed rows in its own SQLite file.
-- The harness writes what it decided in and on; TabPFN learns from a query over it. db is arock-log's port,
-- db:exec(sql, params) -> rows (Moss gives the agent's harness one over its computer's file that reaches only the
-- tablua_ tables; the Mac, its arock-log connection).
--
--   local t = tablua.open(db, { clock? })
--   t:state{ task, n, stage, passed, total, stalls?, last_verb?, last_outcome?, cause?, pages_ok?, own_checks?, ask?,
--            versions? }                                  where the work stood as a decision was made
--   t:candidates(task, n, { { move, jev_p?, jev_conf?, jev_margin?, jev_form?, p_progress?, p_ship?, cost_q50?,
--                cost_q90?, explored? }, ... })           every move that could have been made, and what was said of it
--   t:decision{ task, n, chosen, by, propensity?, policy? }  the move taken, and by whom (jev, tabpfn, mercury)
--   t:action{ task, n, i, cmd, file_kind?, op?, target?, bytes?, exit?, duration_ms? }   a call the move made
--   t:outcome{ task, n, verb, outcome, passed?, total?, regressed?, same_failure?, failing?, note? } -> progress (1|0)
--   t:run{ task, shipped, answered, works, right?, changed?, steps?, cost? }   how the run ended
--   t:prediction(task, n, head, move, p)   t:fit(head, schema, id, rows)   t:fitted(head, schema) -> { id, rows } | nil
--   t:attach(name, path)                   another file's rows (shared experience) read with this one's
--   t:features(task, n, { done = 0.6, ask_dates = 1 }, form)    Jev's fan-out answers as feature rows
--   t:label(task, n, head, value, source)      a label given after the fact (Jev's hindsight, head "contrib")
--   t:effects(task, n, { { keyword, arg } })   the step's effects, from the harness's telemetry (tablua.effects)
--   t:gate{ name, predicate, version?, retired_by? }   a harness gate, and what turned it off if anything did
--   t:training(head[, { before = true }]) -> { columns, rows }, labels   head "progress" (did the step help), "ship" (did its run ship
--                                                   and work) or "contrib" (did the step contribute to the app built,
--                                                   in hindsight: steps so labelled only) or "effect:<Keyword>" (did
--                                                   the effect follow: steps given effects only), one row per step,
--                                                   oldest first; keys[i] is row i's { task, n }
--   t:count(table) -> n
--   t:put_program(file, rows), t:program(file), t:compile(file) -> org, t:files()   the program as rows (issue #2;
--                                                   tablua.program)
local schema = require("tablua.schema")

local M = {}
local T = {}
T.__index = T

M.schema = schema

-- moves that change the app: one of them taken while scenarios fail, leaving as many passing, helped nothing
M.changes = { write_steps = true, write_code = true, write_page = true, fix_failure = true, rewrite = true,
  write_feature = true, undo = true }

-- the columns TabPFN reads of a decided step; categorical ones by 0-based index (ports.tabpfn)
M.columns = { "move", "stage", "pass", "stalls", "last_verb", "last_outcome", "cause", "own_checks", "n", "jev_p",
  "jev_margin" }
-- Jev's fan-out answers about the step (t:features), read as columns after those: what kind of ask it is, and how
-- done Jev judged the app (missing is -1, as for jev_p)
M.features = { "ask_dates", "ask_counts", "ask_groups", "ask_delete", "ask_edit", "done" }
for _, f in ipairs(M.features) do M.columns[#M.columns + 1] = f end
M.categorical = { 0, 1, 4, 5, 6 }
-- the columns known before Jev answers (all but Jev's numbers and its fan-out answers): what ranks the moves before
-- Jev decides is trained on these alone, so a row it scores is a row like those it learned from
M.before = 9

-- A row for `move` taken in state s ({ stage, pass, stalls, last_verb, last_outcome, cause, own_checks, n }), in the
-- columns known before Jev answers (training's `before`)
function M.row(s, move)
  return { move, s.stage or "", s.pass or -1, s.stalls or 0, s.last_verb or "", s.last_outcome or "", s.cause or "",
    s.own_checks or 0, s.n or 0 }
end

local function now() return os.date("!%Y-%m-%dT%H:%M:%SZ") end

function M.open(db, opts)
  db:exec(schema.ddl)
  db:exec("insert or replace into tablua_meta (key, value) values ('version', ?)", { tostring(schema.version) })
  return setmetatable({ db = db, clock = opts and opts.clock or now, sources = { "main" } }, T)
end

local function nz(v) if v == nil then return false end return v end   -- false binds as NULL (arock-log's rule)
local function flag(v) if v == nil then return false end return v and 1 or 0 end

local function put(db, tbl, cols, row)
  local marks, vals = {}, {}
  for i, c in ipairs(cols) do marks[i] = "?"; vals[i] = nz(row[c]) end
  db:exec(("insert or replace into %s (%s) values (%s)"):format(tbl, table.concat(cols, ", "),
    table.concat(marks, ", ")), vals)
end

function T:state(s)
  local row = {}
  for k, v in pairs(s) do row[k] = v end
  if s.passed and s.total and s.total > 0 then row.pass = s.passed / s.total end
  row.stalls, row.own_checks = s.stalls or 0, s.own_checks or 0
  row.stage, row.last_verb, row.last_outcome = s.stage or "", s.last_verb or "", s.last_outcome or ""
  row.cause, row.ask, row.versions, row.at = s.cause or "", s.ask or "", s.versions or "{}", self.clock()
  row.pages_ok = s.pages_ok ~= nil and flag(s.pages_ok) or nil
  put(self.db, "tablua_state", { "task", "n", "stage", "passed", "total", "pass", "stalls", "last_verb",
    "last_outcome", "cause", "pages_ok", "own_checks", "ask", "versions", "at" }, row)
end

function T:candidates(task, n, list)
  for _, c in ipairs(list) do
    put(self.db, "tablua_candidate", { "task", "n", "move", "jev_p", "jev_conf", "jev_margin", "jev_form",
      "p_progress", "p_ship", "cost_q50", "cost_q90", "explored" }, { task = task, n = n, move = c.move,
      jev_p = c.jev_p, jev_conf = c.jev_conf, jev_margin = c.jev_margin, jev_form = c.jev_form or "choice",
      p_progress = c.p_progress, p_ship = c.p_ship, cost_q50 = c.cost_q50, cost_q90 = c.cost_q90,
      explored = c.explored and 1 or 0 })
  end
end

-- Feature values of a step: a map of name to a number (a yes/no as 1 or 0), each with the question form it came from.
function T:features(task, n, map, form)
  for name, v in pairs(map or {}) do
    put(self.db, "tablua_feature", { "task", "n", "name", "value", "form" },
      { task = task, n = n, name = name, value = tonumber(v), form = form or "" })
  end
end

function T:decision(d)
  put(self.db, "tablua_decision", { "task", "n", "chosen", "by", "propensity", "policy", "at" },
    { task = d.task, n = d.n, chosen = d.chosen, by = d.by, propensity = d.propensity, policy = d.policy or "",
      at = self.clock() })
end

function T:action(a)
  put(self.db, "tablua_action", { "task", "n", "i", "cmd", "file_kind", "op", "target", "bytes", "exit",
    "duration_ms" }, { task = a.task, n = a.n, i = a.i, cmd = a.cmd or "", file_kind = a.file_kind or "",
    op = a.op or "", target = a.target or "", bytes = a.bytes, exit = a.exit, duration_ms = a.duration_ms })
end

-- Whether a step helped: more scenarios passing than before it; otherwise a step that did not complete, or a change
-- that left as many passing while some failed, did not; any other complete step did.
function M.progress(o, before)
  local b = before or {}
  if o.passed and b.passed and o.passed > b.passed then return 1 end
  if o.outcome ~= "complete" then return 0 end
  if M.changes[o.verb] and b.passed and o.passed and b.total and b.total > 0 and b.passed < b.total
    and o.passed <= b.passed then return 0 end
  return 1
end

function T:before(task, n)
  return self.db:exec("select passed, total, stage from tablua_state where task = ? and n = ?", { task, n })[1]
end

function T:outcome(o)
  local progress = M.progress(o, self:before(o.task, o.n))
  put(self.db, "tablua_outcome", { "task", "n", "verb", "outcome", "progress", "regressed", "same_failure",
    "passed", "total", "failing", "note" }, { task = o.task, n = o.n, verb = o.verb, outcome = o.outcome,
    progress = progress, regressed = o.regressed and 1 or 0, same_failure = o.same_failure and 1 or 0,
    passed = o.passed, total = o.total, failing = o.failing or "[]", note = o.note or "" })
  return progress
end

function T:run(r)
  put(self.db, "tablua_run", { "task", "shipped", "answered", "works", "right", "changed", "steps", "cost", "at" },
    { task = r.task, shipped = flag(r.shipped), answered = flag(r.answered), works = flag(r.works),
      right = r.right ~= nil and flag(r.right) or nil, changed = r.changed ~= nil and flag(r.changed) or nil,
      steps = r.steps, cost = r.cost, at = self.clock() })
end

function T:prediction(task, n, head, move, p)
  put(self.db, "tablua_prediction", { "task", "n", "head", "move", "p" },
    { task = task, n = n, head = head, move = move, p = p })
end

function T:fit(head, version, id, rows)
  put(self.db, "tablua_fit", { "head", "schema", "id", "rows", "at" },
    { head = head, schema = version, id = id, rows = rows, at = self.clock() })
end

function T:fitted(head, version)
  local r = self.db:exec("select id, rows from tablua_fit where head = ? and schema = ?", { head, version })[1]
  return r and { id = r.id, rows = r.rows } or nil
end

-- Another file's rows, read with this one's (Moss's shared experience): attached once under `name`.
function T:attach(name, path)
  assert(name:match("^[%a_][%w_]*$"), "tablua: not a name: " .. tostring(name))
  self.db:exec("attach database ? as " .. name, { path })
  self.db:exec((schema.ddl:gsub("exists tablua_", "exists " .. name .. ".tablua_")))
  self.sources[#self.sources + 1] = name
end

local function decided(src, featured, labelled, effect)
  local fs = {}
  for _, f in ipairs(M.features) do
    -- a file from before schema 2 has no feature table: its features are missing
    fs[#fs + 1] = featured and ("(select value from %s.tablua_feature f where f.task = s.task and f.n = s.n"
      .. " and f.name = '%s') as f_%s"):format(src, f, f) or ("null as f_%s"):format(f)
  end
  return ([[select s.task, s.n, d.chosen as move, s.stage, s.pass, s.stalls, s.last_verb, s.last_outcome, s.cause,
    s.own_checks, c.jev_p, c.jev_margin, o.progress, r.shipped, r.works, ]] .. table.concat(fs, ", ")
    .. (labelled and ", l.value as contrib" or "")
    .. (effect and ((", exists (select 1 from %s.tablua_effect e where e.task = s.task and e.n = s.n) as e_given,"
      .. " exists (select 1 from %s.tablua_effect e where e.task = s.task and e.n = s.n and e.keyword = '%s') as e_has")
      :format(src, src, effect)) or "") .. [[
    from %s.tablua_state s
    join %s.tablua_decision d on d.task = s.task and d.n = s.n
    join %s.tablua_outcome o on o.task = s.task and o.n = s.n
    left join %s.tablua_candidate c on c.task = s.task and c.n = s.n and c.move = d.chosen
    left join %s.tablua_run r on r.task = s.task]]):format(src, src, src, src, src)
    .. (labelled and (" left join %s.tablua_label l on l.task = s.task and l.n = s.n and l.head = 'contrib'"
      .. " and l.source = 'jev_hindsight'"):format(src) or "")
end

function T:label(task, n, head, value, source)
  put(self.db, "tablua_label", { "task", "n", "head", "value", "source", "at" },
    { task = task, n = n, head = head, value = value, source = source, at = self.clock() })
end

-- a gate of the harness and whether it holds in this file's runs (retired_by names what turned it off)
function T:gate(g)
  put(self.db, "tablua_gate", { "name", "predicate", "version", "retired_by" },
    { name = g.name, predicate = g.predicate or "", version = g.version or 1, retired_by = g.retired_by })
end

function T:effects(task, n, list)
  self.db:exec("delete from tablua_effect where task = ? and n = ?", { task, n })
  for _, e in ipairs(list) do
    put(self.db, "tablua_effect", { "task", "n", "keyword", "arg" }, { task = task, n = n, keyword = e.keyword, arg = e.arg or "" })
  end
  -- a step with no effect at all is still a step given its effects (every effect head reads it as 0)
  if #list == 0 then put(self.db, "tablua_effect", { "task", "n", "keyword", "arg" }, { task = task, n = n, keyword = "", arg = "" }) end
end

local HEADS = { progress = true, ship = true, contrib = true }
local function effect_of(head) return type(head) == "string" and head:match("^effect:(.+)$") end

-- One row per decided step, other files' first, then this one's, each oldest first; with opts.before, each row
-- only in the columns known before Jev answers (M.before).
function T:training(head, opts)
  local effect = effect_of(head)
  assert(HEADS[head] or effect, "tablua: no head " .. tostring(head))
  local rows, labels, keys = {}, {}, {}
  for i = #self.sources, 1, -1 do
    local src = self.sources[i]
    local featured = #self.db:exec(("select 1 from %s.sqlite_master where name = 'tablua_feature'"):format(src)) > 0
    local labelled = head == "contrib"
      and #self.db:exec(("select 1 from %s.sqlite_master where name = 'tablua_label'"):format(src)) > 0
    local effected = effect
      and #self.db:exec(("select 1 from %s.sqlite_master where name = 'tablua_effect'"):format(src)) > 0
    local sql = decided(src, featured, labelled, effected and effect:gsub("'", "''"))
    if head == "ship" then sql = sql .. " where r.task is not null"
    elseif head == "contrib" then sql = sql .. (labelled and " where l.value is not null" or " where 0")
    elseif effect then sql = sql .. (effected and " where e_given = 1" or " where 0") end
    sql = sql .. " order by s.task, s.n"
    for _, r in ipairs(self.db:exec(sql)) do
      local row = { r.move, r.stage, r.pass or -1, r.stalls or 0, r.last_verb or "", r.last_outcome or "",
        r.cause or "", r.own_checks or 0, r.n, r.jev_p or -1, r.jev_margin or -1 }
      for _, f in ipairs(M.features) do row[#row + 1] = r["f_" .. f] or -1 end
      if opts and opts.before then for j = #row, M.before + 1, -1 do row[j] = nil end end
      rows[#rows + 1] = row
      keys[#keys + 1] = { task = r.task, n = r.n }
      if head == "progress" then labels[#labels + 1] = r.progress
      elseif head == "contrib" then labels[#labels + 1] = r.contrib >= 0.5 and 1 or 0
      elseif effect then labels[#labels + 1] = r.e_has
      else labels[#labels + 1] = (r.shipped == 1 and r.works == 1) and 1 or 0 end
    end
  end
  local columns = M.columns
  if opts and opts.before then
    columns = {}
    for j = 1, M.before do columns[j] = M.columns[j] end
  end
  return { columns = columns, rows = rows, keys = keys }, labels
end

require("tablua.program")(T, put)

local TABLES = { state = true, candidate = true, decision = true, action = true, outcome = true, run = true,
  fit = true, prediction = true, gate = true, feature = true, label = true, effect = true, section = true, unit = true, scenario = true, line = true }

function T:count(name)
  assert(TABLES[name], "tablua: no table " .. tostring(name))
  return self.db:exec("select count(*) as n from tablua_" .. name)[1].n
end

return M
