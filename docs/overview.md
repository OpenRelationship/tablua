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
 │ rows · patch · lint · check · sheet ─┼─ exec ──▶ ports.moonsplice ◀── studio world (patch moves) │
 └──────────────────────────────────────┘            │ checkpoint + learn ◀── training rows ──┘      │
                                                     │ tablua   the rows (SQLite, tablua_* tables)   │
 OpenRouter: Jev (decider), minimax/minimax-m3 ◀──── │ ports.jev, ports.chat                         │
                                                     │ robot    tests in Robot syntax, run in Lua    │
                                                     └──────────────────────────────────────────────┘
```

| Piece | Where | What it does |
|---|---|---|
| `agent` (`core/agent/init.lua`) | Tablua | The loop as an explicit state machine: `begin`, `step`, `perform`, `close`. No coroutines, so any embedded Lua runs it. |
| `studio` (`core/studio/`) | Tablua | Moonsplice as the world: the moves as typed patches (`moves`), what TabICL reads of a comp (`features`), the writer's and critic's prompts (`prompts`), and the world itself (`world`): `question`, `state`, `allowed`, `act`. |
| `ports.moonsplice` | Tablua | The engine: `bin/moonsplice rows \| patch \| lint \| check \| sheet --json` through the host's `exec` (the Studio's session later). |
| `checkpoint` (`core/agent/checkpoint.lua`) | Tablua | Before a decision: asks TabICL to rank the legal moves. After a step: writes its rows and its outcome. |
| `learn` (`core/agent/learn.lua`) | Tablua | Turns the rows into a training table, asks the tabular model, keeps its fits, predictions and rankings as rows. |
| `ports.jev` | Tablua | Jev: a typed choice with a probability per option, through OpenRouter. |
| `ports.chat` | Tablua | Any chat model. MiniMax M3 through OpenRouter, or `service = "minimax"` for MiniMax's own API. |
| `ports.tabicl` | Tablua | TabICL in TabPFN's port shape. Calls the host's own TabICL (`host.tabicl`) or a server's url. |
| `tablua` (`core/tablua/`) | Tablua | The rows: one SQLite file per run, every table named `tablua_*`, so a host can let the harness write those and no others. `tablua.studio` keeps the comp as rows per step (schema 19). |
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
a:perform(req, step) ── world.act: treat | a patch move | look  → step.outcome, step.note
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

### The comp: what Moonsplice is making, one snapshot per step (schema 19)

The contract is `cadence/docs/ROWS.md` (msr/1). Each table is the engine's, with `(todo, n)` first: the comp as it
stood after step n, and n = 0 before any step. What step n changed is where snapshot n differs from n - 1
(`t:touched`); the engine's patch response says it too.

| Table | One row per | Notes |
|---|---|---|
| `tablua_msr_comp` | comp setting | width, height, duration, fps, background, seed |
| `tablua_msr_node` | node | id, kind, parent, z; 3D things are nodes under a `world` node |
| `tablua_msr_prop` | prop at rest | value with `type`: `n` number, `s` string, `b` boolean, `j` canonical JSON |
| `tablua_msr_key` | keyframe | `t` is seconds or a fact reference (`beat:12`) |
| `tablua_msr_motion` | motion that is not key to key | path, wiggle, follow, spring, drop |
| `tablua_msr_system` | system | a pure function `(t, state, q) -> rows` |
| `tablua_msr_asset`, `tablua_msr_fact` | asset, fact | media and what perception found |
| `tablua_msr_finding` | lint or check finding | by the node and prop it is about; empty id for the comp |
| `tablua_score` | judge's score | the critic's six dims per look, or the oracle's |

A step's outcome comes from these (`tablua.studio.outcome`): nothing touched is `no_effect`; a new error is
`broken`; a new finding of any other kind is `no_effect`; a change that opened and closed no finding is `neutral`
(findings cannot judge it, the next look's critic does); one still open on what the step touched is `no_effect`;
otherwise `complete`. Only `complete` labels a step as progress.

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

## 6. Moonsplice's world (`core/studio/`)

| Stage | When | Moves offered |
|---|---|---|
| `treating` | no treatment yet | `treat` |
| `building` | no nodes, or errors open | every patch move: `add_node`, `set_prop`, `add_key`, `move_key`, `drop_key`, `bind`, `add_system`, `edit_system`, `derive`, `remove`; `look` once the comp changed and has no errors |
| `polishing` | no errors | the same, and `answer` once a look scored the comp as it is |

1. **A patch move.** Jev picks the move. The writer (M3) gets the comp's rows and the standing, and calls that move's
   tool once per patch, with the engine's own payload fields. Each patch is checked for shape
   (`studio.moves.check`), then applied by the engine, which rejects what fails its checks. The comp is snapshotted,
   its findings kept, and the outcome judged from them.
2. **look.** The engine renders a contact sheet; the critic (M3, the sheet as an image) scores the six dims, kept as
   `tablua_score`.
3. **pass** is the share of seven checks that hold: the gate (no errors) and each of the six scores at 3 or more, on
   the comp as it is now.
4. **What TabICL reads** (`studio.features.columns`): the move, the stage, the last move and outcome, pass, stalls,
   the step, whether it is a game, the comp's size by table, keys bound to facts, errors and warnings open, the
   critic's lowest, mean and six scores, the last render's seconds, and steps since the last look. They are kept per
   decision as `tablua_feature` rows (form `studio`), so training reads exactly what the decision read, and earlier
   trials' sheets attached with `t:attach` train it too.
5. **Jev sees the newest contact sheet.** After a look, Jev's state is content parts: the standing as text, then
   the sheet as an image. Probed 2026-10-06 on `openai/gpt-6-luna-decisions`: a 64 px red square scored red 1.00
   as an image part, red 0.03 from the text alone; an object with an `image` field was ignored.
6. **Not yet:** a candidate is a move, not a move on a target, so the target's kind, prop and open findings are not
   columns yet; the trial's oracle (re-gate, blind critic, frame hashes) is not yet written to `tablua_run`.

The terminal, desktop and program-as-rows tables stay in Tablua; Moonsplice leaves them empty.

## 7. Where it stands (2026-10-06)

| Claim | Level shown | How |
|---|---|---|
| `ports.tabicl` ranks moves for `learn`, with a server or with the host's own model | consistent | Fixture tests; live through Modal once, `fix` 1.000 over `look` 0.003 |
| The same run writes the same rows | consistent | Three processes, byte-identical dumps |
| TabICL on Moonsplice's steps beats the base rate | not shown | Needs Moonsplice trials and its held-out Brier claim |
| A Candle TabICL matches the Python reference | correct | Moonsplice's claims (cadence/.robot/claims/tabicl.robot: logits within 2.6e-4, members within 1.2e-7, probas within 1.9e-6); checked from Tablua too, three fixtures within 1.8e-6. `bin/moonsplice tabicl` takes ports.tabicl's body on stdin |
| The studio world runs a whole request and keeps its rows | consistent | `core/studio/world_test.lua` over fakes: treat, a breaking patch, a fix, a look, answer; outcomes, snapshots, findings, scores and features as rows |
| It builds a good comp with the real engine and M3 | not shown | Needs `bin/moonsplice rows` and `patch` (Moonsplice) and a claim |
