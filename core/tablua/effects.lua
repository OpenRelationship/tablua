-- The harness's own behaviour model (M2; owner, 2026-10-04): each step as Given / When / Then, written by
-- the harness from its telemetry, never by the agent's writer. Given is the state (tablua_state), When the move,
-- and Then the effects seen after it, keywords from a closed vocabulary in the manner of Robot Framework's: the
-- tests (a test turned green or red, its failing keyword fixed, the failure moved on or reached further into the
-- test, by the kind of keyword), the pages (one broke or was fixed), the commands (check passed or failed, a
-- command failed), the stage, and how the step was judged.
-- Each frequent effect is a head TabPFN predicts and Jev is asked of (t:training("effect:<Keyword>")), graded by
-- the next step's telemetry: dense labels no one has to write.
--
--   effects.compare(before, after, step, commands) -> { { keyword, arg } }
--     before, after: { tests = { passed, total, failing = { { test, path, keyword, why, reach } }, undefined } | nil,
--                      pages = { [path] = status }, stage }    (failing as robot.summary gives it)
--     step: { verb, outcome, regressed, same_failure }    commands: { { name, exit } }
--   effects.snapshot(facts, stage) -> a snapshot from the harness's facts (world/facts.lua)
--   effects.commands(lines) -> commands, from a step's "$ cmd  -> code" lines
--   effects.keyword_kind(name) -> open | type | press | press_for | see | see_for | see_before | not_see | own
--   effects.page_keywords        the page's keywords a host's computer gives every app, by their names
local M = {}

M.vocabulary = {
  ["Step Complete"] = "the step did its job", ["Step Broken"] = "the step left something broken",
  ["Step No Effect"] = "the step changed nothing", ["Step Blocked"] = "the agent said it was blocked",
  ["Regressed"] = "a test that passed fails now", ["Same Failure"] = "the same failure as before the step",
  ["Tests First Ran"] = "the tests ran for the first time", ["More Passing"] = "more tests pass",
  ["Fewer Passing"] = "fewer tests pass", ["All Green"] = "every test passes, and did not before",
  ["Test Turned Green"] = "a test passes now (arg: its name)",
  ["Test Turned Red"] = "a test fails now (arg: its name)",
  ["Keyword Fixed"] = "a failing test's failing keyword passes now (arg: the keyword's kind)",
  ["Failure Moved On"] = "a test still fails, at another keyword (arg: the new keyword's kind)",
  ["Same Keyword Failing"] = "a test fails at the same keyword for the same reason (arg: the keyword's kind)",
  ["Reached Further"] = "a failing test passed more keywords before failing than it did",
  ["Fell Back"] = "a failing test passed fewer keywords before failing than it did",
  ["Undefined Keywords"] = "calls no keyword answers", ["Page Broke"] = "a page answers 500 now (arg: its path)",
  ["Page Fixed"] = "a page answers 200 now (arg: its path)", ["Check Passed"] = "check found nothing wrong",
  ["Check Failed"] = "check found something wrong", ["Command Failed"] = "a command exited non-zero (arg: its name)",
  ["Stage Became"] = "the stage changed (arg: the new stage)", ["Published"] = "the app was published",
  ["Undone Next"] = "the next step undid this one",
}

-- the page's keywords, by kind: Open <path>; Type <field> <value>; Press <label>; Press For <label> <row>;
-- See <text>...; See For <text> <row>; See Before <first> <second>; Do Not See <text>
local PAGE = { ["open"] = "open", ["openpage"] = "open", ["goto"] = "open",
  ["type"] = "type", ["typeinto"] = "type", ["inputtext"] = "type",
  ["press"] = "press", ["click"] = "press", ["clickbutton"] = "press", ["pressfor"] = "press_for",
  ["see"] = "see", ["pageshouldcontain"] = "see", ["seefor"] = "see_for", ["seebefore"] = "see_before",
  ["donotsee"] = "not_see", ["pageshouldnotcontain"] = "not_see" }
M.page_keywords = { "Open", "Open Page", "Go To", "Type", "Type Into", "Input Text", "Press", "Click",
  "Click Button", "Press For", "See", "Page Should Contain", "See For", "See Before", "Do Not See",
  "Page Should Not Contain" }

local PREFIX = { given = true, ["when"] = true, ["then"] = true, ["and"] = true, but = true }

-- the kind of a keyword a test calls: one of the page's keywords, else the app's own
function M.keyword_kind(name)
  local s = tostring(name or "")
  local first, rest = s:match("^%s*(%a+)%s+(.+)$")
  if first and PREFIX[first:lower()] then s = rest end
  return PAGE[(s:lower():gsub("[%s_]", ""))] or "own"
end

-- a table's keys in order: pairs' order is not the same from run to run, and what is written from it must be
local function keys(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = k end
  table.sort(out)
  return out
end

local function title(s)
  return (tostring(s):gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

-- failing tests by name: where each failed, why, and how far it got
local function by_test(t)
  local out = {}
  for _, f in ipairs(t and t.failing or {}) do
    if not out[f.test or ""] then out[f.test or ""] = f end
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
    if (a.undefined or 0) > 0 then add("Undefined Keywords") end
    local was, now = by_test(b), by_test(a)
    for _, name in ipairs(keys(was)) do
      local f = was[name]
      if not now[name] and (a.total or 0) > 0 then
        add("Test Turned Green", name)
        add("Keyword Fixed", M.keyword_kind(f.keyword))
      elseif now[name] then
        local g = now[name]
        if g.path == f.path and g.keyword == f.keyword and g.why == f.why then
          add("Same Keyword Failing", M.keyword_kind(g.keyword))
        elseif g.path ~= f.path or g.keyword ~= f.keyword then
          add("Failure Moved On", M.keyword_kind(g.keyword))
        end
        if (g.reach or 0) > (f.reach or 0) then add("Reached Further")
        elseif (g.reach or 0) < (f.reach or 0) then add("Fell Back") end
      end
    end
    for _, name in ipairs(keys(now)) do
      if not was[name] and bt > 0 then add("Test Turned Red", name) end
    end
  end
  for _, path in ipairs(keys(after.pages)) do
    local status = after.pages[path]
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

-- a failing entry as the facts give it ("test: keyword: why") or as a test run reports it (robot.summary's)
local function failing(x)
  if type(x) == "table" then
    return { test = x.test or "", path = x.path or "", keyword = x.keyword or "", why = x.why or "",
      reach = tonumber(x.reach) or 0 }
  end
  local test, rest = tostring(x):match("^(.-): (.*)$")
  local kw, why = (rest or ""):match("^(.-): (.*)$")
  return { test = test or tostring(x), path = "", keyword = kw or rest or "", why = why or "", reach = 0 }
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

-- the command's own name: `cd '/home' && test tests/x.robot` is test
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
