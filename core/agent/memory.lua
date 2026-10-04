-- What Arock remembers of how its work turned out (PROJECT.md §11): every request, every tool step and
-- the controls it chose from, how each ended, and what TabPFN predicted, as Robot keyword rows in an Arock Core store
-- (arock-log, core/arock-log) that outlives the app. The rows are the record; what is read back is folded from them.
--
--   local m = memory.new(store, { today = fn })       store: store.open(db); today() -> "2026-09-29"
--   m:begin(text) -> task                             a request, in the person's words
--   m:step(task, s)            s = { n, verb, app, fails, last_verb, last_outcome, outcome, evidence, stage?, pass? }
--   m:sure(task, n, verb, p, confidence)             the probability Jev gave the verb it picked (calibrate.lua)
--   m:controls(task, n, verb, app, controls, chosen)  the reading a control step chose from, and its choice
--   m:outcome(task, label, evidence)                  how a request ended
--   m:made(task, what, where)                         something the request left behind: "file" and its path, or
--                                                     "page" and its address (the Mailbox's attachments)
--   m:predict(checkpoint, candidate, p, task, n)      m:called(checkpoint, tokens)   m:fitted(checkpoint, schema, id, rows)
--   m:prune(checkpoint, kept, dropped, rule)
--   m.requests[task] = { text, outcome }   m.steps = { s... }   m.choices = { ... }   m.predictions = { ... }
--   m:tokens_today() -> n (TabPFN tokens estimated for today's predictions)   m:fit(checkpoint, schema) -> { id, rows } | nil
--
-- Step labels (the host's, mechanical): complete, broken, no_effect, denied. Request labels: complete, partial,
-- failed, hallucination (Jev's judgement of the finished request) and interrupted (the conversation closed).
local json = require("ports.json")

local M = {}
local Mem = {}
Mem.__index = Mem

M.max_controls = 200   -- controls kept of one reading

local function num(s) return tonumber(s) or 0 end

function M.new(store, opts)
  local m = setmetatable({ store = store, today = (opts and opts.today) or function() return os.date("%Y-%m-%d") end,
    requests = {}, steps = {}, choices = {}, predictions = {}, calls = {}, fits = {}, count = 0 }, Mem)
  for _, e in ipairs(store:events()) do m:fold(e.task, e.keyword, e.args) end
  return m
end

-- One row's meaning, whether it was just written or read back at open.
function Mem:fold(task, keyword, a)
  if keyword == "Request" then
    self.count = self.count + 1
    self.requests[task] = { text = a[1] or "" }
  elseif keyword == "Step" then
    local s = { task = task, n = num(a[1]), verb = a[2], app = a[3] or "", fails = num(a[4]), last_verb = a[5] or "",
      last_outcome = a[6] or "", stage = a[7] or "", pass = tonumber(a[8]) or -1 }
    self.steps[#self.steps + 1] = s
    self.last_step = s
  elseif keyword == "Sure" then
    for i = #self.steps, 1, -1 do
      local s = self.steps[i]
      if s.task == task and s.n == num(a[1]) then s.p, s.confidence = tonumber(a[3]), tonumber(a[4]); break end
    end
  elseif keyword == "Outcome" and a[1] == "step" then
    for i = #self.steps, 1, -1 do
      local s = self.steps[i]
      if s.task == task and s.n == num(a[4]) then s.outcome, s.evidence = a[2], a[3]; break end
    end
  elseif keyword == "Outcome" and a[1] == "request" then
    local r = self.requests[task]
    if r then r.outcome = a[2] end
  elseif keyword == "Controls" then
    local ok, list = pcall(json.decode, a[4] or "[]")
    self.choices[#self.choices + 1] = { task = task, n = num(a[1]), verb = a[2], app = a[3] or "",
      controls = ok and list or {} }
  elseif keyword == "Chose Control" then
    local c = self.choices[#self.choices]
    if c and c.task == task and c.n == num(a[2]) then c.chosen = a[1] end
  elseif keyword == "Predict" then
    self.predictions[#self.predictions + 1] = { checkpoint = a[1], candidate = a[2], p = num(a[3]), task = task,
      n = num(a[4]) }
  elseif keyword == "Predict Call" then
    self.calls[a[2] or ""] = (self.calls[a[2] or ""] or 0) + num(a[3])
  elseif keyword == "Fit" then
    self.fits[a[1] .. "/" .. a[2]] = { id = a[3], rows = num(a[4]) }
  end
end

function Mem:log(task, keyword, args, actor)
  for i, v in ipairs(args) do args[i] = tostring(v) end
  self.store:append(task, keyword, args, actor or "agent")
  self:fold(task, keyword, args)
end

function Mem:begin(text)
  local task = "request-" .. (self.count + 1)
  self:log(task, "Request", { text }, "user")
  return task
end

function Mem:step(task, s)
  self:log(task, "Step", { s.n, s.verb, s.app or "", s.fails or 0, s.last_verb or "", s.last_outcome or "",
    s.stage or "", s.pass and ("%.3f"):format(s.pass) or "" })
  self:log(task, "Outcome", { "step", s.outcome, s.evidence or "", s.n }, "host")
end

function Mem:sure(task, n, verb, p, confidence)
  self:log(task, "Sure", { n, verb, ("%.3f"):format(p), confidence and ("%.3f"):format(confidence) or "" })
end

-- The step's controls, cut to the first M.max_controls, as one JSON argument.
function Mem:controls(task, n, verb, app, controls, chosen)
  local keep = {}
  for i = 1, math.min(#controls, M.max_controls) do
    local c = controls[i]
    keep[i] = { id = c.id, role = c.role, label = c.label, order = c.order }
  end
  self:log(task, "Controls", { n, verb, app or "", json.encode(json.array(keep)) }, "host")
  if chosen then self:log(task, "Chose Control", { chosen, n }) end
end

function Mem:outcome(task, label, evidence) self:log(task, "Outcome", { "request", label, evidence or "" }, "agent") end
function Mem:made(task, what, where) self:log(task, "Made", { what, where }, "host") end

function Mem:predict(checkpoint, candidate, p, task, n)
  self:log(task or "learning", "Predict", { checkpoint, candidate, ("%.4f"):format(p), n or 0 }, "host")
end

function Mem:called(checkpoint, tokens)
  self:log("learning", "Predict Call", { checkpoint, self.today(), tokens or 0 }, "host")
end
function Mem:tokens_today() return self.calls[self.today()] or 0 end

function Mem:fitted(checkpoint, schema, id, rows) self:log("learning", "Fit", { checkpoint, schema, id, rows }, "host") end
function Mem:fit(checkpoint, schema) return self.fits[checkpoint .. "/" .. schema] end

function Mem:prune(checkpoint, kept, dropped, rule)
  self:log("learning", "Prune Memory", { checkpoint, kept, dropped, rule }, "host")
end

-- A step's outcome, as far as learning is concerned: it worked, and the request it served was not judged a
-- failure or a false claim. 1, 0, or nil when it has no outcome yet.
function Mem:worked(s)
  if not s.outcome then return nil end
  local r = self.requests[s.task]
  local bad = r and (r.outcome == "failed" or r.outcome == "hallucination")
  return (s.outcome == "complete" and not bad) and 1 or 0
end

-- The step a choice of control belongs to.
function Mem:step_of(task, n)
  for i = #self.steps, 1, -1 do
    local s = self.steps[i]
    if s.task == task and s.n == n then return s end
  end
end

return M
