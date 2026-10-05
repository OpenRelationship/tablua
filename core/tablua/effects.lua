-- The harness's own behaviour model (M2; owner, 2026-10-04): each step as Given / When / Then, written by
-- the harness from its telemetry, never by the agent's writer. Given is the state (tablua_state), When the move,
-- and Then the effects seen after it, keywords from a closed vocabulary in the manner of Robot Framework's: the
-- tests (a scenario turned green or red, a Gherkin line fixed, by the kind of line it is), the pages (one broke or
-- was fixed), the commands (check passed or failed, a command failed), the stage, and how the step was judged.
-- Each frequent effect is a head TabPFN predicts and Jev is asked of (t:training("effect:<Keyword>")), graded by
-- the next step's telemetry: dense labels no one has to write.
--
--   effects.compare(before, after, step, commands) -> { { keyword, arg } }
--     before, after: { tests = { passed, total, failing = { { scenario, step, why } }, undefined } | nil,
--                      pages = { [path] = status }, stage }
--     step: { verb, outcome, regressed, same_failure }    commands: { { name, exit } }
--   effects.snapshot(facts, stage) -> a snapshot from the harness's facts (world/facts.lua)
--   effects.commands(lines) -> commands, from a step's "$ cmd  -> code" lines
--   effects.line_kind(text) -> open | type | press | press_for | see | see_for | see_before | not_see | own
local M = {}

M.vocabulary = {
  ["Step Complete"] = "the step did its job", ["Step Broken"] = "the step left something broken",
  ["Step No Effect"] = "the step changed nothing", ["Step Blocked"] = "the agent said it was blocked",
  ["Regressed"] = "a scenario that passed fails now", ["Same Failure"] = "the same failure as before the step",
  ["Tests First Ran"] = "the features ran for the first time", ["More Passing"] = "more scenarios pass",
  ["Fewer Passing"] = "fewer scenarios pass", ["All Green"] = "every scenario passes, and did not before",
  ["Scenario Turned Green"] = "a scenario passes now (arg: its name)",
  ["Scenario Turned Red"] = "a scenario fails now (arg: its name)",
  ["Line Fixed"] = "a failing scenario's failing line passes now (arg: the line's kind)",
  ["Failure Moved On"] = "a scenario still fails, at a later line (arg: the new line's kind)",
  ["Same Line Failing"] = "a scenario fails at the same line for the same reason (arg: the line's kind)",
  ["Undefined Steps"] = "lines no step matches", ["Page Broke"] = "a page answers 500 now (arg: its path)",
  ["Page Fixed"] = "a page answers 200 now (arg: its path)", ["Check Passed"] = "check found nothing wrong",
  ["Check Failed"] = "check found something wrong", ["Command Failed"] = "a command exited non-zero (arg: its name)",
  ["Stage Became"] = "the stage changed (arg: the new stage)", ["Published"] = "the app was published",
  ["Undone Next"] = "the next step undid this one",
}

-- the kind of a Gherkin line, by the page's own step shapes (sdk/browse.lua), else the app's own
function M.line_kind(text)
  local s = tostring(text or ""):gsub("^%s*%a+%s+", "", 1)
  if s:match("^I open") then return "open" end
  if s:match("^I type") then return "type" end
  if s:match("^I press .- for ") then return "press_for" end
  if s:match("^I press") then return "press" end
  if s:match("^I do not see") then return "not_see" end
  if s:match("^I see .- before ") then return "see_before" end
  if s:match("^I see .- for ") then return "see_for" end
  if s:match("^I see") then return "see" end
  return "own"
end

local function title(s)
  return (tostring(s):gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

-- failing scenarios by name: the first failing line and why
local function by_scenario(t)
  local out = {}
  for _, f in ipairs(t and t.failing or {}) do
    if not out[f.scenario or ""] then out[f.scenario or ""] = f end
  end
  return out
end

function M.compare(before, after, step, commands)
  before, after, step = before or {}, after or {}, step or {}
  local out, seen = {}, {}
  local function add(k, arg)
    arg = arg or ""
    if not seen[k .. "\0" .. arg] then seen[k .. "\0" .. arg] = true; out[#out + 1] = { keyword = k, arg = arg } end
  end
  if step.outcome and step.outcome ~= "" then
    local k = "Step " .. title(step.outcome)
    if M.vocabulary[k] then add(k) end
  end
  if step.regressed then add("Regressed") end
  if step.same_failure then add("Same Failure") end
  if step.verb == "publish" and step.outcome == "complete" then add("Published") end
  local b, a = before.tests, after.tests
  if a then
    local bp, bt = b and b.passed or 0, b and b.total or 0
    if not b then add("Tests First Ran") end
    if (a.passed or 0) > bp then add("More Passing") elseif (a.passed or 0) < bp then add("Fewer Passing") end
    if (a.total or 0) > 0 and a.passed == a.total and not (bt > 0 and bp == bt) then add("All Green") end
    if (a.undefined or 0) > 0 then add("Undefined Steps") end
    local was, now = by_scenario(b), by_scenario(a)
    for name, f in pairs(was) do
      if not now[name] and (a.total or 0) > 0 then
        add("Scenario Turned Green", name)
        add("Line Fixed", M.line_kind(f.step))
      elseif now[name] then
        local g = now[name]
        if g.step == f.step and g.why == f.why then add("Same Line Failing", M.line_kind(g.step))
        elseif g.step ~= f.step then add("Failure Moved On", M.line_kind(g.step)) end
      end
    end
    for name in pairs(now) do
      if not was[name] and bt > 0 then add("Scenario Turned Red", name) end
    end
  end
  for path, status in pairs(after.pages or {}) do
    local was = (before.pages or {})[path]
    if status >= 500 and was ~= status then add("Page Broke", path)
    elseif status == 200 and was and was ~= 200 then add("Page Fixed", path) end
  end
  for _, c in ipairs(commands or {}) do
    if c.name == "check" then add(c.exit == 0 and "Check Passed" or "Check Failed")
    elseif c.exit ~= 0 then add("Command Failed", c.name) end
  end
  if after.stage and before.stage and after.stage ~= before.stage then add("Stage Became", after.stage) end
  return out
end

-- a failing entry as the facts give it ("scenario: step: why") or as a test run reports it ({ scenario, step, why })
local function failing(x)
  if type(x) == "table" then return { scenario = x.scenario or "", step = x.step or "", why = x.why or "" } end
  local scenario, rest = tostring(x):match("^(.-): (.*)$")
  local stepl, why = (rest or ""):match("^(.-): (.*)$")
  return { scenario = scenario or tostring(x), step = stepl or rest or "", why = why or "" }
end

function M.snapshot(facts, stage)
  local s = { stage = stage, pages = {} }
  local t = facts and facts.tests
  if t then
    s.tests = { passed = t.passed or 0, total = t.total or 0, undefined = #(t.undefined or {}), failing = {} }
    for i, x in ipairs(t.failing or {}) do s.tests.failing[i] = failing(x) end
  end
  for _, p in ipairs(facts and facts.pages or {}) do s.pages[p.path] = tonumber(p.status) end
  return s
end

-- the command's own name: `cd '/home' && test features/x.feature` is test
function M.name(cmd)
  local c = tostring(cmd or ""):gsub("^%s*cd%s+%S+%s*&&%s*", "")
  return c:match("^%s*([%w_%-%.]+)") or ""
end

function M.commands(lines)
  local out = {}
  for _, l in ipairs(lines or {}) do
    local cmd, code = tostring(l):match("^%$ (.-)  %-> (%-?%d+)")
    if cmd then out[#out + 1] = { name = M.name(cmd), exit = tonumber(code) } end
  end
  return out
end

M.failing = failing
return M
