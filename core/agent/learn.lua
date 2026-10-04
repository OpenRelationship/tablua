-- TabPFN narrows, Jev picks (PROJECT.md §7.7), for Arock's agent: at a checkpoint TabPFN reads how
-- past steps turned out (memory.lua) and gives each option its chance of working; Jev reads the ranking. Two
-- checkpoints, not every step: "step", after a step that failed (which tool now), and "control", before a control
-- step in a window with many controls (which one the request means).
--
--   local l = learn.new{ tabpfn?, memory, tablua?, on = fn -> bool, log = fn(line) }
--   l:rank(checkpoint, ctx, candidates) -> { { name, p }, ... } best first | nil, why
--   l:training(checkpoint) -> table, labels, weights (pruned: every failure and surprise, a sample of the rest)
--   l:record(checkpoint) -> { n, right, brier }   how TabPFN's scored predictions have done
--
-- With a Tablua handle (tablua?: the agent's work as typed rows, a shared file attached), the "step" checkpoint
-- learns from Tablua's rows (t:training("progress"), in the columns known before Jev answers) in place of
-- memory's; the control checkpoint and the predictions' record stay memory's.
--
-- One fit (Fast, with the server's cache) serves many predictions; it is refitted once M.refit more outcomes are
-- known. TabPFN is not asked every turn (the free tier's 5M tokens a day are the account's, and a stalled run
-- once spent them): a run asks at most M.per_run times, and a state it ranked before (the same row but for its
-- step number, and the same options) gets the same ranking again without a call. With too little history,
-- learning off, the run's or the day's predictions used up, or TabPFN unreachable, it gives nil and why, and the
-- agent goes on as it would without it.
local M = {}
local L = {}
L.__index = L

M.model = "v3.5-fast_default"
M.schema = { step = "2", control = "1", rows = "t1" }   -- a fit's schema; "t1" for Tablua's rows
M.min_rows, M.min_each = 12, 3    -- labelled rows, and of each label, before TabPFN is asked
M.refit = 25                      -- new labelled rows before a refit
M.per_run = 20                    -- predictions one run may ask for (a ranking reused costs none)
M.per_day = 4000000               -- TabPFN tokens a day, under the free tier's 5M; a predict costs at least 10,000
M.easy = 200                      -- successes kept, newest first; every failure and surprise is kept
M.sure = 0.8                      -- a prediction less sure than this of what happened is a surprise, and kept
M.sampled = 20                    -- controls not chosen, kept as not-the-one for a choice that worked

M.columns = {
  -- stage and pass: where the work stood (a world that keeps stages says so; the offline study of 4,515 build
  -- steps found the move by stage the strongest sign of whether a step makes progress)
  step = { "request", "app", "verb", "step", "fails", "last_verb", "last_outcome", "stage", "pass", "count" },
  control = { "request", "app", "verb", "role", "label", "order", "seen_ok", "count" },
}
M.categorical = { step = { 2, 5, 6, 7 }, control = { 2, 3 } }   -- 0-based column indices

function M.new(env)
  return setmetatable({ tabpfn = env.tabpfn, memory = env.memory, tablua = env.tablua,
    on = env.on or function() return true end,
    log = env.log or function() end, fits = {}, asked = 0, seen = {} }, L)
end

-- Training examples, oldest first: { row, label, candidate, task, n }.
local function step_examples(m)
  local out = {}
  for _, s in ipairs(m.steps) do
    local y = m:worked(s)
    if y then
      local r = m.requests[s.task]
      out[#out + 1] = { row = { r and r.text or "", s.app, s.verb, s.n, s.fails, s.last_verb, s.last_outcome,
        s.stage or "", s.pass or -1 },
        label = y, candidate = s.verb, task = s.task, n = s.n }
    end
  end
  return out
end

-- How often a control of this app with this label was the one that worked, among the choices given.
local function seen(counts, app, label) return counts[(app or "") .. "\0" .. (label or "")] or 0 end

local function control_examples(m)
  local out, counts = {}, {}
  for _, c in ipairs(m.choices) do
    local s = c.chosen and m:step_of(c.task, c.n)
    local y = s and m:worked(s)
    if y then
      local r = m.requests[c.task]
      local text = r and r.text or ""
      local picked, others = nil, {}
      for _, k in ipairs(c.controls) do
        if tostring(k.id) == c.chosen then picked = k else others[#others + 1] = k end
      end
      if picked then
        local function ex(k, label)
          return { row = { text, c.app, c.verb, k.role or "", k.label or "", k.order or 0, seen(counts, c.app, k.label) },
            label = label, candidate = tostring(k.id), task = c.task, n = c.n }
        end
        out[#out + 1] = ex(picked, y)
        -- a choice that worked says the others were not the one; a sample of them, spread through the reading
        if y == 1 then
          local step = math.max(1, math.floor(#others / M.sampled))
          for i = 1, #others, step do
            if (i - 1) / step >= M.sampled then break end
            out[#out + 1] = ex(others[i], 0)
          end
          local key = (c.app or "") .. "\0" .. (picked.label or "")
          counts[key] = (counts[key] or 0) + 1
        end
      end
    end
  end
  return out, counts
end

local function examples(m, checkpoint)
  if checkpoint == "step" then return step_examples(m) end
  return control_examples(m)
end

-- How sure the prediction made for an example was of what happened, if one was made.
local function surprise(m, checkpoint, e)
  for _, p in ipairs(m.predictions) do
    if p.checkpoint == checkpoint and p.task == e.task and p.n == e.n and p.candidate == e.candidate then
      local sure = e.label == 1 and p.p or 1 - p.p
      return sure < M.sure
    end
  end
  return false
end

-- the step checkpoint's columns from Tablua's rows: those known before Jev answers, and a count
local function rows_columns()
  local tablua, columns = require("tablua"), {}
  for j = 1, tablua.before do columns[j] = tablua.columns[j] end
  columns[#columns + 1] = "count"
  return columns
end

-- Tablua's rows for the step checkpoint, each with a count of 1 as memory's merged rows have
local function rows_training(t)
  local train, labels = t:training("progress", { before = true })
  for _, row in ipairs(train.rows) do row[#row + 1] = 1 end
  return { columns = rows_columns(), rows = train.rows, categorical = require("tablua").categorical }, labels, #labels
end

-- whether the checkpoint learns from Tablua's rows
local function rows(self, checkpoint) return checkpoint == "step" and self.tablua ~= nil end

-- The pruned training set: every failure and surprise, the newest M.easy other successes; identical rows merged
-- with a count. Logs Prune Memory with what was kept and dropped. With Tablua's rows, those rows as they are.
function L:training(checkpoint)
  if rows(self, checkpoint) then return rows_training(self.tablua) end
  local m, all = self.memory, examples(self.memory, checkpoint)
  local keep, easy = {}, 0
  for i = #all, 1, -1 do
    local e = all[i]
    if e.label == 0 or surprise(m, checkpoint, e) then keep[#keep + 1] = e
    elseif easy < M.easy then easy = easy + 1; keep[#keep + 1] = e end
  end
  local rows, labels, index = {}, {}, {}
  for i = #keep, 1, -1 do
    local e = keep[i]
    local parts = {}
    for j, v in ipairs(e.row) do parts[j] = tostring(v) end
    local key = table.concat(parts, "\31") .. "\31" .. e.label
    local at = index[key]
    if at then
      rows[at][#rows[at]] = rows[at][#rows[at]] + 1
    else
      local row = {}
      for j, v in ipairs(e.row) do row[j] = v end
      row[#row + 1] = 1
      rows[#rows + 1], labels[#labels + 1] = row, e.label
      index[key] = #rows
    end
  end
  m:prune(checkpoint, #rows, #all - #keep, ("failures and surprises, newest %d successes, duplicates merged"):format(M.easy))
  return { columns = M.columns[checkpoint], rows = rows }, labels, #all
end

-- A fitted training set for the checkpoint, fitting (or refitting) when there is none or enough is new.
function L:fitted(checkpoint, force)
  local m = self.memory
  local from_rows = rows(self, checkpoint)
  local schema = from_rows and M.schema.rows or M.schema[checkpoint]
  local labelled = from_rows and select(3, rows_training(self.tablua)) or #examples(m, checkpoint)
  local have = self.fits[checkpoint] or m:fit(checkpoint, schema)
  if have and not force and labelled - have.rows < M.refit then
    self.fits[checkpoint] = have   -- a fit kept from an earlier session: its rows price the prediction
    return have.id
  end
  local train, labels = self:training(checkpoint)
  local ones, total = 0, 0   -- examples, counting each merged row as many as it stands for
  for i, y in ipairs(labels) do
    local w = train.rows[i][#train.rows[i]]
    total, ones = total + w, ones + y * w
  end
  if total < M.min_rows or ones < M.min_each or total - ones < M.min_each then
    return nil, "no past outcomes to learn from yet"
  end
  local id = self.tabpfn:fit({ columns = train.columns, rows = train.rows }, labels, { model = M.model, cache = true,
    categorical = train.categorical or M.categorical[checkpoint] })
  self.fits[checkpoint] = { id = id, rows = labelled }
  m:fitted(checkpoint, schema, id, labelled)
  return id
end

-- ctx: the request's words, the app, and for "step" the step number, failures, last verb and outcome; for
-- "control" the verb. candidates: tool names ("step") or { id, role, label, order } controls ("control").
function L:rank(checkpoint, ctx, candidates)
  if not self.on() then return nil, "learning from past outcomes is turned off" end
  if not self.tabpfn then return nil, "TabPFN is not set up (the keychain has no arock-priorlabs)" end
  if self.memory:tokens_today() >= M.per_day then return nil, "today's TabPFN predictions are used up" end
  local ok, id, why = pcall(self.fitted, self, checkpoint)
  if not ok then return nil, "TabPFN could not be reached: " .. tostring(id) end
  if not id then return nil, why end
  local from_rows = rows(self, checkpoint)
  local test = { columns = from_rows and rows_columns() or M.columns[checkpoint], rows = {} }
  local counts = checkpoint == "control" and select(2, control_examples(self.memory)) or nil
  for i, c in ipairs(candidates) do
    if from_rows then
      test.rows[i] = require("tablua").row(ctx, c)
      test.rows[i][#test.rows[i] + 1] = 1
    elseif checkpoint == "step" then
      test.rows[i] = { ctx.request, ctx.app or "", c, ctx.n, ctx.fails, ctx.last_verb or "", ctx.last_outcome or "",
        ctx.stage or "", ctx.pass or -1, 1 }
    else
      test.rows[i] = { ctx.request, ctx.app or "", ctx.verb, c.role or "", c.label or "", c.order or 0,
        seen(counts, ctx.app, c.label), 1 }
    end
  end
  -- a state ranked before, but for its step number, is ranked the same again
  local parts = { checkpoint, tostring(id) }
  for _, row in ipairs(test.rows) do
    local step_at = from_rows and require("tablua").before or 4
    for j, v in ipairs(row) do if not (checkpoint == "step" and j == step_at) then parts[#parts + 1] = tostring(v) end end
  end
  local key = table.concat(parts, "\0")
  local probas = self.seen[key]
  if not probas and self.asked >= M.per_run then return nil, "this run's TabPFN predictions are used up" end
  if not probas then
    -- every prediction is priced first (ports.tabpfn's rule); standard fits cost nothing
    local oke, tokens = pcall(self.tabpfn.estimate, self.tabpfn, { operation = "cache_predict", model = M.model,
      train_rows = self.fits[checkpoint] and self.fits[checkpoint].rows or 0, test_rows = #test.rows,
      raw_columns = #test.columns })
    if not oke then return nil, "TabPFN could not be reached: " .. tostring(tokens) end
    if self.memory:tokens_today() + tokens > M.per_day then return nil, "today's TabPFN predictions are used up" end
    self.memory:called(checkpoint, tokens)
    local okp
    okp, probas = pcall(self.tabpfn.predict, self.tabpfn, id, test)
    if not okp then
      -- the server's cache of a fit may have lapsed since it was made: fit again once
      local refit, fresh = pcall(self.fitted, self, checkpoint, true)
      if refit and fresh then okp, probas = pcall(self.tabpfn.predict, self.tabpfn, fresh, test) end
      if not okp then return nil, "TabPFN could not be reached: " .. tostring(probas) end
    end
    self.asked, self.seen[key] = self.asked + 1, probas
  end
  local ranked = {}
  for i, c in ipairs(candidates) do
    local p = probas[i]
    ranked[i] = { name = checkpoint == "step" and c or tostring(c.id), p = p[#p], control = c }
  end
  table.sort(ranked, function(a, b) return a.p > b.p end)
  for _, r in ipairs(ranked) do self.memory:predict(checkpoint, r.name, r.p, ctx.task, ctx.at) end
  return ranked
end

-- Scored predictions: each one whose outcome has since landed (the step it was for took that option).
function L:record(checkpoint)
  local m, n, right, sq = self.memory, 0, 0, 0
  local truth = {}
  for _, e in ipairs(examples(m, checkpoint)) do truth[e.task .. "\0" .. e.n .. "\0" .. e.candidate] = e.label end
  for _, p in ipairs(m.predictions) do
    local y = p.checkpoint == checkpoint and truth[p.task .. "\0" .. p.n .. "\0" .. p.candidate]
    if y then
      n, sq = n + 1, sq + (p.p - y) ^ 2
      if (p.p >= 0.5) == (y == 1) then right = right + 1 end
    end
  end
  return { n = n, right = right, brier = n > 0 and sq / n or nil }
end

-- The record as Jev reads it.
function L:record_line(checkpoint)
  local r = self:record(checkpoint)
  if r.n == 0 then return "its predictions here are not scored yet" end
  return ("right on %d of %d scored predictions here, Brier %.2f"):format(r.right, r.n, r.brier)
end

return M
