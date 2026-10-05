---
description: Module 9. One whole step from start to finish, touching every piece of the course, and a map of every table in an agent's file.
---

# 9. Putting it together

## One step, every piece

Here is a single step of the plants app, with every idea from the course in its place. The agent has 1 of 3 scenarios passing, and the failing one is "water a plant".

1. **Look (the host, Module 2).** The host reads the agent's computer: the feature is agreed, 1 of 3 scenarios pass, the failure is `When I press "Water" for "Fern": no button "Water"`. It writes the **state** row: `stage=building passed=1 total=3 stalls=0`.
2. **Breaks first (Module 5).** The app's org file is cut into rows. The `tablua_break` view finds nothing broken in the links, so no break is added to the facts.
3. **Moves allowed (Modules 3 and 8).** The `building` stage allows about a dozen moves. Each gate in force is checked; none holds anything back right now. The allowed moves become **candidate** rows.
4. **Jev decides (Module 6).** Jev reads the facts and answers with a probability per move: `fix_failure 0.71, write_page 0.18, think 0.11`. It also says where it thinks the cause is: `the_page`.
5. **TabPFN ranks (Module 7).** There are 300 labelled past steps in this agent's file and the shared file, so TabPFN is asked. It gives `fix_failure` a 0.64 chance of progress here. These fill `p_progress`.
6. **The decision (Module 2).** `fix_failure` is chosen and written as the **decision** row, `by=jev`.
7. **Mercury writes (Modules 4 and 5).** Mercury is told the move, the facts and the cause, and makes the calls: it edits one unit of `ui/index.org`, the page, adding a Water button that posts to `post.water`. Each call is an **action** row.
8. **Check (Module 3).** The computer runs the scenarios (Gherkin lines matched to Lua steps, using the real page). Now 3 of 3 pass.
9. **Outcome (Module 2).** The host writes the **outcome**: `complete`, `passed=3 total=3`, `progress=1`. The stage is now `ready`.
10. **Learn (Module 7).** TabPFN's prediction for this step is now scored (it said 0.64, and the step helped). This step becomes a labelled training row for every future decision.

Then the loop starts again from a new state row.

## The map of an agent's file

{{diagram:file}}

| Group | Tables | Holds |
| --- | --- | --- |
| The work | `tablua_state`, `tablua_candidate`, `tablua_decision`, `tablua_action`, `tablua_outcome`, `tablua_run` | Every step and every run |
| What it learns from | `tablua_label`, `tablua_effect`, `tablua_feature`, `tablua_fit`, `tablua_prediction`, `tablua_ranking` | Hindsight, effects, Jev's answers, TabPFN's fits and predictions |
| The program | `tablua_section`, `tablua_unit`, `tablua_scenario`, `tablua_line`, `tablua_link` (and the `tablua_break` view) | The app as rows |
| Policy | `tablua_gate` | The rules in force |
| On a desktop | `tablua_control` | The on-screen controls a step chose among |

Every table name starts with `tablua_`, and the harness writes only to those. The rest of the file belongs to the agent's log and its computer.

## What you now know

- An **agent** is a model in a loop; a **harness** runs the loop and keeps the record.
- Tablua keeps the record as **typed rows** in one SQLite file per agent.
- **Gherkin** scenarios say what done means and give every step an honest score.
- **Lua** is the harness's language: what the agent writes is any language its computer runs.
- **Org** holds an app in one readable file, cut into rows the harness can check and edit.
- **Jev** decides, **Mercury** writes, **TabPFN** learns, and the **host** checks.
- **Learning** is a SQL query plus a tabular model, scored against what happened.
- **Rules** are data, each with a reason, retired as learning takes over.

## Where to go next

- Try it: [Quickstart](/start/quickstart) writes rows with nothing but LuaJIT.
- See every column: [Tables](/reference/tables).
- Go deeper: [How Tablua learns](/concepts/learning), [The program as rows](/concepts/program-as-rows), [Policy as data](/concepts/policy-as-data).
- Read real data: [Read an agent's file with SQL](/guides/query).
