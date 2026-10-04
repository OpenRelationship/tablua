-- What Arock remembers of its requests (PROJECT.md §11): every request, its steps and how each ended, as Robot
-- keyword rows in an Arock Core store (arock-log, core/arock-log) that outlives the app. The rows are the record the
-- Mailbox, the routines and the log read; what the agent learns from is Tablua's typed rows (core/tablua,
-- agent/learn.lua), and only the requests and the day's TabPFN tokens are folded back from these.
--
--   local m = memory.new(store, { today = fn })       store: store.open(db); today() -> "2026-09-29"
--   m:begin(text) -> task                             a request, in the person's words
--   m:step(task, s)            s = { n, verb, app, fails, last_verb, last_outcome, outcome, evidence, stage?, pass? }
--   m:outcome(task, label, evidence)                  how a request ended
--   m:made(task, what, where)                         something the request left behind: "file" and its path, or
--                                                     "page" and its address (the Mailbox's attachments)
--   m:called(checkpoint, tokens)   m:tokens_today() -> n (TabPFN tokens estimated for today's predictions)
--   m.requests[task] = { text, outcome }
--
-- Step labels (the host's, mechanical): complete, broken, no_effect, denied. Request labels: complete, partial,
-- failed, hallucination (Jev's judgement of the finished request) and interrupted (the conversation closed).
local M = {}
local Mem = {}
Mem.__index = Mem

local function num(s) return tonumber(s) or 0 end

function M.new(store, opts)
  local m = setmetatable({ store = store, today = (opts and opts.today) or function() return os.date("%Y-%m-%d") end,
    requests = {}, calls = {}, count = 0 }, Mem)
  for _, e in ipairs(store:events()) do m:fold(e.task, e.keyword, e.args) end
  return m
end

-- One row's meaning, whether it was just written or read back at open.
function Mem:fold(task, keyword, a)
  if keyword == "Request" then
    self.count = self.count + 1
    self.requests[task] = { text = a[1] or "" }
  elseif keyword == "Outcome" and a[1] == "request" then
    local r = self.requests[task]
    if r then r.outcome = a[2] end
  elseif keyword == "Predict Call" then
    self.calls[a[2] or ""] = (self.calls[a[2] or ""] or 0) + num(a[3])
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

function Mem:outcome(task, label, evidence) self:log(task, "Outcome", { "request", label, evidence or "" }, "agent") end
function Mem:made(task, what, where) self:log(task, "Made", { what, where }, "host") end

function Mem:called(checkpoint, tokens)
  self:log("learning", "Predict Call", { checkpoint, self.today(), tokens or 0 }, "host")
end
function Mem:tokens_today() return self.calls[self.today()] or 0 end

return M
