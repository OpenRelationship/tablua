-- The terminal's rows: real and foreseen screens in the same columns, the events each shows, where they part, and
-- the step's terminal as features.
local spec = require("spec")
local tablua = require("tablua")
local sqlite = require("ports.sqlite")

local function fresh() return tablua.open(sqlite.open(":memory:"), { clock = function() return "t" end }) end

local P = "root@x:/app# "

spec.test("a real action and its foreseen screen are rows of one kind, each with the events its screen shows", function()
  local t = fresh()
  t:term("r1", 1, 1, "world", { keys = "make\n", wait = 60, screen = P .. "make\ncc -o app main.c\n" .. P })
  local ev = t:term("r1", 1, 1, "real", { keys = "make\n", wait = 60, exit = 2, done = true, ms = 900,
    screen = P .. "make\nmain.c:4:1: error: expected ';'\nmake: *** [Makefile:2: app] Error 1\n" .. P })
  spec.same({ #ev, ev[1].kind, ev[2].kind }, { 2, "compile_error", "build_failed" })
  local rows = t:term_rows("r1", 1)
  spec.same({ rows[1].source, rows[1].failed, rows[1].exit, rows[2].source, rows[2].failed }, { "real", 1, 2, "world", 0 })
  local s = t:surprise("r1", 1)
  spec.same({ s.unforeseen, s.unfulfilled, s.failed_differs }, { 2, 0, 1 })
end)

spec.test("the terminal as features: what is running, how the last exited, failures in a row, a signature seen before", function()
  local t = fresh()
  local bad = P .. "python3 run.py\nTraceback (most recent call last):\n  File \"run.py\", line 1, in <module>\n"
    .. "ModuleNotFoundError: No module named 'numpy'\n" .. P
  t:term("r1", 1, 1, "real", { keys = "ls\n", exit = 0, done = true, screen = P .. "ls\nrun.py\n" .. P })
  t:term("r1", 2, 1, "real", { keys = "python3 run.py\n", exit = 1, done = true, screen = bad })
  t:term("r1", 3, 1, "real", { keys = "python3 run.py\n", exit = 1, done = true, screen = bad })
  t:term("r1", 3, 2, "real", { keys = "pip install numpy\n", done = false, screen = P .. "pip install numpy\nCollecting" })
  local f, kind = t:term_features("r1", 3)
  spec.same({ f.commands, f.running, f.exit, f.failed, f.errors, f.repeats, f.fails_in_row, f.surprise, kind },
    { 4, 1, 1, 1, 1, 1, 2, 0, "missing_module" })
  f, kind = t:term_features("r1", 1)
  spec.same({ f.commands, f.running, f.exit, f.errors, kind }, { 1, 0, 0, 0, "none" })
end)

spec.test("the terminal's tables are log tables, keyed by the todo", function()
  local t = fresh()
  spec.eq(tablua.schema.version, 18)
  t:term("r1", 1, 1, "real", { keys = "true\n", exit = 0, done = true, screen = P .. "true\n" .. P })
  spec.eq(t:count("term"), 1)
end)

spec.test("every column filled: what was typed, the raw bytes, the files written, where the tests stood", function()
  local t = fresh()
  local E = "\27"
  t:term("r1", 1, 1, "real", { keys = "cd /app && make 2>&1 | tee build.log\n", wait = 60, exit = 2, done = true,
    ms = 1500, first_ms = 200, screen = P .. "make\nmain.c:1:1: error: x\n" .. P,
    raw = "make\n" .. E .. "[1;31mmain.c:1:1: error:" .. E .. "[0m x\n 50%\r100%\n",
    files = { { path = "/app/build.log", size = 120 }, { path = "/app/main.o", size = 900 } }, passed = 1, total = 4 })
  local r = t.db:exec("select * from tablua_term where todo = 'r1'")[1]
  spec.same({ r.program, r.programs, r.reads, r.writes, r.files, r.first_ms, r.red, r.redraws, r.passed, r.total },
    { "make", "cd,make,tee", 0, 1, 2, 200, 1, 1, 1, 4 })
  spec.eq(t:count("file"), 2)
  local f, kind, program = t:term_features("r1", 1)
  spec.same({ f.red, f.files, f.seconds, f.reads, kind, program }, { 1, 2, 1.5, 0, "compile_error", "make" })
end)

spec.test("what bash ran is kept beside what was typed: the trace and each command's program", function()
  local t = fresh()
  t:term("r1", 1, 1, "real", { keys = "cd /app && FOO=1 /usr/bin/make | tee log; for f in a; do echo $f; done\n",
    wait = 9, exit = 0, done = true, screen = P,
    trace = { "cd /app", "FOO=1 /usr/bin/make", "tee log", "for f in a", "echo $f" } })
  local r = t.db:exec("select trace, ran, program from tablua_term")[1]
  spec.eq(r.ran, "cd,make,tee,echo")
  spec.eq(r.trace, "cd /app\nFOO=1 /usr/bin/make\ntee log\nfor f in a\necho $f")
  spec.eq(r.program, "make")
  t:term("r1", 1, 2, "world", { keys = "ls\n", wait = 9, screen = P })
  spec.eq(t.db:exec("select ran from tablua_term where source = 'world'")[1].ran, nil)
end)

spec.test("a file kept at schema 15 gains the new columns at open, its rows kept", function()
  local db = sqlite.open(":memory:")
  db:exec("create table tablua_term (todo text not null, n integer not null, i integer not null, source text not null"
    .. " default 'real', keys text not null default '', wait real, exit integer, done integer not null default 1,"
    .. " failed integer, ms real, lines integer not null default 0, screen text not null default '',"
    .. " primary key (todo, n, i, source))")
  db:exec("insert into tablua_term (todo, n, i, keys) values ('old', 1, 1, 'ls')")
  local t = tablua.open(db)
  local r = t.db:exec("select keys, program, red from tablua_term where todo = 'old'")[1]
  spec.same({ r.keys, r.program, r.red }, { "ls", "", nil })
end)

spec.test("a world model's hidden state for an action, kept and read back", function()
  local t = fresh()
  t:vector("r1", 2, 1, { 0.25, -1.5, 3 }, "qwen-world-encoder")
  local v = t:vectors()
  spec.same({ #v, v[1].n, v[1].v }, { 1, 2, { 0.25, -1.5, 3 } })
  spec.eq(t:count("vector"), 1)
end)

spec.run()
