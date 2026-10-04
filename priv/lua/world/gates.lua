-- The harness's gates as named rows (arock issue #1, M5): each holds one move back in one state, and each but the
-- fixed ones (what a move can do at all, never policy) may be turned off for a run, so every gate is retired one
-- at a time through an A/B (ctx.gates_off, "stuck_fix,give_up"; AROCK_GATES_OFF in Arock's eval). The gates are
-- stated as keyword scenarios with their reasons in priv/gates.org, which the eval holds to the recorded effects;
-- the gates in force are written as Tablua's tablua_gate rows when a run starts (world/record.lua).
--
--   gates.blocking(run, c) -> the name of the first gate in force that holds c.move back, or nil
--     c: { move, req, last, repeats, stuck, w }      gates.list: { { name, what, fixed?, blocks } }
--   gates.off(run) -> { name = true }
local M = {}

M.list = {
  { name = "stuck_fix", what = "fixing the same failure again waits on thinking it through",
    blocks = function(c) return c.stuck and c.move == "fix_failure" end },
  { name = "publish_looked", what = "publishing waits on the app having been used since it changed",
    blocks = function(c) return c.move == "publish" and not c.req.looked end },
  { name = "think_twice", what = "thinking twice running changes nothing",
    blocks = function(c) return c.move == "think" and c.last and c.last.verb == "think" end },
  { name = "undo_regressed", what = "undo is there only after a change broke what passed", fixed = true,
    blocks = function(c) return c.move == "undo" and not c.req.undo end },
  { name = "shipped_answer", what = "once shipped, the task is answered", fixed = true,
    blocks = function(c) return c.req.stage == "shipped" and c.move ~= "answer_task" and not c.w.answer_failed(c.req) end },
  { name = "feature_after_fixing", what = "an agreed feature changes only once fixing the code stopped helping",
    blocks = function(c)
      return c.move == "write_feature" and c.req.stage == "building" and c.repeats < c.w.repeats
        and not c.w.checks_own(c.req.facts)
    end },
  -- green, with only checks in the app's own words left: rewriting the feature in the page's words is what moves it
  -- (a packing run looked, thought and tested 80 times, the remedy in its facts, and never rewrote the feature)
  { name = "own_checks_first", what = "green with only own-word checks left, the feature is rewritten first",
    blocks = function(c)
      return c.req.stage == "building" and c.w.checks_own(c.req.facts) and c.w.failing(c.req.facts or {}) == ""
        and not (c.move == "write_feature" or c.move == "read_help" or c.move == "blocked")
    end },
  { name = "dead_end", what = "past a dead end neither fixing nor thinking is offered",
    blocks = function(c) return c.repeats >= c.w.dead_end and (c.move == "fix_failure" or c.move == "think") end },
  { name = "give_up", what = "giving up leaves only a rewrite, the feature or stopping",
    blocks = function(c)
      return c.repeats >= c.w.give_up and not (c.move == "rewrite" or c.move == "write_feature" or c.move == "blocked")
    end },
  { name = "blocked_trouble", what = "blocked is offered only when the work is in trouble",
    blocks = function(c) return c.move == "blocked" and not c.w.troubled(c.req, c.repeats) end },
}

function M.off(run)
  local out = {}
  for name in tostring(run and run.gates_off or ""):gmatch("[%w_]+") do out[name] = true end
  return out
end

function M.blocking(run, c)
  local off = M.off(run)
  for _, g in ipairs(M.list) do
    if (g.fixed or not off[g.name]) and g.blocks(c) then return g.name end
  end
  return nil
end

return M
