-- TabPFN narrows, Jev picks (PROJECT.md §7.7), for Arock's agent: at a checkpoint TabPFN reads how past steps turned
-- out, as Tablua's rows (core/tablua: the agent's work as typed rows in its own file, a shared file attached), and
-- gives each option its chance of working; Jev reads the ranking. Two checkpoints, not every step: "step", which move
-- now (Tablua's progress head, in the columns known before Jev answers), and "control", before a control step in a
-- window with many controls, which one the request means (tablua.control).
--
--   local l = learn.new{ tabpfn?, tablua?, memory?, on = fn -> bool, log = fn(line) }
--   l:rank(checkpoint, ctx, candidates) -> { { name, p }, ... } best first | nil, why
--   l:training(checkpoint) -> table, labels
--   l:record(checkpoint) -> { n, right, brier }   how TabPFN's logged predictions have done
--
-- Fits and predictions are Tablua's rows too (tablua_fit, tablua_prediction); the day's TabPFN tokens are memory's
-- ledger (memory.lua). One fit (Fast, with the server's cache) serves many predictions; it is refitted once
-- M.refit more outcomes are known. TabPFN is not asked every turn (the free tier's 5M tokens a day are the
-- account's, and a stalled run once spent them): a run asks at most M.per_run times, and a state it ranked before
-- (the same row but for its step number, and the same options) gets the same ranking again without a call. With
-- too little history, learning off, the run's or the day's predictions used up, or TabPFN unreachable, it gives nil
-- and why, and the agent goes on as it would without it.
local tablua = require("tablua")

local M = {}
local L = {}
L.__index = L

M.model = "v3.5-fast_default"
M.schema = { step = "t2", control = "t1" }   -- a fit's schema: its columns' version
M.head = { step = "progress", control = "control" }   -- the Tablua head each checkpoint learns
M.min_rows, M.min_each = 12, 3    -- labelled rows, and of each label, before TabPFN is asked
M.refit = 25                      -- new labelled rows before a refit
M.per_run = 20                    -- predictions one run may ask for (a ranking reused costs none)
M.per_day = 4000000               -- TabPFN tokens a day, under the free tier's 5M; a predict costs at least 10,000

function M.new(env)
  return setmetatable({ tabpfn = env.tabpfn, memory = env.memory, tablua = env.tablua,
    on = env.on or function() return true end,
    log = env.log or function() end, fits = {}, asked = 0, seen = {} }, L)
end

local function tokens_today(self) return self.memory and self.memory:tokens_today() or 0 end

-- One row per past step ("step": the columns known before Jev answers) or per control example ("control").
function L:training(checkpoint)
  if checkpoint == "control" then return self.tablua:control_training() end
  local train, labels = self.tablua:training("progress", { before = true })
  return { columns = train.columns, rows = train.rows, categorical = tablua.categorical }, labels
end

-- A fitted training set for the checkpoint, fitting (or refitting) when there is none or enough is new.
function L:fitted(checkpoint, force)
  local t, head, schema = self.tablua, M.head[checkpoint], M.schema[checkpoint]
  local train, labels = self:training(checkpoint)
  local have = self.fits[checkpoint] or t:fitted(head, schema)
  if have and not force and #labels - have.rows < M.refit then
    self.fits[checkpoint] = have   -- a fit kept from an earlier session: its rows price the prediction
    return have.id
  end
  local ones = 0
  for _, y in ipairs(labels) do ones = ones + y end
  if #labels < M.min_rows or ones < M.min_each or #labels - ones < M.min_each then
    return nil, "no past outcomes to learn from yet"
  end
  local id = self.tabpfn:fit({ columns = train.columns, rows = train.rows }, labels, { model = M.model, cache = true,
    categorical = train.categorical })
  self.fits[checkpoint] = { id = id, rows = #labels }
  t:fit(head, schema, id, #labels)
  return id
end

-- Each candidate's row, in the columns the checkpoint's training set has.
local function test_set(self, checkpoint, ctx, candidates)
  if checkpoint == "control" then
    local rows, columns = self.tablua:control_rows(ctx, candidates)
    return { columns = columns, rows = rows }
  end
  local test = { columns = {}, rows = {} }
  for j = 1, tablua.before do test.columns[j] = tablua.columns[j] end
  for i, c in ipairs(candidates) do test.rows[i] = tablua.row(ctx, c) end
  return test
end

-- ctx: for "step", where the work stands (stage, pass, stalls, last verb and outcome, cause, own checks, the step
-- number n); for "control", the app and the verb; with task and at, the step a prediction is logged for.
-- candidates: move names ("step") or { id, role, label, order } controls ("control").
function L:rank(checkpoint, ctx, candidates)
  if not self.on() then return nil, "learning from past outcomes is turned off" end
  if not self.tabpfn then return nil, "TabPFN is not set up (the keychain has no arock-priorlabs)" end
  if not self.tablua then return nil, "no past outcomes to learn from yet" end
  if tokens_today(self) >= M.per_day then return nil, "today's TabPFN predictions are used up" end
  local ok, id, why = pcall(self.fitted, self, checkpoint)
  if not ok then return nil, "TabPFN could not be reached: " .. tostring(id) end
  if not id then return nil, why end
  local test = test_set(self, checkpoint, ctx, candidates)
  -- a state ranked before, but for its step number, is ranked the same again
  local parts = { checkpoint, tostring(id) }
  for _, row in ipairs(test.rows) do
    for j, v in ipairs(row) do
      if not (checkpoint == "step" and j == tablua.before) then parts[#parts + 1] = tostring(v) end
    end
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
    if tokens_today(self) + tokens > M.per_day then return nil, "today's TabPFN predictions are used up" end
    if self.memory then self.memory:called(checkpoint, tokens) end
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
  if ctx.task then
    for _, r in ipairs(ranked) do self.tablua:prediction(ctx.task, ctx.at or 0, M.head[checkpoint], r.name, r.p) end
  end
  return ranked
end

-- Scored predictions: each one whose outcome has since landed (the step it was for took that option).
function L:record(checkpoint)
  if not self.tablua then return { n = 0, right = 0 } end
  return self.tablua:scored(M.head[checkpoint])
end

-- The record as Jev reads it.
function L:record_line(checkpoint)
  local r = self:record(checkpoint)
  if r.n == 0 then return "its predictions here are not scored yet" end
  return ("right on %d of %d scored predictions here, Brier %.2f"):format(r.right, r.n, r.brier)
end

return M
