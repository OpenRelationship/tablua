-- A bench job's trials, from the box to runs/: each trial's sheet (its tablua.db), and in the ledger a trial row:
-- the task, a label naming what the run tried (the arm, for claims comparing arms), Harbor's reward, whether the
-- agent's own suite went green (some run of it passed every test), how many steps it took.
--
--   local fetch = require("fetch")
--   fetch.job(root, db, label, job?) -> { { trial, task, reward, green, steps }, ... }   job: the latest by default
--   fetch.derived(root)   the sheets built from every run: the decider history (tl.history, on the box: it replays
--                         TabICL there) and the step labels (tl.labels, here, from the ledger's trials)
--   A copy that comes back empty is an error, never a sheet: an empty file once read as a sheet with no tables
--   TABLUA_BOX (cuda-box-cable) is the ssh host; TABLUA_BOX_JOBS (/home/shane/tb/jobs) where Harbor keeps jobs,
--   read through wsl
local json = require("ports.json")
local sqlite = require("ports.sqlite")

local M = {}

M.host = os.getenv("TABLUA_BOX") or "cuda-box-cable"
M.jobs = os.getenv("TABLUA_BOX_JOBS") or "/home/shane/tb/jobs"
M.python = os.getenv("TABLUA_BOX_PYTHON") or "/home/shane/tl-venv12/bin/python"
M.locals = (os.getenv("TABLUA_LOCAL") or (os.getenv("HOME") .. "/tablua-local"))

local function remote(args, out)
  local cmd = ('ssh %s "wsl -e %s"'):format(M.host, args)
  if out then return os.execute(cmd .. " > '" .. out .. "'") end
  local p = assert(io.popen(cmd))
  local s = p:read("*a")
  p:close()
  return s
end

local function size(path)
  local f = io.open(path, "rb")
  if not f then return 0 end
  local n = f:seek("end")
  f:close()
  return n
end

-- a file from the box, refused when it comes back empty
function M.copy(from, to)
  remote("cat " .. from, to)
  if size(to) == 0 then
    os.remove(to)
    error("nothing came back from " .. M.host .. ":" .. from, 0)
  end
end

local function lines(s)
  local out = {}
  for l in s:gmatch("[^\r\n]+") do out[#out + 1] = l end
  return out
end

function M.job(root, db, label, job)
  job = job or lines(remote("ls -1t " .. M.jobs))[1]
  assert(job and job ~= "", "no job on " .. M.host)
  local got = {}
  for _, trial in ipairs(lines(remote(("ls -1 %s/%s"):format(M.jobs, job)))) do
    local dir = ("%s/%s/%s"):format(M.jobs, job, trial)
    local result = trial:find("__") and remote("cat " .. dir .. "/result.json") or ""
    if result:find("{", 1, true) then
      local ok, r = pcall(json.decode, result)
      r = ok and r or {}
      local reward = r.verifier_result and r.verifier_result.rewards and r.verifier_result.rewards.reward
      local sheet = ("runs/%s__%s.sqlite"):format(job, trial)
      M.copy(dir .. "/agent/tablua.db", root .. "/" .. sheet)
      local green, steps
      local okdb, s = pcall(sqlite.open, root .. "/" .. sheet)
      if okdb then
        -- green from the suite's own runs (tablua_result): the terminal's passed column is the count before a step's
        -- last validation, so a run whose last check went 2 of 2 read as never green (UxH3BwD, 2026-10-06)
        local okq, g = pcall(s.exec, s, "select (select coalesce(max(ok), 0) from (select min(status = 'PASS') as ok"
          .. " from tablua_result where type = 'test' group by n, run)) as g, (select max(n) from tablua_term where"
          .. " source = 'real') as steps")
        if okq and g[1] then green, steps = g[1].g, g[1].steps end
      end
      local task = trial:match("^(.-)__") or trial
      db:exec("insert or replace into trial (job, trial, task, label, reward, green, steps, sheet, at) values"
        .. " (?, ?, ?, ?, ?, ?, ?, ?, ?)", { job, trial, task, label, reward or false, green or false, steps or false,
        sheet, os.date("!%Y-%m-%dT%H:%M:%SZ") })
      got[#got + 1] = { trial = trial, task = task, reward = reward, green = green, steps = steps, sheet = sheet }
    end
  end
  return got
end

function M.derived(root)
  -- absolute: the labels are built from tablua-local, where a relative root (".robot") names nothing
  if not root:find("^/") then
    local p = assert(io.popen("pwd"))
    root = p:read("*l") .. "/" .. root
    p:close()
  end
  local hist = "/home/shane/tb/decider-history.sqlite"
  -- the script goes on stdin (tablua-local/bin/box): Windows' ssh reads single quotes and 2>/dev/null its own way
  local p = assert(io.popen(("'%s/bin/box' -l > /dev/null 2>&1"):format(M.locals), "w"))
  p:write(("cd ~/tablua-local && %s -m tl.history --out %s\n"):format(M.python, hist))
  p:close()
  M.copy(hist, root .. "/runs/decider-history.sqlite")
  local ok = os.execute(("cd '%s' && python3 -m tl.labels '%s/ledger.sqlite' '%s/runs/decider-history.sqlite'"
    .. " '%s/runs/labels.sqlite' >/dev/null"):format(M.locals, root, root, root))
  if size(root .. "/runs/labels.sqlite") == 0 or not ok then error("the step labels were not built", 0) end
end

return M
