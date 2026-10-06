# .robot: our claims, as Robot tests

How we tell what we believe from what we've shown. Each claim is a Robot test:

- Its `[Documentation]` says what we believe and names the oracle, the independent thing that checks it.
- Its assertion holds the kill number, written before the measurement runs.
- A sibling test with ` (red)` after the name runs the same check on rows known to be wrong. That test must fail.

```
luajit .robot/run.lua                   every claims/*.robot (or: run.lua terminal, files whose path holds a word)
luajit .robot/run.lua fetch label [job] a bench job from the box: each trial's sheet to runs/, a trial row each
luajit .robot/run.lua invalid todo n why  mark a run whose verdicts can't be trusted, and say why
luajit .robot/run.lua history           every claim's verdicts, run by run
luajit .robot/test.lua                  the framework's own tests
```

## Verdicts

| verdict | when |
|---|---|
| `holds` | Its check passed, and the same check failed at a `Should` assertion on its red proof. |
| `KILLED` | Its check failed. |
| `BLIND` | Its check passed, and so did its red proof: the check can't fail, so it shows nothing. |
| `unproven` | Its check passed, with no red proof, or with one that broke before reaching an assertion. |
| `unknown` | It skipped: not measured yet, or too few rows (every measure skips below its `min=`). |

## The record can't be bent

- **Locked runs only.** A run counts only when its claims file is committed and unchanged on disk. Otherwise the
  run is a `DRAFT`, which is shown but doesn't count.
- **Edits after a kill are flagged.** Each claim's hash covers its text, its red proof, the keywords it names and
  the file's variables. If that changes after a counted run killed the claim, the claim is flagged `!`, and the
  kill stays.
- **The ledger is in git.** `ledger.sqlite` is committed: `claims_run`, `claim` and `trial`, plus every keyword tree
  in `tablua_result`. A run found to be wrong is marked `invalid` with a reason, never deleted.

## Levels (a `level:` tag on each claim), and what measures each

- `consistent`: the rows obey our own rules (`Count Of`, `Value Of`). This is cheap and catches plumbing bugs, but
  it is not truth.
- `correct`: a cell matches an oracle that measures it another way (`Agreement Of`, `Disagreements Of`). For
  example, `programs` (parsed from the keys) against `ran` (bash's DEBUG trap).
- `informative`: a column ranks a label better than chance (`AUROC Against Shuffled`, with a seeded permutation
  p-value).
- `useful`: it changes outcomes over k runs (`Mean Of` over `trial`, `Gap Against Shuffled` between two labels).

Never say "works" without the level.

## When to write one (and when not to)

Write a claim when one of these is true:

- We are about to say "works", "fixed" or "better", and something will be built on it.
- A decision spends runs, money or a day on it.
- We don't know, or we disagree.

An idea not yet measurable costs three lines: the claim with `Skip    <what's missing>`.

Don't write one for refactors, for behaviour a `_test.lua` already pins, or for exploration that nobody acts on
yet. A unit test pins code. A claim tests a belief about what the code does in the world, which usually means a
run's rows.

## The loop

1. Write the claim and its red proof. Commit.
2. Run the bench, then `run.lua fetch <label>`.
3. Run `run.lua`. Commit the ledger.

The harness makes the rows, and the terminal judges them. Both use one language, Robot with red first: the agent
writes tests about its task, and we write claims about the agent.

Files: `run.lua`, `ledger.lua`, `keywords.lua`, `stats.lua`, `fetch.lua`, `test.lua`, `claims/*.robot`, and `runs/`
(copied sheets, not in git).
