---
description: How a Tablua agent takes one step at a time - stages worked out from facts, moves allowed per stage, and the rows each step writes.
---

# The step loop

A Tablua agent works one step at a time. Each step has the same shape: read where the work stands, list the moves allowed, choose one, do it, and check how it went. Every part of that is written down as a row.

{{diagram:loop}}

## Code owns the workflow, models make the choices

Tablua draws a clear line between what is decided by code and what is decided by a model.

**Code decides where the work stands.** The host reads facts it can check: which feature files exist, whether the person has agreed to them, how many test scenarios pass, which pages answer, whether the app was published. From those facts it works out the **stage**, such as `building` or `ready`. No model is asked.

**Code decides which moves are allowed.** Each stage has a fixed list of moves. In `no_feature`, the agent can write a feature, read the help, think, or say it is blocked. In `ready`, it can publish. A model can never pick a move that is not on the list.

**Models choose among the allowed moves.** Jev picks one, with a probability for each option. TabPFN, when it is on, adds its estimate of each move's chance of making progress. Mercury then fills in what the chosen move needs.

This split keeps the agent's progress measurable. A model can be wrong about what to do next, but it can't be wrong about whether the tests pass, because it is never asked.

## The stages

| Stage | What it means | Example moves allowed |
| --- | --- | --- |
| `no_feature` | Nothing written yet | `write_feature`, `read_help`, `think` |
| `awaiting_agreement` | A feature is written; the person hasn't agreed | `wait_for_agreement`, `write_feature` |
| `building` | Scenarios are agreed and some fail | `write_steps`, `write_code`, `write_page`, `run_test`, `fix_failure`, `undo`, `rewrite` |
| `ready` | Every scenario passes and every page answers | `publish`, `look_at_app`, `fix_failure` |
| `awaiting_yes` | Publishing waits for the person's yes | `wait_for_yes` |
| `shipped` | The app is published | `answer_task` |
| `answered` | The task is done | `answer` |
| `changing` | The task asks to change an app that already shipped | `write_feature`, `write_code`, `write_page` |

The full list is in [Stages and moves](/reference/moves).

## The rows of one step

| Row | Written by | When | What it holds |
| --- | --- | --- | --- |
| `tablua_state` | host | before deciding | stage, scenarios passed and total, how long it has stalled, the last move and its outcome, the suspected cause of a failure |
| `tablua_candidate` | Jev and TabPFN | while deciding | one row per allowed move: Jev's probability, TabPFN's chance of progress |
| `tablua_decision` | the harness | when decided | the move taken, who chose it (`jev` or `tabpfn`), how likely the choice was |
| `tablua_action` | the harness | while acting | each call the move made: the command, the file and its kind, bytes written, exit code |
| `tablua_outcome` | host | after acting | how it turned out: `complete`, `broken` or `no_effect`; whether more scenarios pass; whether anything regressed |
| `tablua_effect` | host | after acting | what changed, as keywords such as `More Passing`, `Regressed` or `Page Fixed` |

At the end of a run, one `tablua_run` row records whether the app shipped and works, how many steps it took, and what it cost.

## Progress, worked out from the rows

Each outcome gets a `progress` label of 1 or 0, from a simple rule:

1. If more scenarios pass than before the step, it made progress.
2. Otherwise, if the step didn't complete, it didn't.
3. If it was a change to the app, made while scenarios were failing, and no more pass afterwards, it didn't.
4. Any other completed step did.

That rule turns every step the agent takes into a labelled example, at no cost. It is short-sighted on purpose, and Tablua adds a longer view after each run. See [How Tablua learns](/concepts/learning).

## One step per call

The host doesn't keep the agent in memory between steps. Each call reads what the last one saved, takes one step and saves again. This is why the agent can run on a computer that sleeps between steps, and why the whole agent fits in one file you can move.

The person's part, agreeing to a feature or saying yes to a publish, is never done by the agent. The run waits for it.

## Next

[Three models, one table](/concepts/three-models) explains who writes which columns, and why.
