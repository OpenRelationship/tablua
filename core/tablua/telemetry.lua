-- The behaviour model from the log : a run's log events, keyword rows in the manner of Robot
-- Framework's, cut into one window per step (from Decide <todo>/step/<n> to its Outcome) and turned into each
-- step's effects (tablua.effects): every test file's latest run (Outcome <file>.robot red|green {json}, the json
-- robot.summary's), every page
-- served (Serve Request), every command (Run Command) and the stage at each decision. Reads the log, so it runs
-- where the whole file is open (an eval's tools, a desktop host), never in the agent's harness, which reaches only
-- Tablua's tables; the harness records the same effects from its facts as it goes (in the host's world).
--
--   telemetry.windows(db, todo) -> { [n] = { { keyword, args } } }
--   telemetry.derive(t, todo) -> steps given effects (steps already given them are left as they are)
local json = require("ports.json")
local effects = require("tablua.effects")

local M = {}

function M.windows(db, todo)
  local rows = db:exec([[select e.seq, e.keyword, a.pos, a.value from events e left join args a on a.seq = e.seq
    order by e.seq, a.pos]])
  local events, last = {}, nil
  for _, r in ipairs(rows) do
    if not last or last.seq ~= r.seq then last = { seq = r.seq, keyword = r.keyword, args = {} }; events[#events + 1] = last end
    if r.pos then last.args[tonumber(r.pos)] = r.value end
  end
  local out, n = {}, nil
  local prefix = todo .. "/step/"
  for _, e in ipairs(events) do
    local a1 = e.args[1] or ""
    if e.keyword == "Decide" and a1:sub(1, #prefix) == prefix then
      n = tonumber(a1:sub(#prefix + 1)); out[n] = {}
    elseif n then
      out[n][#out[n] + 1] = e
      if e.keyword == "Outcome" and a1 == prefix .. n then n = nil end
    end
  end
  return out
end

local function merged(suites)
  local t, any = { passed = 0, total = 0, undefined = 0, failing = {} }, false
  local paths = {}
  for p in pairs(suites) do paths[#paths + 1] = p end
  table.sort(paths)
  for _, p in ipairs(paths) do
    local r = suites[p]
    any = true
    t.passed, t.total = t.passed + (r.passed or 0), t.total + (r.total or 0)
    t.undefined = t.undefined + #(r.undefined or {})
    for _, f in ipairs(r.failing or {}) do t.failing[#t.failing + 1] = effects.failing(f) end
  end
  return any and t or nil
end

function M.derive(t, todo)
  local db = t.db
  local done = {}
  for _, r in ipairs(db:exec("select distinct n from tablua_effect where todo = ?", { todo })) do done[r.n] = true end
  local stage, step = {}, {}
  for _, r in ipairs(db:exec("select n, stage from tablua_state where todo = ?", { todo })) do stage[r.n] = r.stage end
  for _, r in ipairs(db:exec("select n, verb, outcome, regressed, same_failure from tablua_outcome where todo = ?",
    { todo })) do step[r.n] = r end
  local windows = M.windows(db, todo)
  local ns = {}
  for n in pairs(windows) do ns[#ns + 1] = n end
  table.sort(ns)
  local suites, pages, given = {}, {}, 0
  local function snap(st)
    local p = {}
    for k, v in pairs(pages) do p[k] = v end
    return { tests = merged(suites), pages = p, stage = st }
  end
  for _, n in ipairs(ns) do
    local before, commands = snap(stage[n]), {}
    for _, e in ipairs(windows[n]) do
      local a = e.args
      if e.keyword == "Outcome" and (a[1] or ""):match("%.robot$") and (a[3] or ""):sub(1, 1) == "{" then
        local ok, r = pcall(json.decode, a[3])
        if ok and type(r) == "table" then suites[a[1]] = r end
      elseif e.keyword == "Serve Request" and a[1] == "GET" then
        pages[a[2] or "/"] = tonumber(a[3])
      elseif e.keyword == "Run Command" then
        commands[#commands + 1] = { name = effects.name(a[1]), exit = tonumber(a[3]) }
      end
    end
    local s = step[n]
    if s and not done[n] then
      local list = effects.compare(before, snap(stage[n + 1]), { verb = s.verb, outcome = s.outcome,
        regressed = s.regressed == 1, same_failure = s.same_failure == 1 }, commands)
      if step[n + 1] and step[n + 1].verb == "undo" then list[#list + 1] = { keyword = "Undone Next", arg = "" } end
      t:effects(todo, n, list)
      given = given + 1
    end
  end
  return given
end

return M
