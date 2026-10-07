-- A studio run the way pi runs (owner, 2026-10-07): one model (MiniMax M3) in agent.loop with the studio's tools
-- builds a Moonsplice comp until it hands in. Tablua keeps the rows: every tool call is a step n with its state,
-- decision, features (what TabICL learns from), outcome and, for a change, the comp's snapshot and findings; every
-- message joins tablua_message. Jev judges each look (studio.judge). A hand-in with errors open, failing
-- expectations or no look at the comp as it is comes back to the model as a follow-up, once for each version of the
-- comp; the run ends when the model hands in again on a comp it already handed in, never on a cap.
--
--   local s = require("studio.session").new{ engine, model, tablua, comp, sheet, ask, kind?, exec, reference?,
--                                             judge?, todo?, window?, log? }
--   s:run() -> { stop, steps, pass, said }   said: the model's last words
--     engine: ports.moonsplice (brief, rows, lint, check, patch, expect, sheet); model: a chat port; judge: a Jev
--     port; reference: the engine's card (cadence/agent/REFERENCE.md); window: the model's context in tokens
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
    ask = o.ask, todo = o.todo or "run", n = 0, findings = {} }, S)
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

local function stage(s) return s:errors() > 0 and "building" or "polishing" end

-- the step a tool call is: its state and the decision the model made, before it runs (what TabICL reads)
local function begin(s, call, args)
  s.n = s.n + 1
  local name = call["function"] and call["function"].name
  local chosen = name == "patch" and type(args.moves) == "table" and type(args.moves[1]) == "table"
    and args.moves[1].move or name
  s.t:state{ todo = s.todo, n = s.n, stage = stage(s), pass = s:pass(), stalls = context.since(s.t, s.todo, s.n - 1),
    last_verb = s.last and s.last.verb or "", last_outcome = s.last and s.last.outcome or "", ask = s.ask }
  features.record(s.t, s.todo, s.n, features.read(s.t, s.todo, s.n, { game = s.kind == "game" and 1 or 0,
    render_s = s.render_s or -1 }))
  s.t:decision{ todo = s.todo, n = s.n, chosen = chosen, by = "model", propensity = 1, policy = "pi" }
end

local function finish(s, _, result)
  local d = result.details or {}
  local outcome = d.outcome or (result.is_error and "broken" or "complete")
  s.last = { verb = d.verb or "tool", outcome = outcome }
  s.t:outcome{ todo = s.todo, n = s.n, verb = s.last.verb, outcome = outcome,
    note = tostring(result.content or ""):sub(1, 500) }
  if s.o.log then s.o.log(("[step %d] %s -> %s"):format(s.n, s.last.verb, outcome)) end
end

-- the model would stop: a hand-in with errors, failing expectations or no look at this version comes back once
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
  if #open == 0 or s.refused == s.digest then return nil end
  s.refused = s.digest
  l:follow_up("Not handed in yet. " .. table.concat(open, "\n") .. "\nFix what you can and look; if something "
    .. "cannot be fixed, say why when you hand in again.")
  return nil
end

function S:run()
  self:snap(0)
  local model = loop.retrying(self.o.model)
  local l = loop.new{ model = model, system = prompts.system(self.kind, context.index(self.reference)),
    tools = tools.list(self), reasoning_effort = "low",
    transform = compact.transform(model, { window = self.o.window or M.window }),
    before_tool = function(call, args) begin(self, call, args) end,
    after_tool = function(_, args, result) finish(self, args, result) end,
    finish_turn = function(turn, lp) return handed_in(self, turn, lp) end,
    on = function(e)
      if e.type ~= "message" then return end
      local m = e.message
      if m.role == "assistant" and not self.treatment and (m.content or "") ~= "" then self.treatment = m.content end
      self.t:message(self.todo, self.n, m)
    end }
  self.loop = l
  local out = l:prompt(("The ask (a %s): %s"):format(self.kind == "game" and "game" or "motion piece", self.ask))
  return { stop = out.stop, error = out.error, steps = self.n, pass = self:pass(), said = self.said }
end

return M
