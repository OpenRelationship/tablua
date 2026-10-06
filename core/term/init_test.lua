-- The terminal on this computer's own tmux, when it has one (the cases that need it say so and pass without it),
-- and the plain session through a fake exec.
local spec = require("spec")
local term = require("term")

-- the host's exec, as a test host gives it: the command through sh, stdout and stderr kept apart
local function exec(cmd)
  local err = os.tmpname()
  local f = io.popen("( " .. cmd .. "\n) 2>" .. err .. "; echo \"@code $?\"")
  local out = f:read("*a")
  f:close()
  local e = io.open(err) local stderr = e and e:read("*a") or "" if e then e:close() end
  os.remove(err)
  local body, code = out:match("^(.-)@code (%d+)\n?$")
  return { code = tonumber(code), stdout = body or out, stderr = stderr }
end

local has_tmux = exec("command -v tmux && command -v bash").code == 0

local function live(name, fn)
  spec.test(name, function()
    if not has_tmux then return end
    local s = term.new(exec, { now = function() local f = io.popen("date +%s.%N 2>/dev/null || date +%s") local v = tonumber(f:read("*l")) f:close() return v end })
    local ok, e = pcall(fn, s)
    exec("tmux -L " .. term.socket .. " kill-server")
    if not ok then error(e, 0) end
  end)
end

live("a command runs at the prompt and comes back done, with its exit code and the screen from the prompt on", function(s)
  spec.eq(s:open(), "tmux")
  spec.ok(s.prompt:find("[#$] $"), "the prompt " .. s.prompt)
  local r = s:send("echo hi; false\n", 10)
  spec.same({ r.done, r.exit }, { true, 1 })
  local lines = {}
  for l in (r.screen .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
  spec.eq(lines[1], s.prompt .. "echo hi; false")
  spec.eq(lines[2], "hi")
  spec.eq(lines[3], s.prompt:gsub(" $", ""))
end)

live("the session is one shell: a folder changed stays changed", function(s)
  s:send("cd /tmp && export TL_X=7\n", 10)
  local r = s:send("echo $TL_X; pwd\n", 10)
  spec.ok(r.screen:find("\n7\n", 1, true), r.screen)
  spec.ok(r.screen:find("/tmp", 1, true), r.screen)
end)

live("a command still running when the wait runs out is left running; an empty send waits for it, C-c stops it", function(s)
  local r = s:send("sleep 1; echo woke\n", 0.2)
  spec.same({ r.done, r.exit }, { false, nil })
  r = s:send("", 5)
  spec.same({ r.done, r.exit }, { true, 0 })
  spec.ok(r.screen:find("woke", 1, true), r.screen)
  s:send("sleep 30\n", 0.2)
  r = s:send("C-c", 5)
  spec.same({ r.done, r.exit }, { true, 130 })
end)

live("a fast command does not wait out its wait", function(s)
  local t0 = os.time()
  local r = s:send("true\n", 30)
  spec.ok(r.done and os.time() - t0 < 5, "it waited")
end)

spec.test("a plain session runs each command in the folder the last one left and writes the screen as tmux would", function()
  local calls = {}
  local fake = function(cmd)
    calls[#calls + 1] = cmd
    if cmd:find("command -v bash", 1, true) then return { code = 1 } end
    if cmd:find("id -un", 1, true) then return { code = 0, stdout = "root@box:/app\n" } end
    if cmd:find("make", 1, true) then return { code = 0, stdout = "built\n@tablua 2\n/app/src\n" } end
    return { code = 0, stdout = "\n@tablua 0\n/app\n" }
  end
  local s = term.new(fake)
  spec.eq(s:open(), "plain")
  spec.eq(s.prompt, "root@box:/app# ")
  local r = s:send("cd src && make\n", 10)
  spec.same({ r.done, r.exit, r.screen }, { true, 2, "root@box:/app# cd src && make\nbuilt\nroot@box:/app/src#" })
  spec.ok(calls[#calls]:find("cd '\\''/app'\\''", 1, true), calls[#calls])
  r = s:send("C-c", 1)
  spec.ok(r.note, "keys with no command are said to go nowhere")
end)

live("each action says how long it took, which files it wrote, and its raw bytes with their colours", function(s)
  local dir = os.tmpname() .. "_d"
  os.execute("mkdir -p " .. dir)
  s:send("cd " .. dir .. "\n", 10)
  local r = s:send("echo hi > a.txt; printf '\\033[31mred\\033[0m\\n'\n", 10)
  spec.ok(r.ms and r.ms > 0, "ms " .. tostring(r.ms))
  local found = false
  for _, f in ipairs(r.files) do if f.path:find("a.txt", 1, true) and f.size == 3 then found = true end end
  spec.ok(found, "a.txt among the files written")
  local p = require("term.pty").read(r.raw)
  spec.ok(p.red >= 1, "a red line in the raw bytes: " .. #r.raw .. " bytes")
  spec.ok(r.first_ms ~= nil, "it saw the first output")
  os.execute("rm -rf " .. dir)
end)

live("the first output is timed in milliseconds, not in polls of the prompt's wait", function(s)
  -- the old count of 50 ms polls could only say a multiple of 50: three times, at least one is not
  local seen, off = {}, false
  for _ = 1, 3 do
    local r = s:send("sleep 0.13; echo late\n", 10)
    seen[#seen + 1] = tostring(r.first_ms)
    spec.ok(r.first_ms and r.first_ms >= 125 and r.first_ms < 300, "first_ms " .. tostring(r.first_ms))
    if r.first_ms % 50 ~= 0 then off = true end
  end
  spec.ok(off, "every first_ms a multiple of 50: " .. table.concat(seen, ", "))
  local q = s:send("echo soon\n", 10)
  spec.ok(q.first_ms and q.first_ms < 250, "first_ms " .. tostring(q.first_ms))
end)

live("the trace is every command bash ran for the keys, as bash read them, its exit codes left alone", function(s)
  local r = s:send("cd /tmp && ls | wc -l; false\n", 10)
  spec.same(r.trace, { "cd /tmp", "ls", "wc -l", "false" })
  spec.eq(r.exit, 1)
end)

spec.run()
