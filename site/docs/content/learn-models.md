---
description: Module 6. The three models in Tablua - one that decides, one that writes and one that learns - and why each job gets its own model.
---

# 6. Three models, three jobs

## Why not one big model?

Many agents use one large model for everything: deciding, writing code and judging the result. Tablua splits the work into three jobs and gives each to a model built for it. Each one is faster and cheaper at its job, and each one's contribution lands in its own columns, so you can measure it.

## The three

| Model | Its job | Kind of model | What it writes |
| --- | --- | --- | --- |
| **Jev** | Decides the next move | Typed decisions: answers a question with a probability for every option | `jev_p` on each candidate row |
| **Mercury** | Writes what the move needs: code, steps, pages | A fast code-writing language model | The files, recorded as action rows |
| **TabPFN** | Predicts which moves tend to make progress | A tabular foundation model: learns from rows, no training run needed | `p_progress` on each candidate row |

And a fourth party that isn't a model at all: **the host**, which writes the state and outcome rows from real checks.

## How a decision is made

At each step:

1. The host writes the **state** row from facts.
2. The allowed moves for this stage become **candidate** rows.
3. **Jev** reads the facts and gives every candidate a probability. Its answers fill `jev_p`.
4. **TabPFN** looks at past rows and gives every candidate its chance of making progress. Its answers fill `p_progress`.
5. A move is chosen and written as the **decision** row, with `by` saying who chose it.
6. **Mercury** fills in the move: it writes the actual code, steps or page.
7. The host runs the checks and writes the **outcome**.

## Why Jev gives probabilities

Jev doesn't just name a move. It gives a probability for *every* option, like "fix_failure 0.71, write_page 0.18, think 0.11". Those numbers are useful twice:

- They are a decision: take the most likely move.
- They are **features**: columns TabPFN can learn from. If Jev's confidence turns out to be unreliable in some situations, TabPFN can learn that too.

## Why TabPFN

TabPFN is a model trained on millions of synthetic tables, so it can make predictions from a new table immediately, with no training run of its own. You give it rows with known answers and rows you want answers for, and it returns probabilities. For an agent that has only a few hundred past steps, this is exactly right: no data science project, just "here are past steps and how they went, how will these new options go?"

## Keeping the jobs honest

Each model only ever sees what it should:

- TabPFN learns only from columns known *before* the decision, so it can't cheat by seeing the outcome.
- The facts in the state row come from the host, so no model grades its own work.
- Mercury writes only what its move allows. If it tries to change something another move owns (for example the feature, which only `write_feature` may change), the computer refuses, and the refusal is written down for the next step.

## Remember

- **Jev** decides, with a probability per option; **Mercury** writes the files; **TabPFN** predicts progress from past rows.
- The **host** writes the facts and checks, never a model.
- Every model's opinion lands in its own column, so each can be measured.

## Next

How do past rows become TabPFN's predictions? [Module 7: Learning from the past](/learn/learning)
