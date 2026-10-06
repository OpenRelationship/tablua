-- Screens as a terminal shows them, read into typed events.
local spec = require("spec")
local read = require("term.read")

local function kinds(screen)
  local out = {}
  for _, e in ipairs(read.events(screen)) do out[#out + 1] = e.kind .. "|" .. (e.name or "") .. "|" .. (e.file or "")
    .. "|" .. tostring(e.line or "") end
  return out
end

spec.test("a compiler's error names its file and line", function()
  spec.same(kinds("root@x:/app# gcc main.c\nmain.c:12:5: error: 'y' undeclared\nroot@x:/app#"),
    { "compile_error||main.c|12" })
end)

spec.test("a Python traceback is one event: its type, and the last file and line it went through", function()
  local s = "Traceback (most recent call last):\n  File \"/app/run.py\", line 3, in <module>\n    import numpy\n"
    .. "ModuleNotFoundError: No module named 'numpy'\n"
    .. "Traceback (most recent call last):\n  File \"a.py\", line 9, in f\nValueError: bad value 42\n"
  spec.same(kinds(s), { "missing_module|numpy|/app/run.py|3", "exception|ValueError|a.py|9" })
end)

spec.test("not found, in its several kinds", function()
  spec.same(kinds("bash: cargo: command not found\ncat: notes.txt: No such file or directory\n"
    .. "E: Unable to locate package libfoo-dev\nERROR: No matching distribution found for torchh\n"
    .. "/usr/bin/ld: cannot find -lpng\n"),
    { "missing_command|cargo||", "missing_file|cat|notes.txt|", "missing_package|libfoo-dev||",
      "missing_package|torchh||", "missing_module|png||" })
end)

spec.test("crashes, build failures and network failures", function()
  spec.same(kinds("Segmentation fault (core dumped)\nmake: *** [Makefile:4: all] Error 1\n"
    .. "curl: (6) Could not resolve host: example.invalid\n"),
    { "crashed|||", "build_failed|||", "network|example.invalid||" })
end)

spec.test("the same failure twice is one event counted twice; numbers do not make it new", function()
  local ev = read.events("main.c:3:1: error: expected ';' at 12\nmain.c:3:1: error: expected ';' at 13\n")
  spec.same({ #ev, ev[1].count }, { 1, 2 })
  spec.eq(read.signature("crashed", "killed at 0xdeadbeef in /tmp/abc123/x step 7"), "crashed:killed at # in /tmp/# step #")
end)

spec.test("a clean screen has no events", function()
  spec.same(read.events("root@x:/app# ls\nmain.c  Makefile\nroot@x:/app#"), {})
end)

spec.test("what was typed is not what the computer said: the command line and a heredoc's lines are skipped", function()
  spec.same(read.events("root@x:/app# grep ERROR app.log > /dev/null\nroot@x:/app# cat > t.py << 'EOF'\n"
    .. "> print('ERROR: bad')\n> raise ValueError('no')\n> EOF\nroot@x:/app#"), {})
end)

spec.test("a traceback after ^C, a script's missing command, not permitted, and a test runner's tally", function()
  spec.same(kinds("^CTraceback (most recent call last):\n  File \"s.py\", line 2, in <module>\nKeyboardInterrupt\n"
    .. "run.sh: line 3: uv: command not found\nnsenter: reassociate failed: Operation not permitted\n"
    .. "========= 2 failed, 5 passed in 0.31s =========\n"),
    { "exception|KeyboardInterrupt|s.py|2", "missing_command|uv||", "permission|||", "tests_failed|2 of 7||" })
end)

spec.test("real failures that were missed once (Terminal-Bench runs, 2026-10-06), each read now", function()
  spec.same(kinds("  File \"/app/j.py\", line 150\nSyntaxError: invalid syntax\n"
    .. "syntax error at -e line 21, at EOF\ntar: Error is not recoverable: exiting now\n"
    .. "2026-10-05 23:21:11 ERROR 404: NOT FOUND.\nobjdump: can't disassemble for architecture UNKNOWN!\n"
    .. "bash: -c: line 19: unexpected EOF while looking for matching `\"'\n"
    .. "RangeError [ERR_OUT_OF_RANGE]: The value of \"offset\" is out of range.\n"),
    { "syntax_error|||", "syntax_error||-e|21", "failed|||", "network|404||", "failed|||", "syntax_error|||",
      "exception|RangeError||" })
end)

spec.test("source code on the screen is not a failure", function()
  spec.same(read.events("140:#define EPERM        1  /* Operation not permitted */\n"), {})
end)

spec.run()
