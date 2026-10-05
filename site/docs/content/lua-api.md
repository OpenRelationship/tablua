---
description: The Lua API of Tablua's harness - the tablua module, agent.learn, robot, and the modules for program rows and edits.
---

# Lua API

The harness's main Lua modules, in `core/`. Everything here is portable Lua: it runs on LuaJIT, Lua 5.4 and 5.5, and any other Lua VM.

## tablua

```lua
local tablua = require("tablua")
local t = tablua.open(db, { clock = fn })
```

`db` is any object with `db:exec(sql, params) -> rows`. On LuaJIT, `require("ports.sqlite").open(path)` gives one. `clock` returns the time as text; by default, UTC in ISO 8601. `open` creates Tablua's tables if they don't exist.

### Writing a step

| Function | Writes |
| --- | --- |
| `t:state{ todo, n, stage, passed, total, stalls?, last_verb?, last_outcome?, cause?, pages_ok?, own_checks?, ask?, versions? }` | where the work stood |
| `t:candidates(todo, n, { { move, jev_p?, jev_conf?, jev_margin?, p_progress?, p_ship?, cost_q50?, cost_q90?, explored? }, ... })` | every move that could be made |
| `t:decision{ todo, n, chosen, by, propensity?, policy? }` | the move taken, and by whom |
| `t:action{ todo, n, i, cmd, file_kind?, op?, target?, bytes?, exit?, duration_ms? }` | a call the move made |
| `t:outcome{ todo, n, verb, outcome, passed?, total?, regressed?, same_failure?, failing?, note? } -> progress` | how it turned out; returns 1 or 0 |
| `t:run{ todo, shipped, answered, works, right?, changed?, steps?, cost? }` | how the run ended |
| `t:features(todo, n, { name = number }, form)` | Jev's answers as feature values |
| `t:results(todo, n, res, file?) -> summary` | a test run's keyword tree (`robot.run`'s result), one `tablua_result` row per keyword; returns `robot.summary(res)` |
| `t:tasks() -> { { file, name, text, runs, passed, fails_at } }` | the program's tasks, each with its record over every run (`tablua_task_record`) |
| `t:effects(todo, n, { { keyword, arg }, ... })` | the step's effects |
| `t:label(todo, n, head, value, source)` | a label given after the fact |
| `t:gate{ name, predicate, version?, retired_by? }` | a gate the run ran under |

### Reading for learning

| Function | Returns |
| --- | --- |
| `t:training(head, { before = true }?)` | `{ columns, rows, keys }, labels`: one row per decided step, oldest first. `head` is `"progress"`, `"ship"`, `"contrib"` or `"effect:<Keyword>"`. With `before`, only the columns known before Jev answers. |
| `t:attach(name, path)` | reads another file's rows beside this one's; attached files come first in training |
| `t:prediction(todo, n, head, move, p)` | logs a prediction |
| `t:scored(head) -> { n, right, brier }` | how logged predictions have done |
| `t:fit(head, schema, id, rows)`, `t:fitted(head, schema)` | keeps and finds a fit |
| `t:count(table) -> n` | rows in a table, by short name (`"state"`, `"outcome"`, ...) |

### Constants

| Name | Value |
| --- | --- |
| `tablua.columns` | the training columns, in order |
| `tablua.before` | how many leading columns are known before Jev answers (9) |
| `tablua.categorical` | which columns are categories, 0-based |
| `tablua.row(state, move)` | a row in the `before` columns, for scoring a move not yet taken |
| `tablua.progress(outcome, before)` | the progress rule, on its own |

## agent.learn

```lua
local learn = require("agent.learn").new{ tablua = t, tabpfn = port, memory = m?, on = fn?, log = fn? }
```

| Function | Does |
| --- | --- |
| `learn:rank(checkpoint, ctx, candidates)` | `{ { name, p }, ... }` best first, or `nil, why`. `checkpoint` is `"step"` (candidates are move names) or `"control"`. For `"step"`, `ctx` holds `stage`, `pass`, `stalls`, `last_verb`, `last_outcome`, `cause`, `own_checks` and `n`; with `todo` and `at` the predictions are logged. |
| `learn:training(checkpoint)` | the training set and labels it would fit on |
| `learn:record(checkpoint)` | `{ n, right, brier }` |
| `learn:record_line(checkpoint)` | the record as one line, for a decision model to read |

Settings on the module: `learn.min_rows` (12), `learn.min_each` (3), `learn.refit` (25), `learn.per_run` (20), `learn.per_day` (4,000,000 tokens), `learn.model` (`"v3.5-fast_default"`).

## ports.tabpfn

```lua
local tabpfn = require("ports.tabpfn").new({ fetch = fetch, now = now? }, { key = key, model? })
```

`fetch` sends an HTTP request; on LuaJIT, `require("ports.curl")` provides `fetch` and `now`. The port has `estimate`, `fit`, `predict` and `limits`. A table is `{ columns, rows }`.

## tablua.source

The program as rows.

| Function | Does |
| --- | --- |
| `src.decode(org) -> rows` | an org file into sections and units |
| `src.compile(rows) -> org` | rows back into the org file, byte for byte |
| `src.from_files{ tests?, keywords?, code?, markup?, notes?, lang? } -> rows` | separate files into one program's rows |
| `src.tests(text) -> head, items` | a Robot file's head and its tests and user keywords, `{ kind, name, text }` |
| `src.calls(item) -> { { path, keyword, args } }` | the keyword calls a test or user keyword makes, `FOR` and `IF` bodies included |

## robot

An agent's tests in Robot Framework's syntax, parsed and run in portable Lua (`core/robot`).

```lua
local robot = require("robot")
local suite = robot.parse(text)
local lib = robot.library()
lib:add("There is a plant ${name}", function(name) plants.add(name) end)
local res = robot.run(suite, { libraries = { lib }, clock = os.clock })
```

| Function | Does |
| --- | --- |
| `robot.parse(text) -> suite` | a Robot file's settings, variables, tests, tasks and keywords |
| `robot.parse.cut(text) -> head, items` | the file cut into its head and each test and keyword, byte for byte |
| `robot.library() -> lib`, `lib:add(name, fn)` | a library of Lua keywords; `${arg}` in a name is an embedded argument |
| `robot.run(suite, { libraries, clock?, variables?, only?, rpa? }) -> res` | runs the tests, or with `rpa` the tasks; every keyword run is a node with its status (`PASS`, `FAIL`, `SKIP`, `NOT RUN`), message and time |
| `robot.summary(res)` | `{ passed, total, undefined, failing = { { test, path, keyword, why, reach } } }` |
| `robot.rows(res)` | one row per keyword run, as `tablua_result` keeps them |
| `robot.record(test, name?) -> text` | a passing test's run written as a task: its top-level calls in the order they ran, with the values they had, loops and branches unrolled |
| `robot.is_builtin(name)` | whether a name is one of BuiltIn's keywords |

A call is answered by the suite's own keywords first, then each library's, then BuiltIn's. Names match without regard to case, spaces or underscores, and a leading `Given`, `When`, `Then`, `And` or `But` is ignored, as in Robot.

## tablua.edit

| Function | Does |
| --- | --- |
| `edit.index(path, text) -> { name, ... }` | the units an edit can name, in file order |
| `edit.apply(path, text, unit, source) -> text` or `nil, why` | replaces (or adds) one unit; the new unit must compile |

## agent

The step machine itself, for driving your own world:

```lua
local agent = require("agent")
local a = agent.new(env, world)      -- env = { jev, mercury, learn?, memory?, tablua?, log?, ... }
local req = a:begin(text)
local next = a:step(req)             -- { "act", step } or { "done", why }
local r = a:perform(req, step)       -- nil, { "ask", form }, { "wait", what } or { "done", said }
a:close(req, step)                   -- records the step and learns from it
```

A *world* is a table describing what the agent can do and how: its tools, the question Jev is asked, how the state reads, and what each tool does. See `core/agent/init.lua` for the full contract.
