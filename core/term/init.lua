-- The terminal: one shell session on the agent's computer, driven as a person drives one, keystrokes then a wait,
-- and read back as its screen. It is what a language world model of a terminal (Qwen-AgentWorld, term.turns) was
-- trained on, so what the agent did and what the world model foresaw are the same kind of thing, and both become
-- rows (tablua.term). The session is tmux on its own socket, reached only through the host's exec; a computer with
-- no tmux and no way to install it gets a plain session (each command a bounded bash, its folder kept), whose screen
-- is written as tmux's would be.
--
--   local term = require("term")
--   local s = term.new(exec, { history?, poll?, width?, height?, limit?, now? })
--                          exec(cmd, timeout) -> { code, stdout, stderr }, the host's command on the computer
--   s:open() -> mode       "tmux" or "plain"; sends nothing to the computer until called
--   s:send(keys, wait) -> { keys, wait, screen, exit, done, ms, first_ms, files, raw, trace }
--       keys: raw keystrokes, tmux's: "ls -la\n" runs a command, "C-c" interrupts, "" only waits
--       wait: seconds at most; it returns as soon as a command it ran is back at the prompt (done), else after
--       wait with the command still running (done false, exit nil) and the session left as it is
--       screen: from the prompt the keys were typed at to the end of the output: the command's echo, its output
--       and the next prompt, as a terminal shows it
--       ms: how long it took (with opts.now, the host's clock in seconds); first_ms: until its first output
--       files: { { path, size }, ... } the files written while it ran, under its folder, /app, /tmp and /root
--       raw: the bytes the terminal was sent while it ran (tmux's pipe-pane), colours and redraws kept (term.pty)
--       trace: { command, ... } every simple command bash itself ran for the keys, in order, as its DEBUG trap saw
--       it (each side of a pipe, each part of a chain, a newline in one read as a space): what was typed, as the
--       shell read it rather than as term.command parses it
--   s:screen() -> the visible screen      s.prompt   the prompt as the session shows it ("root@box:/app# ")
local M = {}

M.socket = "tablua"
M.session = "tablua"
M.dir = "/tmp/.tablua-term"
M.wait = 120          -- seconds a command may run before control comes back, when no wait is given
M.limit = 1800        -- the longest wait
M.poll = 0.05         -- seconds between looks at whether the prompt is back
M.first_poll = 0.005  -- seconds between looks until the first output has come
M.raw_bytes = 524288  -- of an action's raw bytes, the first this many are kept
M.files = 200         -- files written, at most this many listed
M.trace = 500         -- commands traced, at most this many kept

local function q(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
M.q = q

local function trim_end(s) return (tostring(s or ""):gsub("[ \t]+\n", "\n"):gsub("%s+$", "")) end

local S = {}
S.__index = S

function M.new(exec, opts)
  opts = opts or {}
  assert(type(exec) == "function", "term needs the host's exec")
  return setmetatable({ exec = exec, history = opts.history or 100000, poll = opts.poll or M.poll,
    width = opts.width or 200, height = opts.height or 50, limit = opts.limit or M.limit, now = opts.now }, S)
end

function S:run(cmd, timeout)
  local r = self.exec(cmd, timeout or 60) or {}
  r.code = tonumber(r.code) or 1
  return r
end

local function tmux(rest) return ("tmux -L %s %s"):format(M.socket, rest) end

-- installs tmux when the computer has a package manager and no tmux
local INSTALL = table.concat({
  "command -v tmux >/dev/null 2>&1 && exit 0",
  "export DEBIAN_FRONTEND=noninteractive",
  "if command -v apt-get >/dev/null 2>&1; then (apt-get install -y -qq tmux || (apt-get update -qq && apt-get install -y -qq tmux)) >/dev/null 2>&1",
  "elif command -v apk >/dev/null 2>&1; then apk add -q tmux >/dev/null 2>&1",
  "elif command -v dnf >/dev/null 2>&1; then dnf install -y -q tmux >/dev/null 2>&1",
  "elif command -v yum >/dev/null 2>&1; then yum install -y -q tmux >/dev/null 2>&1; fi",
  "command -v tmux >/dev/null 2>&1",
}, "\n")

-- the shell's prompt and, before each prompt, the count of commands done and the last one's exit code, kept in a
-- file the session's wait reads; and before each command bash runs, the command, in a trace file (its DEBUG trap,
-- which leaves the exit code as it was and skips its own prompt work); the leading space keeps the line out of the
-- shell's history
local function setup(dir)
  return " __tl_t() { case $BASH_COMMAND in *__tl_*) ;; *) printf '%s\\n' \"${BASH_COMMAND//$'\\n'/ }\" >> "
    .. dir .. "/trace;; esac; }; trap __tl_t DEBUG;"
    .. " bind 'set enable-bracketed-paste off' 2>/dev/null; export PS1='\\u@\\h:\\w\\$ '"
    .. " HISTCONTROL=ignorespace TERM=xterm-256color PROMPT_COMMAND='__tl_s=$?; "
    .. "__tl_n=$((__tl_n+1)); echo \"$__tl_n $__tl_s\" > " .. dir .. "/exit'; clear\n"
end

function S:open()
  if self.mode then return self.mode end
  local has = self:run("command -v bash >/dev/null 2>&1 && (" .. INSTALL .. ")", 300).code == 0
  if has then
    local d = M.dir
    local start = table.concat({
      "mkdir -p " .. d, "rm -f " .. d .. "/exit " .. d .. "/trace",
      tmux("kill-server") .. " 2>/dev/null",
      "printf 'set -g history-limit " .. self.history .. "\\nset -g status off\\n' > " .. d .. "/tmux.conf",
      tmux(("-f %s/tmux.conf new-session -d -s %s -x %d -y %d bash --noprofile --norc"):format(d, M.session,
        self.width, self.height)),
      tmux("send-keys -t " .. M.session .. " -- " .. q(setup(d))),
      "i=0; while [ ! -s " .. d .. "/exit ] && [ $i -lt 100 ]; do sleep 0.05; i=$((i+1)); done",
      tmux("clear-history -t " .. M.session),
      ": > " .. d .. "/raw",
      tmux("pipe-pane -o -t " .. M.session .. " " .. q("cat >> " .. d .. "/raw")),
      "test -s " .. d .. "/exit",
    }, "\n")
    has = self:run(start, 60).code == 0
  end
  if has then
    self.mode = "tmux"
    self.prompt = trim_end(self:screen()):match("[^\n]*$") .. " "
  else
    self.mode = "plain"
    local r = self:run("echo \"$(id -un 2>/dev/null || echo root)@$(hostname 2>/dev/null || echo localhost):$(pwd)\"", 30)
    local who, cwd = (r.stdout or ""):match("^([^:\n]*):([^\n]*)")
    self.who, self.cwd = who or "root@localhost", cwd or "/"
    self.prompt = self:plain_prompt()
  end
  return self.mode
end

function S:screen()
  if self.mode == "plain" then return self.prompt end
  local r = self:run(tmux("capture-pane -p -J -t " .. M.session), 30)
  return trim_end(r.stdout)
end

-- one exec: note where the prompt is, send the keys, wait for the prompt to come back (a new count in the exit file
-- and bash in front again, seen twice running) or for the wait to run out, then read the screen from that prompt on.
-- The first output is the first byte past the keys' own echo, looked for every M.first_poll seconds and timed in
-- milliseconds by the computer's clock (date's %N; whole seconds where it has none): it once counted polls of the
-- prompt's wait, 0 or 100 and nothing between (the claim First Output Time Is Measured, 2026-10-06)
local function sender(keys, wait)
  local d, s = M.dir, M.session
  local send = keys ~= "" and tmux("send-keys -t " .. s .. " -- " .. q(keys)) or ":"
  local size = "$(wc -c < " .. d .. "/raw 2>/dev/null || echo 0)"
  return table.concat({
    "b=$(cut -d' ' -f1 " .. d .. "/exit 2>/dev/null)",
    "r0=" .. size .. "; r0=$((r0+0)); first=",
    "ms() { t=$(date +%s%N); case $t in *N) echo $(( $(date +%s) * 1000 ));; *) echo $(( t / 1000000 ));; esac; }",
    "t0=$(wc -l < " .. d .. "/trace 2>/dev/null || echo 0); t0=$((t0+0))",
    "touch " .. d .. "/mark; sleep 0.01",
    "set -- $(" .. tmux("display -p -t " .. s .. " '#{history_size} #{cursor_y}'") .. ")",
    "a=$(( $1 + $2 ))",
    "start=$(ms)",
    send,
    "seen=0",
    "while [ $(( $(ms) - start )) -lt " .. math.floor(wait * 1000) .. " ]; do",
    -- until the first output, only the cheap look at its size
    "  if [ -z \"$first\" ]; then",
    "    if [ " .. size .. " -gt $((r0 + " .. (#keys + 8) .. ")) ]; then first=$(( $(ms) - start )); else sleep " .. M.first_poll .. "; continue; fi",
    "  fi",
    "  n=$(cut -d' ' -f1 " .. d .. "/exit 2>/dev/null)",
    "  c=$(" .. tmux("display -p -t " .. s .. " '#{pane_current_command}'") .. ")",
    "  if [ \"$n\" != \"$b\" ] && [ \"$c\" = bash ]; then seen=$((seen+1)); [ $seen -ge 2 ] && break; else seen=0; fi",
    "  sleep " .. M.poll,
    "done",
    "h=$(" .. tmux("display -p -t " .. s .. " '#{history_size}'") .. ")",
    "n=$(tr ' ' , < " .. d .. "/exit 2>/dev/null)",
    "echo \"@tablua b=$b n=$n seen=$seen first=$first\"",
    -- the files written while it ran: newer than the mark, under its folder and the usual places
    "echo @files",
    "p=$(" .. tmux("display -p -t " .. s .. " '#{pane_current_path}'") .. ")",
    "for f in $(find \"$p\" /app /tmp /root -xdev -type f -newer " .. d .. "/mark 2>/dev/null | grep -v '^" .. d
      .. "' | sort -u | head -" .. M.files .. "); do echo \"$(wc -c < \"$f\" 2>/dev/null) $f\"; done",
    "echo @trace",
    "tail -n +$((t0+1)) " .. d .. "/trace 2>/dev/null | head -n " .. M.trace,
    "echo @raw",
    "tail -c +$((r0+1)) " .. d .. "/raw 2>/dev/null | head -c " .. M.raw_bytes .. " | base64",
    "echo @screen",
    tmux("capture-pane -p -J -t " .. s .. " -S $(( a - h ))"),
  }, "\n")
end

function S:send(keys, wait)
  keys = tostring(keys or "")
  wait = math.min(math.max(tonumber(wait) or M.wait, 0), self.limit)
  self:open()
  if self.mode == "plain" then return self:plain(keys, wait) end
  local t0 = self.now and self.now()
  local r = self:run(sender(keys, wait), wait + 60)
  local ms = t0 and (self.now() - t0) * 1000 or nil
  local out = r.stdout or ""
  local head, files, traced, raw, screen = out:match("^(@tablua[^\n]*)\n@files\n(.-)@trace\n(.-)@raw\n(.-)@screen\n?(.*)$")
  if not head then
    return { keys = keys, wait = wait, screen = trim_end(out .. (r.stderr or "")), done = false, ms = ms,
      broken = "the terminal did not answer" }
  end
  local before, after, code, seen, first = head:match("^@tablua b=(%d*) n=(%d*),?(%-?%d*) seen=(%d+) first=(%d*)")
  local done = tonumber(seen) and tonumber(seen) >= 2 and after ~= before
  local written = {}
  for size, path in files:gmatch("%s*(%d+) ([^\n]+)") do written[#written + 1] = { path = path, size = tonumber(size) } end
  local trace = {}
  for line in traced:gmatch("[^\n]+") do trace[#trace + 1] = line end
  return { keys = keys, wait = wait, screen = trim_end(screen), done = done and true or false,
    exit = done and tonumber(code) or nil, ms = ms, first_ms = tonumber(first),
    files = written, raw = require("term.pty").base64(raw), trace = trace }
end

-- the plain session: a command at a time, in the folder the last one left, under its own time limit
function S:plain_prompt()
  return ("%s:%s%s "):format(self.who, self.cwd, self.who:match("^root@") and "#" or "$")
end

function S:plain(keys, wait)
  local cmd = keys:match("^(.*)\n$")
  local before = self.prompt
  if not cmd then
    return { keys = keys, wait = wait, screen = before .. keys, done = true, exit = nil,
      note = "a plain terminal runs whole commands only: nothing was running to send these keys to" }
  end
  local t = math.max(1, math.ceil(wait))
  local d = M.dir
  local inner = "cd " .. q(self.cwd) .. " 2>/dev/null; " .. cmd .. "\n__tl_s=$?; mkdir -p " .. d .. "; pwd > " .. d
    .. "/cwd; exit $__tl_s"
  local r = self:run(("if command -v timeout >/dev/null 2>&1; then timeout -k 5 %d bash -c %s; else bash -c %s; fi"
    .. " </dev/null 2>&1; echo \"@tablua $?\"; cat %s/cwd 2>/dev/null"):format(t, q(inner), q(inner), d), t + 60)
  local out = r.stdout or ""
  local body, code, cwd = out:match("^(.-)\n?@tablua (%d+)\n?([^\n]*)")
  self.cwd = (cwd and cwd ~= "") and cwd or self.cwd
  self.prompt = self:plain_prompt()
  code = tonumber(code)
  local stopped = code == 124
  local screen = trim_end(before .. cmd .. "\n" .. (body or out) .. (stopped and "" or ("\n" .. self.prompt)))
  return { keys = keys, wait = wait, screen = screen, done = not stopped, exit = (not stopped) and code or nil,
    ms = r.ms, note = stopped and ("stopped after %d seconds: a plain terminal cannot leave a command running"):format(t) or nil }
end

return M
