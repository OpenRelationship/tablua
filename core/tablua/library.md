---
name: tablua
description: Tablua, the continual tabular agent harness (issue #1, owner 2026-10-04) — the agent's work as typed rows in its own SQLite file (state, candidates with Jev's and TabPFN's numbers, decisions, actions, outcomes, runs, fits, predictions, gates) and TabPFN's training rows as a query over them; use when changing what the agent records of its work, how it learns from it, or how decisions are taken from the rows.
summary: tablua.open(db) -> t; t:state, t:candidates, t:decision, t:action, t:outcome (-> progress), t:run, t:prediction, t:fit/fitted, t:attach(name, path), t:training(head) -> {columns, rows}, labels; tablua.progress(outcome, before). db is arock-log's port, db:exec(sql, params) -> rows. The program as rows (issue #2): tablua.source decode(org) -> rows, compile(rows) -> org, from_files, from_lui, units, scenarios; tablua.org write/read. Hindsight (issue #1, M2): t:label(task, n, head, value, source); tablua.hindsight.label(t, jev, task) asks Jev, after a run, whether each step contributed; t:training("contrib") trains on those labels. Effects (M2): t:effects(task, n, list); tablua.effects.compare(before, after, step, commands); tablua.telemetry.derive(t, task); t:training("effect:<Keyword>").
do:
  - Keep every fact a typed column; never a sentence to be parsed back.
  - Name every table tablua_; a host can let the harness reach no other.
  - Read training rows with a query over the tables, other files' first, oldest first.
  - Label with what the agent cannot write: tests, the page, the person's check.
dont:
  - Touch arock-log's events or its schema; Tablua's tables sit beside them in the same file.
  - Use goto, //, utf8 or FFI: this runs on LuaJIT, Lua 5.4/5.5, Luerl and any Lua VM a host embeds.
---

# core/tablua

Issue #1. The agent is its SQLite file: where the work stood at each decision (`tablua_state`), every move it could
have made with what Jev and TabPFN said of it (`tablua_candidate`), the move taken and by whom (`tablua_decision`),
the calls it made (`tablua_action`), how the step turned out and whether it helped (`tablua_outcome`), and how the
run ended (`tablua_run`). TabPFN's fits and predictions are rows too, and so are the hand-written gates still live
(`tablua_gate`), each retired by an A/B.

What TabPFN learns from is `t:training(head)`: one row per decided step, with its move, stage, share passing,
stalls, last move and outcome, cause, Jev's probability and margin. Head `progress` labels a step by whether it
helped (`tablua.progress`); head `ship` by whether its run shipped and worked. Another computer's file attached
with `t:attach` is read with this one's, so a computer learns from every other's steps.

Issue #2. The program is rows too, and its file is real org (owner, 2026-10-04): `source.lua` cuts a program into
sections (notes, feature, steps, code, page), its Lua into top-level units (action, function, local, step, other
statement) and its feature into scenarios with their step lines, and compiles the rows to org, each row a heading
with a drawer for its columns and a source block for its text (`org.lua`). Nothing is lost: compile(decode(org)) is
the org, and `just tool eval build rows` holds that over every app in the eval history.

Schema 3 keeps a program's rows in the agent's file (`program.lua`): `tablua_section`, `tablua_unit`, `tablua_scenario` and
`tablua_line`, keyed as the org file's headings are, and `t:compile(file)` gives its org back from them.

Schema 4 adds labels given after the fact (`tablua_label`). `hindsight.lua` gives Jev a finished run, its ask,
how it ended and every step, and keeps its chance that each step contributed to the app built as head `contrib`
(source `jev_hindsight`). Progress is short-sighted; this is the long view. It is a training target only, never an
input at decision time and never the ship label, and is judged on held-out runs (`just tool eval build fit`).

Schema 5 adds the harness's own behaviour model (`tablua_effect`). Each step is Given (the state), When (the
move) and Then (its effects), keywords from a closed vocabulary that the harness writes from its telemetry, never
the writer. The effects cover tests (a scenario turned green or red, a Gherkin line fixed, by the kind of line),
pages, commands, the stage and how the step was judged. `effects.lua` compares snapshots before and after a step,
`telemetry.lua` builds them from arock-log's keyword rows (where the whole file is open), and a host's harness records
them from its facts as it goes. Each frequent effect is a head: `t:training("effect:<Keyword>")`.

Modules: `init.lua`, `schema.lua`, `source.lua`, `org.lua`, `program.lua`, `hindsight.lua`, `effects.lua`,
`telemetry.lua`; `init_test.lua`, `source_test.lua`, `effects_test.lua`.

## Links and breaks (schema 6, issue #1 M6c)

`tablua.links` reads what a program's rows name that another row must hold, and putting a file's rows keeps them
as `tablua_link`:
- a page names the actions it posts to and the fields it sends;
- an action names the fields it reads;
- a scenario line in the app's own words needs a step;
- a line in the page's words needs a label, a field or text the page holds, unless the scenario typed that text
  or it holds a number.

A line's link is settled against every file's steps and text, so a step written later mends it. `tablua_break`
is the view of links with nothing at their end, plus actions no page posts to (`orphan`); `t:breaks()` reads it.
Over the eval history (`just tool eval build breaks`, 2026-10-04), breaks were found in:
- 4 of the 21 runs whose app failed the person's check;
- 1 of the 17 runs the harness stopped with a working app;
- 10 of the 122 runs that worked, mostly leftover actions nothing needed.


Schema 10 adds change blocks (`change.lua`, context/projects/arock/features/change-blocks; owner, 2026-10-04): an
edit is a short script of operations on the program's rows (`%% add`, `replace`, `delete`, `rename`, `scenario`),
applied all or nothing like a migration, with the change that undoes it given back. Each operation is a row
(`tablua_change`: op, kind, name, code lines added, units naming it, units left naming nothing, via `t:change`),
and each unit has columns of its own (`tablua_shape`: code lines, parameters, deepest block, the units it names),
put with the program. `lexer.lua` is the Lua tokenizer under both: a rename reaches references and never a string or
a comment. Colm's model (a grammar, a tree, transformations over it) in portable Lua, not Colm's binary.
