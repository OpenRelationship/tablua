-- Mutation checks: is each test able to fail? Each mutation breaks one rule in the code (an exact edit, found once),
-- runs the tests, puts the file back, and says what the tests did:
--   RED       a test failed: the tests guard that rule
--   MISSED    the tests passed with the rule broken: nothing guards it
--   CRASHED   the command failed with no test failing (the edit broke the code's syntax, or the runner): this shows
--             nothing, and is never counted as red
-- The file is put back however the run ends.
--
--   luajit .robot/mutate.lua .robot/mutations/<suite>.lua ...
--   a suite returns { cmd = "the tests to run", dir? = "where, from this repo", { file, old, new, why }, ... }
--   exit 0 when every mutation is RED
local root = arg[0]:match("^(.*)/[^/]+$") or "."
local repo = root .. "/.."

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function write(path, s)
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
end

local function count(s, part)
  local n, at = 0, 1
  while true do
    local i, j = s:find(part, at, true)
    if not i then return n end
    n, at = n + 1, j + 1
  end
end

local function run(cmd, dir)
  local p = assert(io.popen(("cd '%s' && (%s) 2>&1; echo \"@rc $?\""):format(dir, cmd)))
  local out = p:read("*a")
  p:close()
  local body, rc = out:match("^(.-)@rc (%d+)%s*$")
  return body or out, tonumber(rc) or 1
end

local FAILED = { "not ok", "FAILED (failures", "FAILED (errors=0", "AssertionError" }

local bad, total = 0, 0
for _, suite_path in ipairs(arg) do
  local suite = dofile(suite_path)
  local dir = suite.dir and (suite.dir:find("^/") and suite.dir or repo .. "/" .. suite.dir) or repo
  print(suite_path)
  local base, rc0 = run(suite.cmd, dir)
  if rc0 ~= 0 then
    print("  the tests fail before any mutation, so no mutation can show anything:")
    print("  " .. base:sub(-300))
    os.exit(1)
  end
  for _, m in ipairs(suite) do
    total = total + 1
    local path = m[1]:find("^/") and m[1] or dir .. "/" .. m[1]
    local src = read(path)
    local n = count(src, m[2])
    local verdict, note
    if n ~= 1 then
      verdict, note = "CRASHED", ("the edit's text is found %d times in %s, not once"):format(n, m[1])
    else
      local i = src:find(m[2], 1, true)
      write(path, src:sub(1, i - 1) .. m[3] .. src:sub(i + #m[2]))
      local ok, out, rc = pcall(run, suite.cmd, dir)
      write(path, src)
      if not ok then
        verdict, note = "CRASHED", tostring(out)
      elseif rc == 0 then
        verdict = "MISSED"
      else
        local failed = false
        for _, f in ipairs(FAILED) do if out:find(f, 1, true) then failed = true end end
        verdict = failed and "RED" or "CRASHED"
        if not failed then note = (out:match("[^\n]*[Ee]rror[^\n]*") or out:sub(-160)):sub(1, 160) end
      end
    end
    if verdict ~= "RED" then bad = bad + 1 end
    print(("  %-8s %s"):format(verdict, m[4] or m[2]:sub(1, 60)))
    if note then print("           " .. note) end
  end
end
print(bad == 0 and ("all %d mutations red"):format(total) or ("%d of %d mutations not red"):format(bad, total))
os.exit(bad == 0 and 0 or 1)
