-- What a terminal's screen says, as rows: the errors and failures in a command's output, each one typed (a
-- compiler's error, an exception, a command or file or module or package not found, a crash), with what it names
-- and where, and a signature that is the same when the same thing goes wrong again (its words with numbers,
-- addresses and temporary names taken out). Deterministic patterns, so the screen a world model foresaw reads into the
-- same rows as the one the computer showed, and the two can be compared (tablua.term).
--
--   local read = require("term.read")
--   read.events(screen) -> { { kind, name, file, line, text, sig, count }, ... }   in the order first seen, one per sig
--   read.kinds          each kind and what it means
local M = {}

M.kinds = {
  compile_error = "a compiler or interpreter's error at a file and line",
  exception = "an uncaught exception (name is its type)",
  missing_command = "a command the shell could not find",
  missing_file = "a file or folder that does not exist",
  missing_module = "a module, library or header a program could not find",
  missing_package = "a package the package manager could not find or install",
  permission = "permission denied",
  network = "a host that could not be reached or resolved",
  build_failed = "make or another build tool stopped with an error",
  crashed = "a program killed by a signal: a segmentation fault, abort or out of memory",
  syntax_error = "the shell or a language could not parse what it was given",
  tests_failed = "a test runner's tally with failures in it (name: how many of how many failed)",
  failed = "a line that says something failed or is an error, of no kind above",
}

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- the same failure in other words-free form: no numbers, addresses, temporary paths or quoted values
function M.signature(kind, text)
  local s = tostring(text or ""):lower()
  s = s:gsub("0x%x+", "#"):gsub("/tmp/[%w%._%-/]+", "/tmp/#"):gsub("%d+", "#")
  s = s:gsub("%s+", " ")
  return kind .. ":" .. trim(s):sub(1, 160)
end

-- each pattern: kind, the Lua pattern on one line, and which captures are name, file, line
local LINE = {
  { "compile_error", "^(.-):(%d+):%d+: fatal error: (.+)$", { file = 1, line = 2, text = 3 } },
  { "compile_error", "^(.-):(%d+):%d+: error: (.+)$", { file = 1, line = 2, text = 3 } },
  { "compile_error", "^(.-):(%d+): error: (.+)$", { file = 1, line = 2, text = 3 } },
  { "compile_error", "^error%[E%d+%]: (.+)$", { text = 1 } },
  { "missing_command", "^bash: ([^:]+): command not found$", { name = 1 } },
  { "missing_command", "^.-: line %d+: ([^:]+): command not found$", { name = 1 } },
  { "missing_command", "^[%w/%._-]+: %d*:? *([^:]+): not found$", { name = 1 } },
  { "missing_command", "^([%w%._-]+): command not found$", { name = 1 } },
  { "missing_module", "No module named '([^']+)'", { name = 1 } },
  { "missing_module", "Cannot find module '([^']+)'", { name = 1 } },
  { "missing_module", "^/usr/bin/ld: cannot find %-l(%S+)", { name = 1 } },
  { "missing_module", "error while loading shared libraries: ([^:]+):", { name = 1 } },
  { "missing_package", "^E: Unable to locate package (%S+)", { name = 1 } },
  { "missing_package", "^E: Package '([^']+)' has no installation candidate", { name = 1 } },
  { "missing_package", "No matching distribution found for (%S+)", { name = 1 } },
  { "missing_package", "Could not find a version that satisfies the requirement (%S+)", { name = 1 } },
  { "missing_package", "^npm ERR! 404 .-'([^']+)'", { name = 1 } },
  { "permission", "^(.-): Permission denied$", { file = 1 } },
  { "permission", ": Operation not permitted", {} },
  { "network", "Could not resolve host:? '?([%w%.%-]+)", { name = 1 } },
  { "network", "Temporary failure in name resolution", {} },
  { "network", "Failed to connect to ([%w%.%-]+)", { name = 1 } },
  { "network", "Connection refused", {} },
  { "network", "ERROR (%d%d%d): ", { name = 1 } },
  { "network", "^curl: %(%d+%) (.+)$", { text = 1 } },
  { "build_failed", "^make: %*%*%* (.+)$", { text = 1 } },
  { "build_failed", "^make%[%d+%]: %*%*%* (.+)$", { text = 1 } },
  { "build_failed", "^CMake Error(.*)$", { text = 1 } },
  { "crashed", "Segmentation fault", {} },
  { "crashed", "core dumped", {} },
  { "crashed", "^Killed$", {} },
  { "crashed", "^Aborted", {} },
  { "syntax_error", "^bash: (.-): line (%d+): syntax error", { file = 1, line = 2 } },
  { "syntax_error", "syntax error near unexpected token", {} },
  { "syntax_error", "unexpected EOF while looking for matching", {} },
  { "syntax_error", "^syntax error at (.-) line (%d+)", { file = 1, line = 2 } },
  { "syntax_error", "^SyntaxError: (.+)$", { text = 1 } },
  { "exception", "^([%u][%w_]*Error): .+$", { name = 1 } },
  { "exception", "^([%u][%w_]*Error) %[[%u_]+%]: .+$", { name = 1 } },
  { "missing_file", "^(.-): (.-): No such file or directory$", { name = 1, file = 2 } },
  { "missing_file", "^(.-): No such file or directory$", { file = 1 } },
  { "missing_file", "can't open file '([^']+)'", { file = 1 } },
  { "missing_file", "^No such file '([^']+)'", { file = 1 } },
  { "failed", "^tar: Error is not recoverable", {} },
  { "failed", "not in gzip format", {} },
  { "missing_file", "^fatal error: (.-): No such file or directory", { file = 1 } },
}

local FAILED = { "^ERROR[:%s]", "^Error[:%s]", "^error[:%s]", "^FAILED", "^FATAL", "^fatal:", "^E: ",
  "^[%w_%.%-]+: failed to ", "^[%w_%.%-]+: cannot ", "^[%w_%.%-]+: can't ", "^[%w_%.%-]+: unknown ",
  "^[%w_%.%-]+: invalid ", "^Automatic merge failed" }

-- a test runner's tally: pytest's "2 failed, 3 passed", Robot's and others' "N PASSED, M FAILED"
local function tally(l)
  local failed = l:match("(%d+) failed") or l:match("(%d+) FAILED")
  local passed = l:match("(%d+) passed") or l:match("(%d+) PASSED")
  if not (failed or passed) or not (l:find("=", 1, true) or l:find(",", 1, true) or l:find(" in [%d%.]+s")) then
    return nil
  end
  return tonumber(passed) or 0, tonumber(failed) or 0
end
M.tally = tally

local function add(out, seen, ev)
  local what = trim((ev.name or "") .. " " .. (ev.file or ""))
  ev.sig = M.signature(ev.kind, what ~= "" and what or ev.text)
  local had = seen[ev.sig]
  if had then had.count = had.count + 1 return end
  ev.count = 1
  seen[ev.sig] = ev
  out[#out + 1] = ev
end

function M.events(screen)
  local out, seen = {}, {}
  local lines = {}
  for l in (tostring(screen or "") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = (l:gsub("\r$", "")) end
  local trace = nil   -- a Python traceback being read: its last file and line
  for _, raw in ipairs(lines) do
    local l = trim(raw)
    local hit = false
    -- what was typed is not what the computer said: the command at the prompt and a heredoc's or an unclosed
    -- quote's continuation lines ("> ") are skipped
    local typed = l:find("^[%w%._%-]+@[%w%._%-]+:[^\n]-[#$] ") or l:find("^> ") or l == ">"
    if typed then hit = true end
    if not typed and l:find("Traceback %(most recent call last%)") then trace = {} end
    if trace then
      local f, n = l:match('^File "([^"]+)", line (%d+)')
      if f then trace.file, trace.line = f, tonumber(n) end
      local ex, msg = l:match("^([%a_][%w_%.]*Error):%s*(.*)$")
      if not ex then ex, msg = l:match("^([%a_][%w_%.]*Exception):%s*(.*)$") end
      if not ex then ex, msg = l:match("^([%a_][%w_%.]*Interrupt)()$") end
      if ex then
        local kind = ex:find("ModuleNotFoundError", 1, true) and "missing_module"
          or ex:find("SyntaxError", 1, true) and "syntax_error" or ex:find("FileNotFoundError", 1, true) and "missing_file"
          or "exception"
        local name = kind == "missing_module" and tostring(msg):match("'([^']+)'") or ex
        add(out, seen, { kind = kind, name = name, file = trace.file, line = trace.line, text = l })
        trace, hit = nil, true
      end
    end
    if not hit and not trace then
      for _, p in ipairs(LINE) do
        local caps = { l:match(p[2]) }
        if #caps > 0 or (l:find(p[2]) and next(p[3]) == nil) then
          local c = p[3]
          add(out, seen, { kind = p[1], name = c.name and caps[c.name], file = c.file and caps[c.file],
            line = c.line and tonumber(caps[c.line]), text = c.text and caps[c.text] or l })
          hit = true
          break
        end
      end
    end
    if not hit and not trace then
      local passed, failed = tally(l)
      if passed and failed > 0 then
        add(out, seen, { kind = "tests_failed", name = ("%d of %d"):format(failed, passed + failed), text = l })
        hit = true
      end
    end
    if not hit and not trace then
      for _, p in ipairs(FAILED) do
        if l:find(p) then add(out, seen, { kind = "failed", text = l }) break end
      end
    end
  end
  return out
end

return M
