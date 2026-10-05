---
description: Follow one agent through a few steps of building a small app, and see each row Tablua writes and who writes it.
---

# A tour of one step

This page follows an agent building a small app, step by step, and shows each row it writes. You don't need to run anything. The values are illustrative, but the shape of every row is exactly Tablua's.

## The task

A person asks: *"I'd like a little app for my house plants. It should list each plant with when I last watered it, let me add a plant, and let me mark one as watered today."*

The agent builds apps the way a careful developer does. First it writes the person's ask as test scenarios, in Gherkin. Once the person agrees to them, it writes the code, the test steps and the pages until every scenario passes, then asks the person before publishing.

## Step 1: write the feature

**Where the work stands.** Before anything is decided, the host writes a `state` row from facts it can check: there is no feature file yet.

```text
state      n=1  stage=no_feature  passed=0/0  stalls=0
```

**What could be done.** In the `no_feature` stage only a few moves are allowed. Jev is asked to pick one and gives a probability for each. Each option becomes a `candidate` row.

```text
candidate  write_feature  jev_p=.82
```

**What was done, and by whom.**

```text
decision   chosen=write_feature  by=jev
action     write features/plants.feature  (4 scenarios)        ← written by Mercury
outcome    complete  progress=1  passed=0/4                     ← checked by the host
```

The feature now exists, with four scenarios that all fail, because there is no code yet. That is expected. The step still counts as progress: it did its job.

## Step 2: write the test steps

The person agrees to the feature. Now the stage is `building`, and many more moves are allowed. This time TabPFN has past rows to learn from, so each candidate also gets `p_progress`: TabPFN's estimate of the chance that this move makes progress here.

```text
state      n=2  stage=building  passed=0/4  last=write_feature
candidate  write_steps  jev_p=.61  p_progress=.52
candidate  write_page   jev_p=.27  p_progress=.31
candidate  rewrite      jev_p=.12  p_progress=.07
decision   chosen=write_steps  by=jev  propensity=1
action     write code/steps/plants.lua  (38 lines)
outcome    complete  progress=1  passed=2/4
```

Two of four scenarios pass. Jev and TabPFN agreed on the best move, and the outcome bears them out.

## Step 3: a step that makes things worse

```text
state      n=3  stage=building  passed=2/4  last=write_steps
candidate  rewrite  jev_p=.55  p_progress=.09
decision   chosen=rewrite  by=jev
action     rewrite code/plants.lua  (52 lines)
outcome    broken  progress=0  passed=1/4  regressed=1
```

Jev was fairly sure about `rewrite`. TabPFN, having seen how rewrites in this stage tend to go, gave it a 9% chance. The rewrite broke a scenario that was passing. The outcome row records it plainly: `regressed=1`.

This is the kind of disagreement the table makes visible. Over many runs, rows like this show whether Jev's confidence or TabPFN's estimate deserves more trust in which situations. Tablua can be set to act on that. See [Turn learning on](/guides/learning-modes).

## Step 4: undo

After a regression, the `undo` move becomes available. It puts back the files the last change wrote.

```text
state      n=4  stage=building  passed=1/4  last=rewrite
decision   chosen=undo  by=jev
outcome    complete  progress=1  passed=2/4
```

## Steps 5 and 6: finish and publish

```text
state      n=5  stage=building  passed=2/4  last=undo
candidate  write_page  jev_p=.70  p_progress=.66
decision   chosen=write_page  by=jev
action     write ui/index.org  (61 lines)
outcome    complete  progress=1  passed=4/4

state      n=6  stage=ready  passed=4/4  pages_ok=1
decision   chosen=publish  by=jev
run        shipped=1  works=1  steps=6
```

All four scenarios pass, so the stage becomes `ready` and `publish` is allowed. Publishing waits for the person's yes. The `run` row records how the whole run ended.

## What to notice

- **Facts come from the host, choices from the models.** The stage, the pass counts and the regression are measured. No model is asked whether its own work succeeded.
- **Every option is recorded, not just the one taken.** That is what lets a model later learn what would likely have happened with the others.
- **Who decided is recorded.** `by=jev` or `by=tabpfn`. When you learn from your own decisions, knowing who made them, and how likely the choice was, keeps you honest about cause and effect.
- **Every step is labelled for free.** `progress` is worked out from the rows themselves, so the agent's own work becomes training data without anyone writing labels.

## Next

Try it yourself in the [Quickstart](/start/quickstart), or read [The step loop](/concepts/step-loop) for the full picture.
