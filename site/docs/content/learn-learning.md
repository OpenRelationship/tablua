---
description: Module 7. How Tablua turns past steps into training data with a SELECT, how TabPFN ranks the next moves, and how agents learn from each other's runs.
---

# 7. Learning from the past

## The question

Every step, the agent faces the same kind of question: *given where the work stands, which move is most likely to help?* Tablua answers it by looking at how similar steps went before.

## Step 1: label each past step

To learn, you need examples with answers. In Tablua, the answer for a past step is its **progress** label, worked out from the outcome row:

- **1 (helped)** if more tests passed after the step, or the step completed and wasn't a change that went nowhere;
- **0 (didn't help)** otherwise.

No model decides this label. It comes from the test counts in Module 3.

## Step 2: a training set is a SELECT

Because everything is already in tables, a training set is just a query. Each past step becomes one row: the columns known before the decision (stage, tests passing, stalls, last move, cause, the move considered, Jev's probability) and its label.

```text
stage     passed  stalls  last_verb    cause      move          jev_p  | progress
building  1/3     0       write_code   the_page   fix_failure   0.71   | 1
building  1/3     2       fix_failure  the_page   fix_failure   0.64   | 0
building  1/3     2       fix_failure  the_page   think         0.20   | 1
ready     3/3     0       look_at_app  -          publish       0.88   | 1
```

The second and third rows show the kind of thing it learns: when fixing the same failure has already stalled twice, thinking first tends to work better than fixing again.

## Step 3: ask TabPFN

At a new step, the harness builds one row per candidate move (the current state plus that move) and asks TabPFN for each one's chance of progress. The answers fill the `p_progress` column on the candidate rows, and the candidates are ranked.

A few practical rules keep it cheap and sensible:

- **It waits for enough history.** TabPFN is only asked once there are at least 12 labelled steps, with at least 3 that helped and 3 that didn't.
- **One fit serves many predictions.** The training set is sent once and cached; it is refreshed after 25 new labelled steps.
- **Seen states are free.** A state it already ranked gets the same ranking again without a call.
- **There's a budget.** Each run may ask a limited number of times, and the day's total stays under the service's free tier.

If TabPFN can't be asked (no history yet, budget spent, service unreachable), the agent simply goes on with Jev alone. Learning helps; it is never required.

## Step 4: every prediction is scored

Each prediction is saved (`tablua_prediction`). When the step it was for finishes, its outcome says whether the prediction was right. So you can always check how well the learning is doing, as a number, from the rows.

## Shared experience

One agent's past is small. Many agents' pasts are big. When a run ends, its rows are copied into a **shared file** on the machine, with each task renamed so runs don't mix. The next agent attaches that file and learns from every agent before it. A brand-new agent with no history of its own still starts with one.

## Other things it learns

Progress is the main question, but the same machinery answers others, each called a **head**:

| Head | Question |
| --- | --- |
| `progress` | Did this step help? |
| `ship` | Did its run end with an app that works? |
| `contrib` | Looking back at the whole run, did this step contribute? |
| `effect:<name>` | Did a particular effect follow (for example `Test Turned Green`)? |

## Remember

- Each past step is labelled helped or not, from the test counts.
- A training set is a SQL query over the rows; TabPFN predicts from it with no training run.
- Predictions are budgeted, cached and scored.
- Agents share experience through one shared file, so new agents start informed.

## Next

Learning shapes choices. But some choices are held back by rules. [Module 8: Rules as data](/learn/rules)
