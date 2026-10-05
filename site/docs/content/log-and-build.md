---
description: The three parts of an agent's file - the log (what it did), the build (what it is making) and the policy (how it decides) - and how to tell which a table belongs to.
---

# The log and the build

An agent's file holds three kinds of rows. Every table belongs to exactly one of them, and you can tell which by its key.

| Part | What it holds | Keyed by | Changes by |
| --- | --- | --- | --- |
| **The log** | what the agent did: each state it decided in, the moves it could have made, the move it took, the calls that move made, how the step turned out, how the run ended | `(task, n)`: the run and the step | adding rows; nothing is ever edited |
| **The build** | what the agent is making: the files of the app, cut into sections, units, scenarios and the links between them | the file | replacing rows as the files change |
| **The policy** | how the next decision is made: the gates in force, the fits TabPFN has made, the rankings a run paid for | neither | refitting, and retiring gates through an A/B |

The test: if a fact needs a step number, it is in the log. If it needs a file, it is in the build. If it needs neither, it is policy.

## Why they are kept apart

The log is history, and history is never rewritten: a model trained on it has to be able to trust that what it reads is what happened. The build is the present: what the files say now. Mixing them would mean either rewriting history every time a file changes, or making the present a pile of every version ever written.

So they meet in one place only. When a step changes the build, the log records the change as rows: a `tablua_change` row for each operation, saying what it did to which kind of unit, how many lines it added, how many units depended on what it touched, and what it left broken. That row is in the log (it has a step number), but its columns describe the build. These columns, where an event meets the thing it changed, are what TabPFN learns most from.

The build's state at any earlier step is not stored, and does not need to be: every change block comes with the change that undoes it, so the build can be walked back from the log.

## Which table is which

| The log | The build | The policy |
| --- | --- | --- |
| `tablua_state` | `tablua_section` | `tablua_gate` |
| `tablua_candidate` | `tablua_unit` | `tablua_fit` |
| `tablua_decision` | `tablua_shape` | `tablua_ranking` |
| `tablua_action` | `tablua_scenario` | |
| `tablua_change` | `tablua_element` | |
| `tablua_outcome` | `tablua_line` | |
| `tablua_effect` | `tablua_link` | |
| `tablua_feature` | `tablua_break` (a view) | |
| `tablua_label` | | |
| `tablua_prediction` | | |
| `tablua_control` | | |
| `tablua_run` | | |

`tablua_meta` holds the schema version and belongs to none of them. Every column of every table is in [Tables](/reference/tables).

## What TabPFN sees

None of these tables is what TabPFN reads. It reads a query: one join across the log's state, candidate, decision and outcome, giving one flat row per decided step. That flat table is the spreadsheet a model sees, made fresh each time from the parts, so the parts can stay as they are while what the model sees changes.
