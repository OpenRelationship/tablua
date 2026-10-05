---
name: robot
description: An agent's tests in Robot Framework's syntax, parsed and run in portable Lua (owner, 2026-10-05: org plus Robot, no Gherkin, since it is the models that read and write them) — tests and tasks as keyword calls, user keywords, Lua keyword libraries and BuiltIn, with every keyword's result kept as a tree that becomes rows; use when changing how tests are read, run or reported, or adding a keyword the runner knows itself.
summary: robot.parse(text) -> suite { settings, variables, tests, tasks, keywords }; robot.parse.cut(text) -> head, items (byte for byte); robot.library() -> lib, lib:add(name, fn) (embedded ${args} in names); robot.run(suite, { libraries, clock?, variables?, only?, rpa? }) -> result tree (rpa: the tasks instead of the tests) (PASS, FAIL, SKIP, NOT RUN per keyword); robot.summary(res) -> { passed, total, undefined, failing = { test, path, keyword, why, reach } }; robot.rows(res) -> one row per keyword; robot.record(test, name?) -> a passing test's run written as a task; robot.is_builtin(name).
do:
  - Keep Robot's own names and behaviour where the subset has them (Given/When/Then prefixes ignored, names matched without case, spaces or underscores, NOT RUN after a failure), so a model's knowledge of Robot holds.
  - Record every keyword that ran, and every one that did not, in the tree: the rows are the evidence.
  - Keep expressions (IF, Evaluate, Should Be True) in a sandboxed load with an empty environment.
dont:
  - Depend on Python's Robot Framework or any host: libraries are Lua functions a host hands the runner.
  - Use goto, //, utf8 or FFI: this runs on LuaJIT, Lua 5.4/5.5, Luerl and any Lua VM a host embeds.
---

# core/robot

Robot Framework's test data in portable Lua. `parse.lua` reads sections (Settings, Variables, Test Cases or Tasks,
Keywords, Comments), cells split by a tab or two spaces, `...` continuations, `[Arguments]`, `[Setup]`,
`[Teardown]`, `[Tags]`, `[Return]`, `FOR` (IN, IN RANGE), `IF`/`ELSE IF`/`ELSE`, `RETURN`, `BREAK`, `CONTINUE`
and assignments; `cut` gives every test and keyword its exact text, so a file is rows and back byte for byte.

`run.lua` runs a suite: a call is found among the suite's keywords, then each library's (Lua functions, embedded
arguments allowed), then BuiltIn's (`builtin.lua`: Should Be Equal, Should Contain, Length Should Be, Evaluate, Run
Keyword And Expect Error and the rest of the common set); `vars.lua` keeps the scopes and Robot's substitution.
Every keyword run is a node: type, name, arguments, status, message, time, children. `result.lua` reads the tree
as a summary (what passed; for each failing test where it failed, why, and its reach, how many keywords passed
before it) and as rows, which Tablua keeps in `tablua_result`.

Modules: `init.lua`, `parse.lua`, `run.lua`, `vars.lua`, `builtin.lua`, `result.lua`; `parse_test.lua`,
`run_test.lua`.
