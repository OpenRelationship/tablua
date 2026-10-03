-- The agent's own computer as the world Arock's agent works in (library/agent; Arock PROJECT.md §14, feature
-- file-kinds): it builds what the person asks as an app, agreed to shipped, and answers the task. Code owns the
-- workflow (TypeSafe's rule): the stage and its gates are worked out from the computer's facts (the host's, never a
-- model's), and Jev is offered only the moves the stage allows. Jev picks the move; Mercury fills it with tool calls
-- on the computer (world_prompt.lua, laid out as Inception's guide says); the person's part (agreeing to a feature,
-- the yes to publish) is waited for, never done here.
--
--   local world = require("moss.world").new(host, run)   host = { exec(req) -> { code, stdout, stderr }, facts() }
--   run = { help, procedures, task }                      what Mercury's fixed context holds, read once a run
--   world.stage(facts) -> stage, why
local prompt = require("moss.world.prompt")
local undo = require("moss.world.undo")
local clip = require("agent.clip").clip

local M = {}

-- Each move as Jev reads it: a name in words and what it is for.
M.moves = {
  write_feature = "Write the feature: the person's ask, in their words, as Gherkin scenarios (new feature <name>,"
    .. " then edit it), or change it before the person has agreed; once agreed, change it only when it cannot pass"
    .. " as written, and the person agrees to it again.",
  wait_for_agreement = "The feature is written and the person has not agreed to it yet: wait for them. Nothing is"
    .. " built before they agree.",
  write_steps = "Write the Lua steps in code/steps/ that make each scenario check the app's real behaviour, from the"
    .. " stubs test printed.",
  write_code = "Write the app's code (code/*.lua) and its database (data/*.dbl) that the steps and pages use.",
  write_page = "Write or fix the app's pages (ui/*.lui): what the person sees and uses.",
  run_test = "Run the feature's tests (test) to see what passes, what fails and which steps are missing.",
  run_check = "Check the pages and code (check) for what is wrong in them.",
  fix_failure = "Fix what the last test, check or page named as failing, from its file and line.",
  undo = "Put back the files the last change wrote, as they were: it broke scenarios that passed before it.",
  rewrite = "Throw out the file the failure is in and write it again whole, from the knowledge base's patterns:"
    .. " for when patching it has not worked.",
  look_at_app = "Open the app as the person will (open app) and use it: add something, see it there.",
  read_help = "Read the computer's help on a kind of file or a command, when how to do the next thing is unclear.",
  publish = "Publish the app: every test is green and every page answers, so it goes to the person for their yes.",
  wait_for_yes = "Publishing waits for the person's yes: wait for it.",
  answer_task = "The app has shipped: answer the task with a DONE letter that names what shipped and where.",
  answer = "The task is answered: the work is done.",
  think = "Think it through first: go over the task and every step so far, say what is wrong and what to do next."
    .. " For when the app's tests or pages keep failing, or the way on is unclear.",
  blocked = "Stop and report: the agent's own tools keep failing (Mercury could not fill a move, the computer"
    .. " itself errs), or what is needed is not among these moves. Never for a mistyped command or a failing test or"
    .. " page: those are the app's to fix. Say what is missing.",
}

-- Where the failure's cause lies, asked beside the move whenever something is failing (TypeSafe: narrow questions,
-- batched in one call); Mercury is told the answer when it fills the move.
M.causes = {
  the_steps = "The step definitions: a step that does not match its line in the feature, checks the wrong thing,"
    .. " or is missing.",
  the_app_code = "The app's code or its database: what the steps and pages call does the wrong thing.",
  the_page = "The page: it does not compile, or its action or markup is wrong.",
  a_library_call = "A call into the computer's library (db, date, test, lui, mail) made the wrong way, such as a"
    .. " missing or wrong argument (\"bad argument #1 to ...\" from inside it): its help says how.",
  the_feature = "The feature as written cannot pass: changing it needs the person's agreement again.",
  unclear = "It cannot be told from what is shown: read the failing file and line first.",
}

-- What each stage allows, in the order Jev is offered them.
M.allowed = {
  no_feature = { "write_feature", "read_help", "think", "blocked" },
  awaiting_agreement = { "wait_for_agreement", "write_feature", "think", "blocked" },
  building = { "undo", "write_feature", "write_steps", "write_code", "write_page", "run_test", "run_check", "fix_failure", "rewrite",
    "look_at_app", "read_help", "think", "plan", "next_part", "blocked" },
  ready = { "publish", "undo", "look_at_app", "fix_failure", "rewrite", "write_page", "run_test", "think", "blocked" },
  awaiting_yes = { "wait_for_yes" },
  shipped = { "answer_task", "think", "blocked" },
  answered = { "answer" },
}

-- What only one move may do (code owns the workflow): a call of another move that does it is not run. Mercury filling
-- look_at_app once also sent the DONE letter, and the run ended answered with nothing shipped.
M.only = {
  { what = "mail", move = "answer_task", cmd = "^%s*mail%s" },
  { what = "publish", move = "publish", cmd = "^%s*publish" },
  { what = "a feature", move = "write_feature", file = "features/[^/]*%.feature$", cmd = "^%s*new%s+feature" },
}

-- where an app's files may go: /home's own folders, never another app's or outside /home
local function misplaced(path)
  return string.find(path, "^apps/") or string.find(path, "^/home/apps/")
    or (string.find(path, "^/") and not string.find(path, "^/home/"))
end

-- why a call may not run in this move, or nil
function M.refused(verb, c)
  if string.find(c.cmd or "", "^%s*new%s+app") then return "the app is /home itself: new app makes another" end
  for path in pairs(c.files or {}) do
    if misplaced(path) then return ("%s is outside the app: it lives in /home (features/, code/, ui/, data/)"):format(path) end
  end
  for _, r in ipairs(M.only) do
    if verb ~= r.move then
      if string.find(c.cmd or "", r.cmd) then return ("%s belongs to the %s move"):format(r.what, r.move) end
      for path in pairs(r.file and c.files or {}) do
        if string.find(path, r.file) then return ("writing %s belongs to the %s move"):format(path, r.move) end
      end
    end
  end
end

-- the command that opens a page in the computer's browser: /house-plants/ is open app/house-plants
function M.open(path)
  local rest = string.gsub(string.gsub(path, "^/", ""), "/$", "")
  return rest == "" and "open app" or ("open app/" .. rest)
end

-- The moves that change the app: after one, it has to be used as the person will before it is published.
M.changes = { write_steps = true, write_code = true, write_page = true, fix_failure = true, rewrite = true }

M.waits = { wait_for_agreement = "the person's agreement to the feature", wait_for_yes = "the person's yes to publish" }

-- The stage from the facts, and why: code's judgement, never a model's.
--   facts = { features = { { path, stage } }, tests = { passed, total, failing = {}, undefined = {} } | nil,
--             empty_steps = n, pages = { { path, status } }, asked = bool, shipped = bool, answered = bool }
function M.stage(f)
  if f.answered then return "answered", "the task is answered DONE" end
  if f.shipped then return "shipped", "the app has shipped; the task is not answered yet" end
  if f.asked then return "awaiting_yes", "publishing waits for the person's yes" end
  if #f.features == 0 then return "no_feature", "there is no feature yet" end
  for _, ft in ipairs(f.features) do
    if ft.stage == "written" then return "awaiting_agreement", ft.path .. " is written and not agreed" end
  end
  local t, why = f.tests, {}
  if not t or t.total == 0 then why[#why + 1] = "no test has run since the last change" end
  if t and t.passed < t.total then why[#why + 1] = ("%d of %d scenarios pass"):format(t.passed, t.total) end
  if t and #t.undefined > 0 then why[#why + 1] = #t.undefined .. " steps have no definition" end
  if (f.empty_steps or 0) > 0 then why[#why + 1] = f.empty_steps .. " step definitions check nothing (an empty body)" end
  if #f.pages == 0 then why[#why + 1] = "the app has no page" end
  for _, p in ipairs(f.pages) do
    if p.status ~= 200 then why[#why + 1] = ("the page %s answers %d"):format(p.path, p.status) end
  end
  if #why > 0 then return "building", table.concat(why, "; ") end
  return "ready", "every scenario passes and every page answers"
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
  if now ~= "" and now == was then
    req.repeats = (req.repeats or 0) + 1
    out[#out + 1] = ("The same failure as before this step (%d changes running have left it): %s"):format(
      req.repeats, clip(now, 300))
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
  if verb == "publish" and c.cmd then c.cmd = c.cmd:gsub("^(%s*publish)%s+[%w_%-]+%s*$", "%1") end
  return c
end

-- whether stopping can be right: something fails, Mercury could not fill a move, fixing has stopped helping, or the
-- last step broke (a chores run, every scenario passing and publish offered, blocked saying nothing was missing)
function M.troubled(req, repeats)
  local last = req.steps[#req.steps]
  return M.failing(req.facts) ~= "" or M.unfilled(req) >= 1 or repeats >= M.repeats
    or (last ~= nil and last.outcome ~= "complete")
end

-- an answer_task step that did not come out complete
function M.answer_failed(req)
  for _, st in ipairs(req.steps) do
    if st.verb == "answer_task" and st.outcome ~= "complete" then return true end
  end
  return false
end

function M.facts_text(f, s)
  local stage, repeats = s.stage, s.repeats
  local out = { ("Stage: %s (%s)."):format(stage, s.why) }
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

function M.new(host, run)
  local w = { tools = {}, host = host, run = run }
  for name in pairs(M.moves) do
    if name ~= "answer" and name ~= "think" and name ~= "blocked" then w.tools[#w.tools + 1] = { name = name, what = M.moves[name] } end
  end
  table.sort(w.tools, function(a, b) return a.name < b.name end)

  -- the facts are read again before every decision, so what the person did between steps is seen
  local function facts(req)
    req.facts = host.facts()
    req.stage, req.why = M.stage(req.facts)
    return req.facts
  end

  function w.facts_text(req) return M.facts_text(req.facts, { stage = req.stage, why = req.why,
    repeats = req.repeats, looked = req.looked, unfilled = M.unfilled(req), regressed = req.undo and req.regressed }) end

  function w.question(a)
    local req = a.req
    facts(req)
    local last = req.steps[#req.steps]
    -- the same failure through M.repeats changes: fixing it again waits on thinking it through, and then one fix
    -- is offered; thinking does not wipe the count (a plants run went fix, think, fix, think thirty times over when
    -- it did); through M.dead_end, neither is offered, and through M.give_up only a rewrite, the feature or stopping
    local repeats = req.repeats or 0
    local stuck = repeats >= M.repeats and not (last and last.verb == "think" and repeats < M.dead_end)
    local last_resort = { rewrite = true, write_feature = true, blocked = true }
    local options = {}
    for _, name in ipairs(M.allowed[req.stage]) do
      -- and publishing waits on the app having been used as the person will since it last changed
      -- and thinking twice running changes nothing
      -- and once shipped, the task is answered: thinking or stopping is for after an answer that failed (a budget
      -- run, shipped, thought and then blocked twice saying it still waited on the person's yes)
      -- and an agreed feature is changed only once fixing the code has stopped helping (a countdown run blocked
      -- with no move that could change the feature it blamed)
      if not (stuck and name == "fix_failure") and not (name == "publish" and not req.looked)
        and not (name == "think" and last and last.verb == "think") and not (name == "undo" and not req.undo)
        and not (req.stage == "shipped" and name ~= "answer_task" and not M.answer_failed(req))
        and not (name == "write_feature" and req.stage == "building" and repeats < M.repeats)
        and not (repeats >= M.dead_end and (name == "fix_failure" or name == "think"))
        and not (repeats >= M.give_up and not last_resort[name])
        and not (name == "blocked" and not M.troubled(req, repeats)) then
        options[name] = M.moves[name] or require("agent.parts").verbs[name]
      end
    end
    if options.plan or options.next_part then
      options.plan, options.next_part = nil, nil
      require("agent.parts").options(a, options)
    end
    return { kind = "choice", options = options,
      text = "Which move should the agent make next on its computer to build what the task asks? Read the stage,"
        .. " the facts and the steps so far. Waiting is for when only the person can move it on." }
  end

  function w.state(a, req, for_jev) return prompt.state(a, req, for_jev, w.facts_text(req)) end

  -- whenever something is failing, where its cause lies, in the same call
  function w.questions(_, req)
    if M.failing(req.facts) == "" then req.cause = nil return {} end
    return { cause = { kind = "choice", options = M.causes,
      text = "Where does the cause of what is failing now lie? Read the failing lines, the files the steps so far"
        .. " wrote and their results." } }
  end

  -- the move Jev weighed second, which Mercury is told of when Jev was unsure; and the cause, when asked
  function w.answered(_, req, answers)
    local c = answers.cause
    req.cause = c and c.choice and { choice = c.choice, p = tonumber((c.probabilities or {})[c.choice]) } or nil
    local n, second, p2 = answers.next, nil, -1
    for v, p in pairs(n and n.probabilities or {}) do
      if v ~= n.choice and tonumber(p) and tonumber(p) > p2 then second, p2 = v, tonumber(p) end
    end
    req.second = second
  end

  function w.arbiter(a, req, first, second) return prompt.arbiter(a, req, first, second, M.moves) end
  function w.think(a, req) return prompt.think(a, req, M.moves) end
  function w.ask() error("the computer's agent asks the person through its task's letters, not a form") end
  w.form = w.ask

  function w.act(a, req, verb, step)
    if M.changes[verb] then req.looked = false end
    if M.waits[verb] then
      step.lines[1] = "waiting for " .. M.waits[verb]
      step.outcome = "complete"
      return { "wait", M.waits[verb] }
    end
    if verb == "blocked" then
      local missing = a:mercury(prompt.blocked(a, req, M.moves))
      if type(missing) ~= "string" or not missing:find("%S") then missing = "(Mercury could not say what is missing)" end
      step.note, step.outcome = "Blocked: " .. clip(missing, 600), "blocked"
      -- the first time, what is missing is guidance both minds read; a second blocked running ends the run
      req.guidance = "Blocked: " .. clip(missing, 600)
      local last = req.steps[#req.steps]
      if last and last.verb == "blocked" then return { "done", "blocked: " .. clip(missing, 600) } end
      return
    end
    if verb == "undo" then
      local kept = req.undo or {}
      req.undo, req.regressed = nil, nil
      for _, l in ipairs(undo.restore(host, kept)) do step.lines[#step.lines + 1] = l end
      local r = host.exec({ cmd = "test" })   -- the run that shows the files as they were pass again
      step.lines[#step.lines + 1] = ("$ test  -> %d\n%s"):format(r.code, clip(r.stdout or "", 1500))
      step.outcome = "complete"
      if req.facts then step.note = M.after(req, req.facts, host.facts()) end
      return
    end
    local calls, err = prompt.fill(a, req, verb, M.moves[verb], run, M.causes)
    if not calls then step.note, step.outcome = "Filling the move failed: " .. tostring(err), "broken" return end
    if #calls == 0 then step.note, step.outcome = "Mercury made no call for this move.", "no_effect" return end
    local kept = M.changes[verb] and undo.keep(host, calls) or nil
    local failed, used, typed, shown = 0, false, {}, ""
    for _, c in ipairs(calls) do
      -- every command runs in /home: a folder of the model's own was a guess (home became /home/home)
      M.tidy(verb, c)
      local no = M.refused(verb, c)
      local r = no and { code = 1, stdout = "", stderr = "not run: " .. no .. "\n" } or host.exec(c)
      if r.code ~= 0 then failed = failed + 1 end
      -- each command of a line (open app; type Name cereal; click Add; page): a submit or click is using the app,
      -- and what was typed is its last word (type "Plant name" "Pothos": Pothos); once used, what the page said
      for part in (c.cmd or ""):gmatch("[^;&|]+") do
        local word = part:match("^%s*(%a+)")
        if r.code == 0 and (word == "submit" or word == "click") then used = true end
        if word == "type" then typed[#typed + 1] = part:match("([%w%-]+)[\"']?%s*$") end
      end
      if used then shown = shown .. (r.stdout or "") end
      local files = {}
      for path in pairs(c.files or {}) do files[#files + 1] = path end
      table.sort(files)
      step.lines[#step.lines + 1] = ("$ %s  -> %d%s\n%s%s"):format(c.cmd, r.code,
        #files > 0 and ("  (wrote " .. table.concat(files, ", ") .. ")") or "",
        clip(r.stdout or "", 3000), (r.stderr or "") ~= "" and ("\nstderr: " .. clip(r.stderr, 1500)) or "")
    end
    step.outcome = failed == 0 and "complete" or "broken"
    -- looking is using: a look that only opened the page saw nothing of its form (a habits page whose form
    -- went nowhere shipped on a look that never submitted it)
    if verb == "look_at_app" and step.outcome == "complete" and not used then
      step.outcome = "no_effect"
      step.lines[#step.lines + 1] = "Only opened: using the app is typing in its form and submitting it (or clicking"
        .. " its button), then reading the page for what was added."
    end
    -- and using it shows what was typed: a page whose form went to an empty get.add showed nothing it was given
    if verb == "look_at_app" and step.outcome == "complete" and #typed > 0 then
      local seen = false
      for _, t in ipairs(typed) do seen = seen or shown:find(t, 1, true) ~= nil end
      if not seen then
        step.outcome = "broken"
        step.lines[#step.lines + 1] = ("Typed %s and sent it, but the page after shows none of it: the form keeps"
          .. " nothing. Read the page's form and the action it names."):format(table.concat(typed, ", "))
      end
    end
    if verb == "look_at_app" then req.looked = step.outcome == "complete" end
    if req.facts then
      local repeats, now = req.repeats or 0, host.facts()
      -- the stage Jev was shown, then where it placed the cause, then how the change left the work
      step.note = ("[%s: %s] "):format(req.stage, clip(req.why or "", 160))
        .. (req.cause and ("Cause placed in %s. "):format(req.cause.choice) or "")
        .. M.after(req, req.facts, now)
      -- only the last change can be undone, and only when it broke what passed
      req.undo = req.regressed and kept or nil
      -- publish answers 3 when it has asked the person: that is it done
      if verb == "publish" and (now.asked or now.shipped) then step.outcome = "complete" end
      -- a fix that left the failure as it was did nothing, whatever its commands said
      if verb == "fix_failure" and (req.repeats or 0) > repeats then step.outcome = "no_effect" end
    end
  end

  return w
end

return M
