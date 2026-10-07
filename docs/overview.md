# How Tablua fits together, for Moonsplice

Tablua is the agent harness Moonsplice runs to build games and videos as Lua comps (owner, 2026-10-06). It does
three things at every step: **Jev decides** the next move, **MiniMax M3 writes** what the move needs, and **TabICL
ranks** the moves from how earlier steps turned out. Every step is written down as **typed rows** in a SQLite
file, and those rows are both the record of the work and what TabICL learns from.

This page explains the pieces, then one step end to end, then the rows, then the learning loop, then what runs where
for Moonsplice, and last what is still to build.

## 1. The pieces

```
 Moonsplice (Rust)                                    Tablua (portable Lua, core/)
 ┌──────────────────────────────────────┐            ┌──────────────────────────────────────────────┐
 │ engine: mlua + vendored LuaJIT ──────┼── runs ──▶ │ agent    the step machine: decide, act, close │
 │ model:  Candle ── TabICLv2 ──────────┼─ host.tabicl ▶ ports.tabicl ─┐                          │
 │ curl, sqlite (FFI or Rust) ──────────┼─ host.fetch, db ▶ ports.*    │                          │
 │ lint · check · render · critic ──────┼─ world verbs ─▶ world (in Moonsplice: treat/write/fix/look)
 └──────────────────────────────────────┘            │ checkpoint + learn ◀── training rows ──┘      │
                                                     │ tablua   the rows (SQLite, tablua_* tables)   │
 OpenRouter: Jev (decider), minimax/minimax-m3 ◀──── │ ports.jev, ports.chat                         │
                                                     │ robot    tests in Robot syntax, run in Lua    │
                                                     └──────────────────────────────────────────────┘
```

| Piece | Where | What it does |
|---|---|---|
| `agent` (`core/agent/init.lua`) | Tablua | The loop as an explicit state machine: `begin`, `step`, `perform`, `close`. No coroutines, so any embedded Lua runs it. |
| world | Moonsplice (`agent/world.lua`) | The moves Jev may pick (`question`), what both minds read (`state`), what each move does (`act`), the moves legal now (`allowed`). |
| `checkpoint` (`core/agent/checkpoint.lua`) | Tablua | Before a decision: asks TabICL to rank the legal moves. After a step: writes its rows and its outcome. |
| `learn` (`core/agent/learn.lua`) | Tablua | Turns the rows into a training table, asks the tabular model, keeps its fits, predictions and rankings as rows. |
| `ports.jev` | Tablua | Jev: a typed choice with a probability per option, through OpenRouter. |
| `ports.chat` | Tablua | Any chat model. MiniMax M3 through OpenRouter, or `service = "minimax"` for MiniMax's own API. |
| `ports.tabicl` | Tablua | TabICL in TabPFN's port shape. Calls the host's own TabICL (`host.tabicl`) or a server's url. |
| `tablua` (`core/tablua/`) | Tablua | The rows: one SQLite file per run, every table named `tablua_*`, so a host can let the harness write those and no others. |
| `robot` (`core/robot/`) | Tablua | Robot Framework tests parsed and run in Lua, every keyword's result kept as a row. |

The host supplies everything that touches the world: `fetch` for HTTP, a `db` with `exec(sql, params)`, the clock,
and `tabicl`. Tablua never opens a socket or a file on its own.

## 2. One step, end to end

```
a:step(req)
 ├─ checkpoint.before ── standing = { stage, pass }  (the world sets req.stage, req.pass)
 │                     └ allowed = world.allowed(a, req)
 │                     └ learn:rank("step", ctx, allowed) ──▶ TabICL ──▶ req.ranking
 ├─ decide ──────────── Jev gets world.state + world.question (the world puts checkpoint.card in its state)
 │                     ├ close call (top two within 0.1)  → the writer arbitrates, if the world has an arbiter
 │                     ├ rank mode: TabICL's best overrules Jev when it leads by ≥ 0.15 and Jev gave < 0.9
 │                     ├ explore: with env.explore, now and then another legal move (propensity kept)
 │                     └ env.decided(req, verb, answer, how, propensity)
 └─ returns { "act", step } (step.by = how it was settled, step.propensity) or { "done" } on answer
a:perform(req, step) ── world.act: treat | write | fix | look  → step.outcome, step.note
a:close(req, step)
 └─ checkpoint.after ── memory:step(...)
                       └ rows: tablua_state, tablua_candidate, tablua_decision (unless the host wrote them),
                               tablua_outcome → progress label (1 | 0)
```

Details that decide behaviour:

1. **Jev chooses only from `question.options`.** `answer` must be one of them for Jev to be able to stop.
   `answer` is Jev's alone: exploration and rank mode never pick it.
2. **Rank mode needs `world.allowed`** and a stage in `checkpoint.ranked`. Without them TabICL ranks only after two
   failed steps, and never overrules Jev. The bench sets `checkpoint.ranked = { failing = true, stale = true }`;
   Moonsplice's stage words are `treating`, `building` and `polishing`, and the default ranks `building`.
3. **Outcome words are `complete`, `no_effect` and `broken`.** Only `complete` (or more tests passing than before)
   labels a step 1. Any other word labels it 0.
4. **Jev sees TabICL's ranking only if the world shows it.** `checkpoint.card(req, a.env)` gives the line ("From past
   outcomes ..., the chance each tool's step works now: ..."), or nothing in shadow mode. A world's `state` adds it
   when Jev reads (`for_jev`).
5. **`req.stage` and `req.pass` are set by the world** after each act, and read before the next decision.
   `pass` is one number in [0, 1]. Moonsplice's is the share of seven checks that hold: the gate, then the six
   critic scores at 3 or more.

## 3. The rows

Every table is in `core/tablua/schema.lua` (schema 18). They fall into three parts by their key.

### The log: what the agent did, keyed by `(todo, n)`, only ever added to

| Table | One row per | What Moonsplice gets from it |
|---|---|---|
| `tablua_state` | decision | Where the work stood: stage, pass, stalls, last move and outcome, cause. The inputs TabICL reads. |
| `tablua_candidate` | move that could have been made | What Jev gave each move (`jev_p`, `jev_conf`), and each part of a probability. |
| `tablua_decision` | decision | The move taken, how it was settled (`jev`, `arbiter`, `tabpfn` for any tabular overrule, `explore`) and the chance it had (propensity). |
| `tablua_outcome` | step | How it ended (`complete`, `no_effect`, `broken`), the progress label, a note. |
| `tablua_prediction` | move scored | TabICL's chance for each move; scored later against what happened (`t:scored`). |
| `tablua_ranking` | ranking asked for | A run's rankings, reused when the same state comes back, so a run never pays twice. |
| `tablua_label` | label given after the fact | Hindsight (`contrib`, Jev rereading the whole run), or a host's own (`further`, `safe`). Never an input. |
| `tablua_feature` | answer Jev gave beside its pick | Extra columns from Jev's fan-out questions. |
| `tablua_effect` | effect seen after a step | Keywords from a closed vocabulary (a test turned green, a command failed). Each can be a head. |
| `tablua_result` | keyword a test run ran | The Robot tree: what ran, with what, PASS/FAIL/NOT RUN, why. |
| `tablua_run` | run | How it ended: shipped, answered, works, steps, cost. |
| `tablua_action`, `tablua_change`, `tablua_term`, `tablua_event`, `tablua_file`, `tablua_vector`, `tablua_control` | call, edit, keystroke, screen event, file, vector, control | The terminal and desktop worlds' detail. Moonsplice needs none of them today. |

### The build: what is being made, keyed by file, replaced as files change

`tablua_section`, `tablua_unit`, `tablua_shape`, `tablua_element`, `tablua_test`, `tablua_keyword`, `tablua_call`,
`tablua_link` and the `tablua_break` view keep a program as rows (org plus Robot). Moonsplice keeps its comp as a
`.lua` file and its own checks, so it does not use these today.

### The policy: keyed by neither

`tablua_gate` (hand-written gates still live), `tablua_fit` (a model's fit per head), `tablua_meta`.

### Determinism

The same run writes the same bytes when the host passes `tablua.open(db, { clock = fn })` and, with exploration on,
`env.random`. Tables are walked in sorted order (`69459b5`). Three separate LuaJIT processes wrote byte-identical
sheets on 2026-10-06. TabICL is fixed with `random_state = 0`, so the same rows give the same probabilities.

## 4. The learning loop

```
rows ──t:training("progress", {before = true})──▶ { columns, rows }, labels
     ──learn:fitted── ≥ 12 labelled rows, ≥ 3 of each label ──▶ ports.tabicl:fit  (kept here: no call)
     ──learn:rank──▶ test rows = each legal move in the current state ──▶ host.tabicl ──▶ p per move
     ──▶ tablua_prediction, tablua_ranking ──▶ the card in the world's state, or an overrule in rank mode
     ──▶ the step happens ──▶ tablua_outcome.progress ──▶ the prediction is scored (t:scored → Brier)
```

1. **The training table** is one row per decided step, in the nine columns known before Jev answers:
   `move, stage, pass, stalls, last_verb, last_outcome, cause, own_checks, n` (`tablua.columns`, `tablua.before`).
   `move`, `stage`, `last_verb`, `last_outcome` and `cause` are categorical.
2. **The label** is the head. `progress` (did the step help) is the default; `ship` (did the run ship and work),
   `contrib` (hindsight) and `effect:<Keyword>` are the others.
3. **History** comes from every attached sheet as well as the current one (`t:attach(name, path)` adds it to
   `t.sources`). One run alone rarely has 12 labelled steps, so earlier trials' sheets are attached.
4. **Limits:** at most 20 rankings a run (`learn.per_run`), a refit every 25 new labelled rows, and the same state
   ranked again from `tablua_ranking` without a call.
5. **TabICL is in-context.** "Fitting" stores the training rows. Each prediction sends the training rows with the
   rows to score, and TabICL reads them as one table.

## 5. TabICL locally, in Moonsplice's binary

The owner's choice (2026-10-06): TabICL runs locally, never on a hosted service. Moonsplice already embeds LuaJIT
through mlua (`engine/`) and runs models with Candle (`model/`, with `metal` and `cuda` features). So TabICLv2 is
ported to Candle in Moonsplice and handed to Tablua as a host function:

```lua
-- Moonsplice registers this through mlua; Tablua calls it
host.tabicl = function(body)  -- { train = { columns, rows }, labels, categorical = { 0-based }, test = { columns, rows } }
  return { probas = { { p0, p1 }, ... } }   -- one per test row
end
local tab = require("ports.tabicl").new(host)   -- no url: the host's own TabICL
learn.new{ tabpfn = tab, tablua = t }
```

**The model.** TabICLv2 (`tabicl-classifier-v2-20260212`) has 27.5 M parameters, 110 MB in float32. It has three
stacks. `col_embedder` is a set transformer over each column, with 128 inducing points and 3 blocks.
`row_interactor` is a transformer over each row's features with rotary positions and 4 CLS tokens, 3 blocks.
`icl_predictor` is 12 blocks of attention from test rows to training rows. Embedding width is 128, with 8 heads,
GELU and pre-norm.

**Parity fixtures**, in `tablua-local/data/tabicl-parity/` (made by `tablua-local/tl/tabicl_parity.py` from the Python
reference):

| Level | What it checks | Fixture fields |
|---|---|---|
| 1. forward | The Candle model alone: same inputs, same logits | `forwards[].X`, `y_train`, `feature_shuffles`, `out` |
| 2. ensemble | Encoding, ensemble members, class shuffles, averaging, softmax at temperature 0.9 | `encoded`, `class_shuffles`, `settings` |
| 3. end to end | The table as Tablua sends it, to `probas` | `raw`, `probas` |

There are three cases, `toy` (2 columns), `steps` (Tablua's nine columns, 40 rows) and `scores` (a critic's six
scores and a gate's counts, 60 rows), each with 1 and 4 estimators. The weights as safetensors and the config are on
cuda-box at `~/tabicl-parity/`. The checksum is in `tabicl-v2.safetensors.sha256`.

**The native-Lua option** is a pure-Lua forward pass of the same model. Forward-pass arithmetic is about 2 GFLOP per
estimator on 50 rows, so it would take seconds on LuaJIT. But 27.5 M weights as Lua numbers take 220 to 440 MB. It
is the fallback for a host without Candle, and not built.

## 6. What changes for Moonsplice's world

Tablua was first shaped for apps (pages, forms, tests) and then a terminal. For games and videos:

| Already fits | Gap | Proposed |
|---|---|---|
| The step machine, Jev, M3, rank mode, the log tables, determinism, attaching past trials | The training columns speak of apps: `own_checks`, `cause`, and Jev's fan-out `ask_dates`, `ask_edit` | A Moonsplice column set: `kind` (video, game), `version`, gate errors and warnings, the critic's six scores and lowest, frame-hash stability |
| `tablua_outcome` and the progress label | The gate's findings and the critic's scores live only in the world's text and the step's note | `tablua_score` (todo, n, judge, dim, value) and `tablua_finding` (todo, n, tier, code, severity, count): schema 19 |
| `tablua_run` | The trial's oracle (re-gate, blind critic, hashes) lives in Moonsplice's ledger only | The oracle's verdict as `tablua_run.works` and `right`, so the `ship` head learns from it |
| `robot` | Moonsplice's checks are its own CLI (`lint`, `check`, `probe`) | Leave as is; a check's codes become `tablua_finding` rows |

The terminal, desktop and program-as-rows tables stay in Tablua and Moonsplice leaves them empty.

## 7. Where it stands (2026-10-06)

| Claim | Level shown | How |
|---|---|---|
| `ports.tabicl` ranks moves for `learn`, with a server or with the host's own model | consistent | Fixture tests; live through Modal once, `fix` 1.000 over `look` 0.003 |
| The same run writes the same rows | consistent | Three processes, byte-identical dumps |
| TabICL on Moonsplice's steps beats the base rate | not shown | Needs Moonsplice trials and its held-out Brier claim |
| A Candle TabICL matches the Python reference | not built | The parity fixtures above are its test |
