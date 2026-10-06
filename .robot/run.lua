-- Runs our claims and keeps the record (README.md says how to use them).
--
--   luajit .robot/run.lua [word ...]           every claims/*.robot, or those whose path holds a word
--   luajit .robot/run.lua fetch label [job]    a bench job's trials from the box: sheets to runs/, rows to trial
--   luajit .robot/run.lua refresh label [job]  fetch, rebuild the decider history and the step labels, run every claim
--   luajit .robot/run.lua invalid todo n why   mark a run whose verdicts cannot be trusted, saying why
--   luajit .robot/run.lua history              every claim's verdicts, run by run
--   luajit .robot/run.lua reds [word ...]      each red proof, run now: where it fails, and whether that is at an
--                                              assertion (the only red that shows a check can fail); records nothing
--
-- Each claims file's run is kept in ledger.sqlite: its keyword trees (tablua_result: todo is the file, n the run),
-- its verdicts (claim) and whether it counts (claims_run: a draft when the file was not committed as it ran).
local root = arg[0]:match("^(.*)/[^/]+$") or "."
package.path = root .. "/?.lua;" .. root .. "/../core/?.lua;" .. root .. "/../core/?/init.lua;" .. package.path

local robot = require("robot")
local tablua = require("tablua")
local sqlite = require("ports.sqlite")
local keywords = require("keywords")
local ledger = require("ledger")

local t = tablua.open(sqlite.open(root .. "/ledger.sqlite"))
ledger.open(t.db)

-- a command's output and exit code (read from the output: not every Lua VM's popen gives the code)
local function sh(cmd)
  local p = assert(io.popen(cmd .. '; echo "@rc $?"'))
  local s = p:read("*a")
  p:close()
  local out, code = s:match("^(.-)@rc (%d+)%s*$")
  return out or s, tonumber(code) or 1
end

local cmd = arg[1]

local refresh = cmd == "refresh"
if cmd == "fetch" or refresh then
  local got = require("fetch").job(root, t.db, assert(arg[2], cmd .. " needs a label"), arg[3])
  for _, g in ipairs(got) do
    print(("%s  reward=%s green=%s steps=%s  %s"):format(g.task, tostring(g.reward), tostring(g.green),
      tostring(g.steps), g.sheet))
  end
  print(#got .. " trials")
  if not refresh then return end
  require("fetch").derived(root)
  print("rebuilt the decider history and the step labels")
  arg = {}
elseif cmd == "invalid" then
  ledger.invalid(t.db, assert(arg[2], "invalid needs a claims file"), tonumber(arg[3]), assert(arg[4], "say why"))
  print(("%s run %s marked invalid"):format(arg[2], arg[3]))
  return
elseif cmd == "history" then
  for _, r in ipairs(ledger.history(t.db)) do print(("%-18s %-58s %s"):format(r.todo, r.name, r.runs)) end
  print("(draft): run with the file uncommitted   (invalid): marked untrustworthy   !: edited after a kill")
  local c = ledger.calibration(t.db)
  local parts = {}
  for k, b in pairs(c.by) do parts[#parts + 1] = ("%s %d of %d"):format(k, b.right, b.n) end
  table.sort(parts)
  print(("predictions: %d of %d right (%s)"):format(c.right, c.predicted, table.concat(parts, ", ")))
  if c.optimism then print(("  optimism %+.2f: how often we said holds, less how often it held"):format(c.optimism)) end
  if c.brier then
    print(("  over %d with a p: Brier %.3f, log loss %.3f (a coin scores 0.250 and 0.693), overconfidence %+.2f")
      :format(c.scored, c.brier, c.log_loss, c.overconfidence))
  end
  for _, r in ipairs(t.db:exec("select todo, n, why from claims_run where invalid = 1 order by todo, n")) do
    print(("%s run %d is invalid: %s"):format(r.todo, r.n, r.why))
  end
  return
end

-- the claims file as committed: its commit, and whether the file on disk is that commit's
local function lock(path)
  local rel = path:sub(#root + 2)
  local dir = root
  local id = sh(("git -C '%s' log -1 --format=%%h -- '%s' 2>/dev/null"):format(dir, rel)):gsub("%s+", "")
  local _, changed = sh(("git -C '%s' diff --quiet HEAD -- '%s' 2>/dev/null"):format(dir, rel))
  local tracked = sh(("git -C '%s' ls-files -- '%s'"):format(dir, rel)) ~= ""
  return id, (id == "" or not tracked or changed ~= 0)
end

local function deepest(node)
  for _, c in ipairs(node.children or node.body or {}) do if c.status == "FAIL" then return deepest(c) end end
  return node
end

local files = {}
local p = io.popen('ls "' .. root .. '"/claims/*.robot 2>/dev/null')
for path in p:lines() do
  local want = #arg == 0 or (#arg == 1 and arg[1] == "reds")
  for k, w in ipairs(arg) do if not (k == 1 and w == "reds") and path:find(w, 1, true) then want = true end end
  if want then files[#files + 1] = path end
end
p:close()

local lib = keywords.library(root)

if cmd == "reds" then
  local bad = 0
  for _, path in ipairs(files) do
    local f = assert(io.open(path))
    local res = robot.run(robot.parse(f:read("*a")), { libraries = { lib } })
    f:close()
    print(path:match("(claims/.*)%.robot$"))
    for _, t in ipairs(res.tests) do
      if t.name:find(" %(red%)$") then
        local ok = t.status == "FAIL" and ledger.assertion(t)
        if not ok then bad = bad + 1 end
        print(("  %s  %-62s fails at %s"):format(ok and "red " or "BAD ", t.name,
          t.status == "FAIL" and tostring(deepest(t).name) or ("nothing: " .. t.status)))
        if not ok and t.message then print("        " .. t.message:gsub("\n", " "):sub(1, 140)) end
      end
    end
  end
  print(bad == 0 and "every red proof fails at an assertion" or (bad .. " red proofs show nothing"))
  os.exit(bad == 0 and 0 or 1)
end
local MARK = { holds = "holds   ", KILLED = "KILLED  ", broken = "BROKEN  ", BLIND = "BLIND   ", unproven = "unproven",
  unknown = "unknown " }
local totals = {}

for _, path in ipairs(files) do
  local f = assert(io.open(path))
  local text = f:read("*a")
  f:close()
  local todo = path:match("(claims/.*)%.robot$")
  local commit, draft = lock(path)
  local res = robot.run(robot.parse(text), { libraries = { lib }, clock = os.clock })
  local n = (t.db:exec("select coalesce(max(n), 0) + 1 as n from claims_run where todo = ?", { todo })[1]).n
  t:results(todo, n, res, todo)
  local verdicts = ledger.verdicts(res)
  local flags = ledger.record(t.db, todo, n, commit, draft, verdicts, ledger.hashes(text))
  print(("%s  run %d  %s"):format(todo, n, draft and "DRAFT: the file is not committed as it ran, so this run does not count"
    or ("locked at " .. commit)))
  for _, v in ipairs(verdicts) do
    totals[v.verdict] = (totals[v.verdict] or 0) + 1
    print(("  %s  %-58s %s"):format(MARK[v.verdict], v.name, table.concat(v.tags, " ")))
    if v.verdict ~= "holds" then print("            " .. (v.message ~= "" and v.message or ("red proof: " .. v.red))
      :gsub("\n", " "):sub(1, 150)) end
    if v.predict ~= "" then
      print(("            predicted %s%s: %s"):format(v.predict, v.p and ("@" .. v.p) or "",
        v.predict == v.verdict and "right" or (v.verdict == "unknown" and "pending, not measured yet") or "WRONG"))
    end
    if flags[v.name] then print("            ! " .. flags[v.name]) end
  end
end
print(("%d hold, %d killed, %d broken, %d blind, %d unproven, %d unknown"):format(totals.holds or 0,
  totals.KILLED or 0, totals.broken or 0, totals.BLIND or 0, totals.unproven or 0, totals.unknown or 0))
