-- The world's reading of its computer's facts (split from world.lua, issue #1 M1): the stage and why, what is
-- failing, how a step left things, the gates' counts, and the facts as Jev and Mercury read them. It adds its
-- functions to the world's module, so world.stage, world.after and the rest are where they were.
local clip = require("agent.clip").clip

return function(M)

-- The stage from the facts, and why: code's judgement, never a model's.
--   facts = { features = { { path, stage } }, tests = { passed, total, failing = {}, undefined = {} } | nil,
--             empty_steps = n, pages = { { path, status } }, asked = bool, shipped = bool, answered = bool }
-- since: how many publishes the computer had when this task began; an app that shipped before it is one the task
-- changes, not one it has shipped
function M.stage(f, since)
  if f.answered then return "answered", "the task is answered DONE" end
  if f.shipped and (f.publishes or 0) <= (since or -1) then
    return "changing", "the app shipped before this task: change it as the task asks"
  end
  if f.shipped then return "shipped", "the app has shipped; the task is not answered yet" end
  if f.asked then return "awaiting_yes", "publishing waits for the person's yes" end
  if #f.features == 0 then return "no_feature", "there is no feature yet" end
  for _, ft in ipairs(f.features) do
    -- a feature the person asked for in a writ, its scenarios not written yet: the loop writes them
    if ft.stage == "asked" then return "building", ft.path .. " only asks: write its scenarios (Scenario: and its steps)" end
    if ft.stage == "written" then return "awaiting_agreement", ft.path .. " is written and not agreed" end
  end
  local t, why = f.tests, {}
  if not t or t.total == 0 then why[#why + 1] = "no test has run since the last change" end
  if t and t.passed < t.total then why[#why + 1] = ("%d of %d scenarios pass"):format(t.passed, t.total) end
  if t and #t.undefined > 0 then why[#why + 1] = #t.undefined .. " steps have no definition" end
  if (f.empty_steps or 0) > 0 then why[#why + 1] = f.empty_steps .. " step definitions check nothing (an empty body)" end
  if f.page_steps and t and #(t.checked or {}) > 0 then
    -- what to do first, then at most two of them: a long list once pushed the remedy past where the facts are cut,
    -- and runs whose tests were green blocked instead of changing the feature
    local some = {}
    for i = 1, math.min(2, #t.checked) do some[i] = t.checked[i] end
    -- (an empty list's check had no page form here, and a run rewrote the same feature unchanged until it blocked)
    why[#why + 1] = #t.checked .. ' checks use steps of the app\'s own, not the page\'s: write_feature rewrites each'
      .. ' in its file as I see "x", I see "x" for "row" or I do not see "x", in the words the page shows ('
      .. table.concat(some, "; ")
      .. (#t.checked > 2 and "; ..." or "") .. ")"
  end
  -- (a module asked for, run.kind "module", is code and its steps alone: an Exercism exercise has no page)
  if #f.pages == 0 and not f.module then why[#why + 1] = "the app has no page" end
  for _, p in ipairs(f.pages) do
    if p.status ~= 200 then why[#why + 1] = ("the page %s answers %d"):format(p.path, p.status) end
  end
  if #why > 0 then return "building", table.concat(why, "; ") end
  return "ready", "every scenario passes and every page answers"
end

-- A page-steps run's checks answered by the app's own steps: only the feature can change them, so writing it is
-- offered at once (habits passed every test and blocked after 115 steps, the one move that could fix it withheld)
function M.checks_own(f)
  local t = f and f.tests
  return f and f.page_steps and t and #(t.checked or {}) > 0 or false
end

-- No test has run since the last change (or none could): what is failing is not known yet
function M.untested(f)
  local t = f and f.tests
  return not t or (t.total or 0) == 0
end

-- What is failing, as one string: the same string after a change means the change fixed nothing.
function M.failing(f)
  local out, t = {}, f.tests
  if t then
    for _, x in ipairs(t.failing) do out[#out + 1] = x end
    for _, x in ipairs(t.undefined) do out[#out + 1] = "no step: " .. x end
  end
  if (f.empty_steps or 0) > 0 then out[#out + 1] = f.empty_steps .. " empty steps" end
  for _, p in ipairs(f.pages) do
    if p.status ~= 200 then out[#out + 1] = ("%s answers %d"):format(p.path, p.status) end
  end
  return table.concat(out, "\n")
end

-- the moves running, newest first, that Mercury could not fill (thinking between them does not break the run)
function M.unfilled(req)
  local n = 0
  for i = #req.steps, 1, -1 do
    local s = req.steps[i]
    if s.verb ~= "think" then
      if not (s.note and s.note:find("^Filling the move failed")) then break end
      n = n + 1
    end
  end
  return n
end

M.repeats = 2   -- changes that left the same failure, after which fixing it again waits on thinking it through
M.dead_end = 4  -- after which fixing and thinking are no longer offered: rewrite, change the feature, or stop
M.give_up = 8   -- after which only rewriting, changing the feature or stopping is
-- the stages the agent's own moves advance (not waiting on the person, not done)
M.working = { no_feature = true, building = true, ready = true, changing = true }

-- How a step's change left the work, against the facts before it: the step's note, which both minds read in the
-- work so far. Counts the changes running that left the same failure in req.repeats.
function M.after(req, before, f)
  local was, now = M.failing(before), M.failing(f)
  local t0, t = before.tests, f.tests
  local out = {}
  if t then
    out[1] = ("Test after: %d of %d pass"):format(t.passed, t.total)
      .. (t0 and (" (before: %d of %d)."):format(t0.passed, t0.total) or ".")
  end
  -- fewer scenarios pass than before the change: it broke what worked
  req.regressed = (t and t0 and t.passed < t0.passed) and ("%d of %d to %d of %d"):format(t0.passed, t0.total,
    t.passed, t.total) or nil
  if req.regressed then out[#out + 1] = "This change broke scenarios that passed." end
  -- a stall: something failed before and fails after, and no more scenarios pass. The same failure's words are one;
  -- a failure reworded is another (a pantry run's 26 fixes each changed the message a little, so the count kept
  -- starting again and fixing was never taken away)
  -- and a step is measured against the most that ever passed of the same scenarios, not the step before: going back
  -- up to it is not moving on (a circular-buffer run went 6, 4, 6 of 10 through a hundred rewrites, each climb back
  -- starting the count again, and no gate that ends a loop came into force, 2026-10-05)
  local best = t and req.best and req.best.total == t.total and req.best.passed or nil
  local stalled = now ~= "" and was ~= "" and (now == was or (t ~= nil and t0 ~= nil and t.passed <= t0.passed)
    or (best ~= nil and t.passed <= best))
  if t and t.total > 0 and (not req.best or req.best.total ~= t.total or t.passed > req.best.passed) then
    req.best = { passed = t.passed, total = t.total }
  end
  -- with nothing failing, a step that left the stage where it was, for the same reason, stalled too: a green app
  -- short of ready (a packing run read the help seven times, every scenario passing, then blocked) or ready and
  -- not published moved nothing on, and without counting it no gate that ends a loop ever came into force
  local idle = false
  if now == "" and was == "" and before.features and f.features then
    local stage0, why0 = M.stage(before, req.publishes0)
    local stage1, why1 = M.stage(f, req.publishes0)
    idle = stage0 == stage1 and why0 == why1 and M.working[stage1] and { stage1, why1 }
  end
  if stalled then
    req.repeats = (req.repeats or 0) + 1
    out[#out + 1] = (now == was and "The same failure as before this step (%d changes running have left it): %s"
      or "No more scenarios pass than before this step (%d changes running have moved nothing on): %s"):format(
      req.repeats, clip(now, 300))
  elseif idle then
    req.repeats = (req.repeats or 0) + 1
    out[#out + 1] = ("Nothing moved on: the work is %s as before this step (%d steps running), because %s.")
      :format(idle[1], req.repeats, clip(idle[2], 300))
  else
    req.repeats = 0
  end
  return table.concat(out, " ")
end

-- The facts in a few lines, as both minds read them.
--   s = { stage, why, repeats, looked, unfilled, regressed }: what the world knows of the run beside the facts
-- a call as the computer should run it: every command in /home (a folder of the model's own was a guess), and the
-- app, being /home, published by publish alone (a budget run's publish expense_tracker asked for an app under apps/
-- that is not there, four times, then blocked)
function M.tidy(verb, c)
  c.cwd = nil
  -- files as the tool defines them, an object of path to text: Mercury once sent it as JSON in a string, and the
  -- run stopped on pairs over a string
  if type(c.files) == "string" then
    local ok, v = pcall(require("ports.json").decode, c.files)
    c.files = ok and type(v) == "table" and v or nil
  elseif c.files ~= nil and type(c.files) ~= "table" then
    c.files = nil
  end
  if verb == "publish" and c.cmd then c.cmd = c.cmd:gsub("^(%s*publish)%s+[%w_%-]+%s*$", "%1") end
  return c
end

-- whether stopping can be right: something fails, Mercury could not fill a move, fixing has stopped helping, or the
-- last step broke (a chores run, every scenario passing and publish offered, blocked saying nothing was missing)
function M.troubled(req, repeats)
  local last = req.steps[#req.steps]
  -- (one move Mercury could not fill is a service's bad minute, tried again; two running is the tool failing)
  return M.failing(req.facts) ~= "" or M.unfilled(req) >= 2 or repeats >= M.repeats
    or (last ~= nil and last.outcome ~= "complete" and not (last.note or ""):find("^Filling the move failed"))
end

-- an answer_task step that did not come out complete
function M.answer_failed(req)
  for _, st in ipairs(req.steps) do
    if st.verb == "answer_task" and st.outcome ~= "complete" then return true end
  end
  return false
end

-- a break in the program (tablua_break) as both minds read it, or nil for one the tests already name
function M.broken(b)
  if b.kind == "calls" then
    local mod, fn = b.target:match("^([%w_]+)%.(.+)$")
    return ("%s calls %s.%s, which code/%s.lua does not define"):format(b.file, mod, fn, mod)
  elseif b.kind == "post" then
    return ("%s posts to %s, which no action defines"):format(b.file, b.target)
  elseif b.kind == "reads" then
    return ("the action %s reads the field %s, which no form sends"):format(b.source, b.target)
  end
end

function M.facts_text(f, s)
  local stage, repeats = s.stage, s.repeats
  local out = { ("Stage: %s (%s)."):format(stage, s.why) }
  local said = {}
  for _, b in ipairs(f.breaks or {}) do
    local line = M.broken(b)
    if line and #said < 3 then said[#said + 1] = line end
  end
  if #said > 0 then
    out[#out + 1] = "Broken in the program, before any test: " .. table.concat(said, "; ")
      .. ". Fix the side that is missing (the module's code, the action), not the side that names it."
  end
  if (s.unfilled or 0) >= 2 then
    out[#out + 1] = ("Mercury, who fills the moves, failed on the last %d moves: the agent's own tool is failing,"
      .. " not the app."):format(s.unfilled)
  end
  if s.regressed then
    out[#out + 1] = ("The last change broke scenarios that passed (%s): undo puts its files back as they were.")
      :format(s.regressed)
  end
  if stage == "shipped" then
    out[#out + 1] = "The person said yes and the app is published: nothing waits on them any more; answer the task."
  elseif stage == "changing" then
    out[#out + 1] = "This task asks to change the app as it shipped. Change the feature first when the task changes"
      .. " what the app does (the person agrees to it again), then its steps, code and page; it ships again by publish."
      .. " The change adds to the app: everything the page showed before (its lists, totals and their order) stays."
  end
  if stage == "ready" and not s.looked then
    out[#out + 1] = "Nobody has used the app as the person will since it last changed: publishing waits on"
      .. " look_at_app (open it, add something, see it there)."
  end
  for _, ft in ipairs(f.features) do out[#out + 1] = ("Feature %s: %s."):format(ft.path, ft.stage) end
  if f.tests then
    local t = f.tests
    out[#out + 1] = ("Last test: %d of %d scenarios pass."):format(t.passed, t.total)
    for i = 1, math.min(5, #t.failing) do out[#out + 1] = "  failing: " .. clip(t.failing[i], 300) end
    for i = 1, math.min(5, #t.undefined) do out[#out + 1] = "  no step: " .. clip(t.undefined[i], 200) end
  end
  for _, p in ipairs(f.pages) do
    out[#out + 1] = ("Page %s (%s) answers %d%s"):format(p.path, M.open(p.path), p.status,
      p.error and (": " .. clip(p.error, 300)) or ".")
    if p.own_db then
      out[#out + 1] = "  " .. p.own_db .. " opens its database itself, so no step tests what it shows: let it require"
        .. " the code module the steps test, and keep the SQL there."
    end
    if p.nils then
      out[#out + 1] = "  it shows nothing for " .. clip(p.nils, 300) .. " (nil: a name the code does not set?)"
    end
  end
  if (repeats or 0) >= M.dead_end then
    out[#out + 1] = ("The last %d changes left the same failure, thinking between them: fixing it piece by piece"
      .. " has failed. Rewrite the failing code whole from the feature, change the feature if it cannot pass as"
      .. " written (the person agrees again), or stop as blocked."):format(repeats)
  elseif (repeats or 0) >= M.repeats then
    out[#out + 1] = ("The last %d changes left the same failure: what was tried is not the cause. Think it through"
      .. " (read the help on what the failing code uses, and the code the step calls) before changing it again.")
      :format(repeats)
  end
  return table.concat(out, "\n")
end

end
