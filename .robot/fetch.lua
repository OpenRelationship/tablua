-- A bench job's trials, from the box to runs/: each trial's sheet (its tablua.db), and in the ledger a trial row:
-- the task, a label naming what the run tried (the arm, for claims comparing arms), Harbor's reward, whether the
-- agent's own suite went green (a real action ran with every test passing), how many steps it took.
--
--   local fetch = require("fetch")
--   fetch.job(root, db, label, job?) -> { { trial, task, reward, green, steps }, ... }   job: the latest by default
--   TABLUA_BOX (cuda-box-cable) is the ssh host; TABLUA_BOX_JOBS (/home/shane/tb/jobs) where Harbor keeps jobs,
--   read through wsl
local json = require("ports.json")
local sqlite = require("ports.sqlite")

local M = {}

M.host = os.getenv("TABLUA_BOX") or "cuda-box-cable"
M.jobs = os.getenv("TABLUA_BOX_JOBS") or "/home/shane/tb/jobs"

local function remote(args, out)
  local cmd = ('ssh %s "wsl -e %s"'):format(M.host, args)
  if out then return os.execute(cmd .. " > '" .. out .. "'") end
  local p = assert(io.popen(cmd))
  local s = p:read("*a")
  p:close()
  return s
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
      remote("cat " .. dir .. "/agent/tablua.db", root .. "/" .. sheet)
      local green, steps
      local okdb, s = pcall(sqlite.open, root .. "/" .. sheet)
      if okdb then
        local okq, g = pcall(s.exec, s, "select max(case when total > 0 and passed = total then 1 else 0 end) as g,"
          .. " max(n) as steps from tablua_term where source = 'real'")
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

return M
