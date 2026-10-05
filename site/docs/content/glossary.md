---
description: Plain definitions of the words used across Tablua's docs.
---

# Glossary

**Action.** One call a move made, such as writing a file or running a command. A `tablua_action` row.

**Agent.** A program that works toward a goal in steps, choosing what to do at each one. In Tablua, an agent is its rows and its computer, in one file.

**A/B.** Running the same todos two ways, for example with a gate on and with it off, and comparing the outcomes.

**Build, the.** What the agent is making: the files of the app, as rows keyed by file (`tablua_section`, `tablua_unit`, `tablua_test` and the rest). Rows are replaced as the files change. One of the three parts of an agent's file, with the log and the policy ([The log and the build](/concepts/log-and-build)).

**Change block.** An edit as a short script of operations on the build (`%% add`, `replace`, `delete`, `rename`, `test`, `keyword`, and on a page's elements `set`, `put`, `drop`, `move`, `wrap`, `unwrap`), made all or none, with the change that undoes it. Each operation is a `tablua_change` row in the log ([Change blocks](/concepts/program-as-rows#change-blocks)).

**Candidate.** A move that could be made at a step. Every candidate is recorded, not only the one taken.

**Cause.** Where Jev judged the last failure to be: the keywords, the app's code, the page, a library call, the tests, or unclear.

**Computer.** Wherever the agent's code is written, run and tested. The host supplies it as the world the step loop acts on.

**Decision.** The move taken at a step, who took it, and how likely the choice was.

**Effect.** A keyword for something a step changed, such as `More Passing` or `Page Broke`, from a closed list.

**Element.** One nested call of a page written as Lua (`ui.form{ ... }`), named by its path (`page/card/form`, `button[2]` for the second of a name). A change block can set, put, drop, move, wrap and unwrap elements; each is a `tablua_element` row in the build ([Page elements](/concepts/program-as-rows#page-elements)).

**Experience, shared.** A file of Tablua rows from many agents' finished runs, which each agent reads beside its own.

**Feature (column).** A number describing a step that a model can learn from, such as Jev's answer to "does the ask involve dates?"

**Fit.** TabPFN reading a training table, ready to predict. One fit serves many predictions.

**Gate.** A named rule that holds one move back in one situation, with a stated reason.

**Harness.** The code that runs an agent: its tables, its step loop, and the code that decides which model is asked what.

**Head.** One question TabPFN can be asked about a step, with its own label: `progress`, `ship`, `contrib`, or an effect.

**Hindsight label.** After a run, Jev's judgement of whether each step contributed to the final app. Used for training only.

**Host.** The program that runs an agent. It writes the facts (state and outcome) and supplies what the agent can't reach itself.

**Jev.** The decision model. It picks the next move, with a probability for each option.

**Keyword.** A named step of a test, in Robot Framework's sense: a user keyword written in Robot, a Lua function the agent declares with `keyword(...)`, one of BuiltIn's, or one of the page's (`Open`, `Type`, `Press`, `See`). A call no keyword answers is a break.

**Label.** The answer a training row carries, such as whether the step made progress.

**Log, the.** What the agent did: every state, candidate, decision, action, change and outcome, as rows keyed by run and step. Rows are only ever added. One of the three parts of an agent's file ([The log and the build](/concepts/log-and-build)).

**Mercury.** The writing model. It fills in a chosen move: code, tests, keywords, pages.


**Move.** One kind of thing the agent can do, such as `write_code` or `publish`. Also called a verb.

**Org.** A plain-text file format with headings, drawers and source blocks. An app's file in Tablua is org.

**Outcome.** How a step turned out: `complete`, `broken`, `no_effect` or `denied`, with its progress label.

**Policy, the.** How the next decision is made: the gates in force, TabPFN's fits and the rankings a run paid for. Keyed by neither step nor file. One of the three parts of an agent's file.

**Progress.** A step's label: 1 if it helped, by a fixed rule over the rows, else 0.

**Propensity.** How likely a choice was under the policy that made it. Needed to learn fairly from your own decisions.

**Rank mode.** TabPFN decides when its best move clearly leads and Jev is unsure.

**Reach.** How many keywords of a failing test passed before it failed. A step that leaves a test failing but further along raises it (`Reached Further`).

**Result.** One keyword of one test run, with its status (`PASS`, `FAIL`, `SKIP` or `NOT RUN`), message and time. A `tablua_result` row.

**Robot Framework.** The syntax an agent's tests are written in: tests and tasks as lists of keyword calls. Tablua parses and runs it in portable Lua (`core/robot`).

**Row.** One record in a table, with fixed columns.

**Run.** One todo, from the first step to the end. Its ending is a `tablua_run` row.

**Shadow mode.** TabPFN's estimates are recorded at every decision but never used.

**Stage.** Where the work stands, worked out from facts: `building`, `ready` and so on.

**State.** The facts at a step, before deciding. A `tablua_state` row.

**TabPFN.** A tabular foundation model from Prior Labs. It learns from a table of examples in one pass, with no training run.

**Task.** A test that does a job rather than checks one, written under `*** Tasks ***`: the same keyword calls, run the same way, its run kept as `tablua_result` rows. A `tablua_test` row of kind `task`; its record over every run is `tablua_task_record`.

**Test.** One test case in Robot Framework's syntax: a name and the keyword calls it makes. The tests say what done means; how many pass is the state's `passed`. A `tablua_test` row.

**Todo.** What the agent was asked to do: org's word for a thing to be done. The key that joins a run's rows (the `todo` column), so that "task" means only a Robot task.

**Unit.** One top-level piece of a program: a function, an action, a Lua keyword, a page.
