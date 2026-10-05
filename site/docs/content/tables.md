---
description: Every table Tablua keeps in an agent's SQLite file, with every column and what it means.
---

# Tables

Every table Tablua keeps in an agent's file, and what each column means. All names start with `tablua_`. The schema is at version 10 (`tablua_meta`).

The tables fall into three parts ([The log and the build](/concepts/log-and-build)), told apart by their key:

- **The log**: what the agent did. Keyed by `(task, n)`, the run's task and the step number. Rows are only ever added.
- **The build**: what the agent is making. Keyed by file. Rows are replaced as the files change.
- **The policy**: how the next decision is made. Keyed by neither.

## The log

### tablua_state

Where the work stood when a decision was made. Written by the host, from facts.

| Column | Meaning |
| --- | --- |
| `task`, `n` | the run and the step (key) |
| `stage` | the stage, worked out from facts ([Stages and moves](/reference/moves)) |
| `passed`, `total`, `pass` | scenarios passing, scenarios in all, and their ratio |
| `stalls` | steps in a row that made no progress |
| `last_verb`, `last_outcome` | the step before and how it went |
| `cause` | what was judged the cause of the last failure: `the_steps`, `the_app_code`, `the_page`, `a_library_call`, `the_feature`, `unclear` |
| `pages_ok` | 1 when every page answers |
| `own_checks` | checks the agent wrote in its own words |
| `ask` | the kind of ask |
| `versions` | the versions of the code and models, as JSON |
| `at` | when |

### tablua_candidate

Every move that could have been made, one row each, with each model's number for it.

| Column | Meaning |
| --- | --- |
| `task`, `n`, `move` | the step and the move (key) |
| `jev_p`, `jev_conf`, `jev_margin` | Jev's probability for the move, its confidence, and the gap to its next best |
| `jev_form` | the form of question Jev was asked (`choice`) |
| `p_progress`, `p_ship` | TabPFN's chance the move makes progress; that the run ships |
| `cost_q50`, `cost_q90` | estimated cost, median and 90th percentile |
| `explored` | 1 when the move was taken to explore |

### tablua_decision

The move taken, and who took it.

| Column | Meaning |
| --- | --- |
| `task`, `n` | the step (key) |
| `chosen` | the move |
| `by` | who decided: `jev`, `tabpfn`, `arbiter` |
| `propensity` | how likely the choice was under the policy that made it |
| `policy` | which policy |
| `at` | when |

### tablua_action

Each call the move made.

| Column | Meaning |
| --- | --- |
| `task`, `n`, `i` | the step and the call's place in it (key) |
| `cmd` | the command |
| `file_kind`, `op`, `target` | the kind of file, what was done to it, and its path or unit |
| `bytes`, `exit`, `duration_ms` | size written, exit code, time taken |

### tablua_outcome

How the step turned out. Written by the host.

| Column | Meaning |
| --- | --- |
| `task`, `n` | the step (key) |
| `verb` | the move |
| `outcome` | `complete`, `broken`, `no_effect`, or `denied` (the person said no) |
| `progress` | 1 if the step helped ([the rule](/concepts/step-loop#progress-worked-out-from-the-rows)), else 0 |
| `regressed` | 1 if a scenario that passed fails now |
| `same_failure` | 1 if the same failure as before the step |
| `passed`, `total` | scenarios passing after the step |
| `failing` | the failing scenarios, as JSON |
| `note` | what the host noted |

### tablua_run

How a run ended.

| Column | Meaning |
| --- | --- |
| `task` | the run (key) |
| `shipped` | the app was published |
| `answered` | the task was answered |
| `works` | the published app works when checked |
| `right` | it does what was asked, by a hidden check |
| `changed` | a change asked after shipping was made |
| `steps`, `cost`, `at` | steps taken, cost in US dollars, when |

### tablua_change

Each operation of a change block a step made ([The program as rows](/concepts/program-as-rows)): where the log meets the build. Key: `task`, `n`, `i`; also `op` (`add`, `replace`, `delete`, `rename`, `scenario`), `kind` (the unit's kind), `name`, `lines` (code lines added, negative when taken away), `named_by` (units that named the target before) and `breaks` (units left naming something no unit defines).

### tablua_effect

What each step changed, as keywords ([Effects vocabulary](/reference/effects)). Key: `task`, `n`, `keyword`, `arg`.

### tablua_feature

Jev's answers to extra questions about a step, as numbers. Key: `task`, `n`, `name`; also `value` and `form`. Names include `ask_dates`, `ask_counts`, `ask_groups`, `ask_delete`, `ask_edit` and `done`.

### tablua_label

Labels given after the fact, such as Jev's hindsight. Key: `task`, `n`, `head`, `source`; also `value` and `at`. Head `contrib`, source `jev_hindsight`.

### tablua_prediction

Every prediction made, scored once its outcome lands. Key: `task`, `n`, `head`, `move`; also `p`.

### tablua_control

The controls a step chose among on a screen (Tablua's Mac app). Key: `task`, `n`, `i`; also `id`, `app`, `verb`, `role`, `label`, `ord` and `chosen`.

## The build

| Table | Key | Holds |
| --- | --- | --- |
| `tablua_section` | `file`, `n` | a file's sections: `kind`, `lang`, `body` |
| `tablua_unit` | `file`, `section`, `n` | top-level units: `kind`, `name`, `source` |
| `tablua_shape` | `file`, `section`, `n` | each unit's columns: `lines` (code lines), `arity` (a function's parameters), `depth` (deepest block), `names` (other units it names) |
| `tablua_scenario` | `file`, `n` | scenarios: `name`, `text` |
| `tablua_line` | `file`, `scenario`, `n` | scenario lines: `keyword`, `text` |
| `tablua_link` | `file`, `kind`, `source`, `target` | links between units, with `found` |
| `tablua_break` | (view) | links with nothing at their end, and actions nothing reaches |

Link kinds: `post` (page to action), `defines`, `sends` (page to field), `reads` (action to field), `line`, `press`, `field` and `see` (scenario line to what must answer it).

## The policy, and metadata

| Table | Holds |
| --- | --- |
| `tablua_gate` | the gates a run ran under: `name`, `predicate`, `version`, `retired_by` |
| `tablua_fit` | TabPFN fits kept for reuse: `head`, `schema` (key), `id` (the fit's id at Prior Labs), `rows`, `at` |
| `tablua_ranking` | rankings a run paid TabPFN for, reused across steps: `task`, `head`, `key` (key), `n`, `ps` |
| `tablua_meta` | `key`, `value`; `version` is the schema version |
