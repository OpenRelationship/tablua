---
description: How Tablua's agent learns from its own record - labels the rows give for free, a tabular model that needs no training run, and three ways its estimates can reach a decision.
---

# How Tablua learns

A Tablua agent learns from its own record. Every step it takes is a row, every row gets a label from what happened next, and a tabular model reads those rows to estimate which move is likely to help now. Nothing is fine-tuned. The table grows, and the model reads it.

{{diagram:learn}}

## Learning without a training run

Most ways of making an agent learn involve training: collect examples, adjust a model's weights, deploy the new model. That takes time, compute and a lot of examples, and it happens offline.

Tablua uses TabPFN, which learns *in context*. You hand it a table of labelled rows and a few unlabelled ones, and it predicts their labels in a single call. Twelve rows are enough to start; a few thousand work well. When the agent has done a few more steps, the next call simply includes them.

So the agent can learn while it works, from a record measured in dozens of steps rather than millions.

## What it learns from

Each training row is one past step, in these columns:

| Column | Meaning |
| --- | --- |
| `move` | the move taken |
| `stage` | the stage it was taken in |
| `pass` | the share of tests passing before it |
| `stalls` | how many steps in a row had made no progress |
| `last_verb`, `last_outcome` | the step before, and how it went |
| `cause` | what Jev judged the cause of the last failure to be |
| `own_checks` | how many checks the agent wrote in its own words |
| `n` | the step number |

These are the columns known *before* Jev answers. That matters: when TabPFN ranks the moves for a step that hasn't been decided yet, the row it scores looks exactly like the rows it learned from.

Wider training sets add Jev's numbers (`jev_p`, `jev_margin`) and its answers to the extra questions (`ask_dates`, `done` and others), for studying how Jev and TabPFN relate.

## What it predicts: the heads

A *head* is one question TabPFN can be asked about a step. Each has its own label, and every label comes from the record. Nobody writes them by hand.

| Head | The question | Where the label comes from |
| --- | --- | --- |
| `progress` | Did the step help? | the progress rule: more tests passing, or a completed step that wasn't a change going nowhere |
| `ship` | Did the run this step belongs to ship an app that works? | the `run` row |
| `contrib` | Looking back, did this step contribute to the app that was built? | Jev's hindsight, after the run |
| `effect:<keyword>` | Did this effect follow the step? | the step's recorded effects |

### The long view: hindsight

`progress` is short-sighted on purpose. Writing keywords before the code exists turns tests red, so it looks like no progress, but it is groundwork. To correct for that, after a run Jev reads the whole trajectory and how it ended, and says of each step whether it contributed to the final app. Those answers are stored as the `contrib` label.

Hindsight labels use information from after the step, so they are only ever used for training, never as an input when deciding.

### Effects: a behaviour model

After each step the host records what changed as keywords from a closed vocabulary: `More Passing`, `Regressed`, `Same Failure`, `Page Fixed`, `Check Failed` and more. Together they describe each step as *Given* a state, *When* a move, *Then* these effects. Each common effect can be its own head, so TabPFN can estimate, say, the chance that `rewrite` here will cause a regression. The full list is in [Effects vocabulary](/reference/effects).

## How estimates reach the decision

TabPFN's ranking can be used in three ways, and you choose which:

| Mode | What happens | When to use it |
| --- | --- | --- |
| **evidence** (default) | After two failed steps in a row, TabPFN ranks the moves and Jev sees the ranking on its card, as evidence. Every option stays open. | Everyday use: TabPFN helps when the agent is stuck, and costs nothing otherwise. |
| **shadow** | At every decision in the `building` stage, TabPFN ranks the moves and the estimates are recorded. Jev never sees them. | Measuring: you learn how good TabPFN's estimates are without them changing anything. |
| **rank** | As in shadow mode, but when TabPFN's best move leads Jev's pick by a clear margin, and Jev wasn't sure of its pick, TabPFN's move is taken. The decision row says `by=tabpfn`. | Acting on what the measurements showed. |

[Turn learning on](/guides/learning-modes) shows how to switch modes.

## Keeping it honest

**Every prediction is logged and scored.** Each ranking is a `tablua_prediction` row. When the step's outcome lands, the prediction is scored, and the agent's record, such as "right on 41 of 52 scored predictions here", is shown to Jev beside the ranking.

**Who decided is always recorded.** When an agent learns from its own decisions, the record is shaped by those decisions. Recording who chose each move, and how likely that choice was, is what allows the effect of a move to be told apart from the effect of the policy that chose it.

**It is used sparingly.** TabPFN's free tier has a daily budget. Tablua refits only after 25 new outcomes, asks for at most 20 predictions per run, reuses a ranking for a state it has already seen, and prices every prediction before making it. When the budget runs out, the agent carries on without it.

## Next

An agent's rows can teach other agents too. See [Shared experience](/concepts/shared-experience).
