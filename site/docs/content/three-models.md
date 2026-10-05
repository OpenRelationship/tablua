---
description: Jev decides, TabPFN learns, Mercury writes. Why Tablua gives three models one job each, and how they meet in the same table.
---

# Three models, one table

Tablua uses three models. Each has one job and writes its own columns. They never take over each other's work, and they meet only in the agent's tables.

{{diagram:models}}

## Jev decides

**Jev** is a decision model. You give it a description of the situation and a typed question, such as "which of these moves next?", and it answers with a choice, a probability for each option, and its confidence. Tablua reaches it through OpenRouter.

At each step Tablua asks Jev to choose among the moves the current stage allows. In the same call, it can ask Jev extra questions about the state, for example whether the person's ask involves dates or counts, or how finished the app looks. Those answers become feature columns that TabPFN can learn from. Asking everything in one call keeps the cost to one call per step.

Jev's probabilities are recorded in the `candidate` rows (`jev_p`, `jev_conf`, `jev_margin`). They are useful in two ways: as the basis of the decision, and as evidence about how far Jev's confidence can be trusted.

## TabPFN learns

**TabPFN** is a tabular foundation model from Prior Labs. It learns from a table of examples in one pass: you give it the rows you have, with their labels, and it predicts labels for new rows. There is no training run and no fine-tuning. The rows are its context, much as a prompt is a language model's context.

That makes it a good fit for an agent's record. Tablua gives TabPFN the agent's past steps as rows, labelled with whether each made progress. For the moves allowed now, TabPFN gives each one its chance of making progress in the current situation.

Its estimates are recorded too (`p_progress` in the `candidate` rows), whether or not they were used. See [How Tablua learns](/concepts/learning) for how they reach the decision.

## Mercury writes

**Mercury**, from Inception, is a fast language model for writing code. Once a move is chosen, Mercury fills it in: the Gherkin scenarios for `write_feature`, the Lua for `write_code`, the page for `write_page`. What it does becomes `action` rows: each command, each file written and its size.

Mercury never chooses the next move. Its prompts are laid out so the parts that don't change (the computer's help and the agent's knowledge base) come first, where Inception's prompt cache can reuse them across calls.

## The host checks

The fourth writer isn't a model. The **host**, the program running the agent, writes the `state` before each decision and the `outcome` after each step, from facts it can verify: test results, which pages answer, exit codes. Asking a model whether its own work succeeded invites it to say yes. Tablua doesn't ask.

## Why split it this way

**Each model does what it is good at.** Language models read situations and write code well. A tabular model learns patterns from many labelled examples well. Asking one model to do all of it means it does some of it badly.

**The record says who did what.** Because each model writes its own columns, you can measure each one on its own. Was Jev's 0.8 right 80% of the time? Did TabPFN's ranking predict progress better than Jev's confidence? The answers are queries over the table. Tablua's calibration report is one of them.

**Speed and cost stay sensible.** Measured from 368 traced calls in Tablua's desktop app, the median call takes 0.20 s for Jev, 0.77 s for Mercury and 3.0 s for a TabPFN prediction on a cached fit. TabPFN is the slowest and has a daily budget, so Tablua asks it only where it helps. See [Turn learning on](/guides/learning-modes).

## Swapping a model

Each model is reached through a small port in `core/ports`, a Lua module with one or two functions. The decision model and the writer can each be replaced for a comparison: a run can put another model from OpenRouter in Mercury's place, or another decision model in Jev's. The tables don't change, which is what makes the comparison fair.

## Next

[How Tablua learns](/concepts/learning) shows what TabPFN learns from, and how its estimates reach a decision.
