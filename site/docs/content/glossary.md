---
description: Plain definitions of the words used across Tablua's docs.
---

# Glossary

**Action.** One call a move made, such as writing a file or running a command. A `tablua_action` row.

**Agent.** A program that works toward a goal in steps, choosing what to do at each one. In Tablua, an agent is its rows and its computer, in one file.

**A/B.** Running the same tasks two ways, for example with a gate on and with it off, and comparing the outcomes.

**Candidate.** A move that could be made at a step. Every candidate is recorded, not only the one taken.

**Cause.** Where Jev judged the last failure to be: the steps, the app's code, the page, a library call, the feature, or unclear.

**Computer.** Wherever the agent's code is written, run and tested. The host supplies it as the world the step loop acts on.

**Decision.** The move taken at a step, who took it, and how likely the choice was.

**Effect.** A keyword for something a step changed, such as `More Passing` or `Page Broke`, from a closed list.

**Experience, shared.** A file of Tablua rows from many agents' finished runs, which each agent reads beside its own.

**Feature (Gherkin).** The person's ask written as test scenarios in plain language: *Given*, *When*, *Then*.

**Feature (column).** A number describing a step that a model can learn from, such as Jev's answer to "does the ask involve dates?"

**Fit.** TabPFN reading a training table, ready to predict. One fit serves many predictions.

**Gate.** A named rule that holds one move back in one situation, with a stated reason.

**Harness.** The code that runs an agent: its tables, its step loop, and the code that decides which model is asked what.

**Head.** One question TabPFN can be asked about a step, with its own label: `progress`, `ship`, `contrib`, or an effect.

**Hindsight label.** After a run, Jev's judgement of whether each step contributed to the final app. Used for training only.

**Host.** The program that runs an agent. It writes the facts (state and outcome) and supplies what the agent can't reach itself.

**Jev.** The decision model. It picks the next move, with a probability for each option.

**Label.** The answer a training row carries, such as whether the step made progress.

**Mercury.** The writing model. It fills in a chosen move: code, test steps, pages.


**Move.** One kind of thing the agent can do, such as `write_code` or `publish`. Also called a verb.

**Org.** A plain-text file format with headings, drawers and source blocks. An app's file in Tablua is org.

**Outcome.** How a step turned out: `complete`, `broken`, `no_effect` or `denied`, with its progress label.

**Progress.** A step's label: 1 if it helped, by a fixed rule over the rows, else 0.

**Propensity.** How likely a choice was under the policy that made it. Needed to learn fairly from your own decisions.

**Rank mode.** TabPFN decides when its best move clearly leads and Jev is unsure.

**Row.** One record in a table, with fixed columns.

**Run.** One task, from the first step to the end. Its ending is a `tablua_run` row.

**Shadow mode.** TabPFN's estimates are recorded at every decision but never used.

**Stage.** Where the work stands, worked out from facts: `building`, `ready` and so on.

**State.** The facts at a step, before deciding. A `tablua_state` row.

**TabPFN.** A tabular foundation model from Prior Labs. It learns from a table of examples in one pass, with no training run.

**Task.** What the agent was asked to do. The key that joins a run's rows.

**Unit.** One top-level piece of a program: a function, an action, a scenario, a page.
