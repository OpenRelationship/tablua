-- A studio run the way pi runs (owner, 2026-10-07): one model (MiniMax M3) in agent.loop with the studio's tools
-- builds a Moonsplice comp until it hands in. Tablua keeps the rows: every tool call is a step n with its state,
-- decision, features (what TabICL learns from), outcome and, for a change, the comp's snapshot and findings; every
-- message joins tablua_message. Jev judges each look (studio.judge). A hand-in with errors open, failing
-- expectations or no look at the comp as it is comes back to the model as a follow-up; the run ends when the model
-- answers a send-back without calling a tool, never on a cap.
--
--   local s = require("studio.session").new{ engine, model, tablua, comp, sheet, ask, kind?, exec, reference?,
--                                             judge?, learn?, todo?, compact?, log? }
--   s:run() -> { stop, status, steps, pass, said }   status: complete (handed in with no errors and every expectation
--                                             holding) or partial; said: the model's last words
--     learn: agent.learn with step = studio.features.learner(t): before a patch it ranks the moves from states like
--     this one (TabICL, local) and the predictions are kept as rows; it never blocks. Its line reaches the model only
--     with learner_shown, which waits on The Learner Beats The Base Rate (killed 2026-10-07, Brier 0.218 against 0.089)
--     expect_first: a patch before the model has written an expectation of its own is refused (default true): pi-s6
--     made twenty set_prop and look pairs with nothing of its own to converge on, and never handed in
--     engine: ports.moonsplice (brief, rows, lint, check, patch, expect, sheet); model: a chat port; judge: a Jev
--     port; reference: the engine's card (Moonsplice's .robot/docs/reference.robot); compact: { window, reserve?, keep? }, the
--     model's context in tokens: near it, the turns before the cut become a checkpoint rendered from the tables
local loop = require("agent.loop")
local compact = require("agent.compact")
local tools = require("studio.tools")
local prompts = require("studio.prompts")
local features = require("studio.features")
local context = require("studio.context")

local M = {}
local S = {}
S.__index = S

M.window = 196608

function M.new(o)
  local s = setmetatable({ o = o, t = assert(o.tablua, "session needs the run's tablua handle"), engine = o.engine,
    comp = o.comp, sheet = o.sheet, exec = o.exec, reference = o.reference, judge = o.judge, kind = o.kind or "video",
    ask = o.ask, todo = o.todo or "run", n = 0, findings = {}, expect_first = o.expect_first ~= false }, S)
  return s
end

-- the comp as it stands now, as step n's snapshot (n = 0 before any step)
function S:snap(n, findings)
  local rows = self.engine:rows(self.comp)
  self.t:comp(self.todo, n, rows)
  self.digest, self.snapped = rows.digest, n
  if not findings then
    findings = self.engine:lint(self.comp)
    for _, f in ipairs(self.engine:check(self.comp)) do findings[#findings + 1] = f end
  end
  self.t:findings(self.todo, n, findings)
  self.findings = findings
  return rows
end

function S:errors()
  local k, x = 0, 0
  for _, f in ipairs(self.findings) do
    if (f.severity or "error") == "error" then
      k = k + 1
      if f.code == "expect_failed" then x = x + 1 end
    end
  end
  return k, x
end

-- the share of seven checks that hold: no errors, and each of the judge's six at 3 or more on the comp as it is
function S:pass()
  local held = self:errors() == 0 and 1 or 0
  if self.critic and self.looked == self.digest then
    for _, k in ipairs(prompts.order) do if (self.critic.scores[k] or 0) >= 3 then held = held + 1 end end
  end
  return held / 7
end

-- the expectation rows at the newest snapshot
function S:expects()
  return self.t.db:exec("select count(*) as c from tablua_msr_expect where todo = ? and n = ?",
    { self.todo, self.snapped or 0 })[1].c
end

local function stage(s) return s:errors() > 0 and "building" or "polishing" end

-- the comp's state in one line, from the newest snapshot: what every result ends with, so the newest message in an
-- append-only transcript always says what is true (Moonsplice's spec, 2026-10-07)
function S:state_line()
  local errs, fail = {}, {}
  local warnings = 0
  for _, f in ipairs(self.findings) do
    if (f.severity or "error") == "error" then
      local id = f.code == "expect_failed" and tostring(f.detail or ""):match("%(expect ([^)]+)%)%s*$")
      if id then fail[#fail + 1] = id
      elseif #errs < 5 then errs[#errs + 1] = f.code .. ((f.id or "") ~= "" and (" " .. f.id) or "") end
    elseif f.severity == "warn" then warnings = warnings + 1 end
  end
  -- as the engine's own state line counts them: a failing expectation is under expect, not among the errors (pi-s5
  -- read "errors 0" from the engine and "errors 6" from this line on one comp)
  local all, failing = self:errors()
  local errors = all - failing
  local total = self:expects()
  return ("state: digest %s; errors %d%s; warnings %d; expect %d/%d%s; step %d"):format(tostring(self.digest or ""):sub(1, 8),
    errors, #errs > 0 and (" (" .. table.concat(errs, ", ") .. (errors > #errs and ", ..." or "") .. ")") or "", warnings,
    total - #fail, total, #fail > 0 and (" (failing: " .. table.concat(fail, ", ") .. ")") or "", self.n)
end

-- the tables as the checkpoint a compaction leaves, in pi's sections, exact and with no model call: the ask and the
-- treatment, the comp as it is, every step's line, the model's last words, and the last look
function S:checkpoint()
  local brief = ""
  local ok, text = pcall(self.engine.brief, self.engine, self.comp)
  if ok then brief = text end
  local said = ""
  for i = #(self.loop and self.loop.messages or {}), 1, -1 do
    local m = self.loop.messages[i]
    if m.role == "assistant" and (m.content or "") ~= "" then said = m.content break end
  end
  return ("## Goal\nThe ask: %s\nTreatment: %s\n\n## State\n%s\n%s\n\n## Progress\n%s\n\n## Last intent\n%s\n\n## Next\n%s")
    :format(self.ask, self.treatment or "(none written)", brief, self:state_line(),
      context.history(self.t, self.todo, self.n), said:sub(1, 800), self.judged or "No look yet.")
end

-- the step a tool call is: its state and the decision the model made, before it runs (what TabICL reads)
local function begin(s, call, args)
  s.n = s.n + 1
  s.worked = true
  local name = call["function"] and call["function"].name
  local chosen = name == "patch" and type(args.moves) == "table" and type(args.moves[1]) == "table"
    and args.moves[1].move or name
  s.t:state{ todo = s.todo, n = s.n, stage = stage(s), pass = s:pass(), stalls = context.since(s.t, s.todo, s.n - 1),
    last_verb = s.last and s.last.verb or "", last_outcome = s.last and s.last.outcome or "", ask = s.ask }
  features.record(s.t, s.todo, s.n, features.read(s.t, s.todo, s.n, { game = s.kind == "game" and 1 or 0,
    render_s = s.render_s or -1 }))
  s.t:decision{ todo = s.todo, n = s.n, chosen = chosen, by = "model", propensity = 1, policy = "pi" }
  s.ranked = nil
  if s.o.learn and name == "patch" then
    local ok, ranked = pcall(s.o.learn.rank, s.o.learn, "step", { todo = s.todo, n = s.n, at = s.n, stage = stage(s),
      pass = s:pass(), stalls = context.since(s.t, s.todo, s.n - 1), last_verb = s.last and s.last.verb or "",
      last_outcome = s.last and s.last.outcome or "" }, tools.edits)
    if ok and type(ranked) == "table" and #ranked > 0 then s.ranked = ranked end
  end
end

-- TabICL's line: its best move from states like this one, and the chosen one's chance
local function learner_line(s)
  if not s.ranked then return nil end
  local best = s.ranked[1]
  local mine
  for _, r in ipairs(s.ranked) do if r.name == (s.last and s.last.verb) then mine = r end end
  return ("learner: from states like this, %s %.2f to close something%s"):format(best.name, best.p, mine
    and mine ~= best and ("; %s %.2f"):format(mine.name, mine.p) or "")
end

local function finish(s, call, result)
  local d = result.details or {}
  local outcome = d.outcome or (result.is_error and "broken" or "complete")
  s.last = { verb = d.verb or (call and call["function"] and call["function"].name) or "tool", outcome = outcome }
  s.t:outcome{ todo = s.todo, n = s.n, verb = s.last.verb, outcome = outcome,
    note = tostring(result.content or ""):sub(1, 500) }
  if s.o.log then s.o.log(("[step %d] %s -> %s"):format(s.n, s.last.verb, outcome)) end
  if d.verb == "reference" then return nil end
  local lines = { tostring(result.content or "") }
  if s.o.learner_shown then lines[#lines + 1] = learner_line(s) end
  lines[#lines + 1] = d.state or s:state_line()
  if d.delta then lines[#lines + 1] = d.delta end
  return { content = table.concat(lines, "\n") }
end

-- the model would stop: a hand-in with errors, failing expectations, no look at this version, no expectations of
-- the model's own or no change from the seed comes back, unless the model is answering a send-back with no tool call
local function handed_in(s, turn, l)
  if turn.message.tool_calls then return nil end
  s.said = turn.message.content
  local errors, failing = s:errors()
  local open = {}
  if errors > 0 then
    open[#open + 1] = ("%d errors are open%s:\n%s"):format(errors, failing > 0 and (", " .. failing
      .. " of them expectations failing") or "", tools.found(s.findings, 12))
  end
  if s.looked ~= s.digest then open[#open + 1] = "You have not looked at the comp as it is now." end
  if s:expects() <= s.seed_expects then
    open[#open + 1] = "Write what the ask requires as expectations first (expect): none of the comp's are yours."
  end
  if s.digest == s.seed then open[#open + 1] = "The comp is as it was given: nothing has changed." end
  -- the run ends when the model answers a send-back without trying anything: a reply with no tool call after work on
  -- an unchanged comp is not a hand-in (pi-g2 ended on "Let me try editing hud first" after two rejected patches)
  if #open == 0 or (s.sent_back and not s.worked) then return nil end
  s.sent_back, s.worked = true, false
  l:follow_up("Not handed in yet. " .. table.concat(open, "\n") .. "\nFix what you can and look; if something "
    .. "cannot be fixed, say why when you hand in again.")
  return nil
end

function S:run()
  self:snap(0)
  self.seed, self.seed_expects = self.digest, self:expects()
  self.seed_ids = {}
  for _, x in ipairs(self.t:comp_rows(self.todo, 0).tables.expect or {}) do self.seed_ids[x.id] = true end
  local model = loop.retrying(self.o.model)
  local l = loop.new{ model = model, system = prompts.system(self.kind, context.index(self.reference)),
    tools = tools.list(self), reasoning_effort = "low",
    transform = compact.transform(model, { window = (self.o.compact or {}).window or M.window,
      reserve = (self.o.compact or {}).reserve, keep = (self.o.compact or {}).keep,
      render = function() return self:checkpoint() end }),
    before_tool = function(call, args)
      if self.expect_first and call["function"] and call["function"].name == "patch"
        and self:expects() <= self.seed_expects then
        return { block = true, reason = "Write what the ask requires as expectations first (expect), each saying when: "
          .. "they are what done means for this comp. Then patch toward them." }
      end
      begin(self, call, args)
    end,
    after_tool = function(call, _, result) return finish(self, call, result) end,
    finish_turn = function(turn, lp) return handed_in(self, turn, lp) end,
    on = function(e)
      if e.type ~= "message" then return end
      local m = e.message
      if m.role == "assistant" and not self.treatment and (m.content or "") ~= "" then self.treatment = m.content end
      self.t:message(self.todo, self.n, m)
    end }
  self.loop = l
  local out = l:prompt(("The ask (a %s): %s"):format(self.kind == "game" and "game" or "motion piece", self.ask))
  local errors = self:errors()
  -- a hand-in on the comp as it was given is never complete, whatever its findings (pi-s4 handed in the seed)
  local status = (out.stop == "stop" and errors == 0 and self.digest ~= self.seed) and "complete" or "partial"
  self.t:run{ todo = self.todo, shipped = out.stop == "stop", answered = out.stop == "stop", works = status == "complete",
    changed = self.digest ~= self.seed, steps = self.n }
  return { stop = out.stop, status = status, error = out.error, steps = self.n, pass = self:pass(), said = self.said }
end

return M
