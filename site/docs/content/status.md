---
description: What works in Tablua today, what has been measured, and what is still being built.
---

# Status and roadmap

Tablua is in active development. This page says what works today, what has been measured, and what is still being built. It is updated as that changes.

## Works today

- **The harness** (`core/`): the tables, the step loop, the learning (`agent.learn`), the program as rows and unit edits. It runs from a public clone on LuaJIT, Lua 5.4 and 5.5, and on any Lua VM a host embeds, and it has its own tests.
- **Recording every step** as typed rows, with no text parsing: state, candidates, decision, actions, outcome, effects and the run's ending.
- **Learning from the rows** with TabPFN, in evidence, shadow and rank modes, under a daily budget.
- **Shared experience** between the agents on one node.
- **Gates as named rows**, each stated as a Robot test with a measurable reason, switchable for an A/B.
- **Tasks**: a test that does a job rather than checks one (Robot's `*** Tasks ***`), recorded from a passing test, run with no model deciding, and kept with its record over every run.
- **The program as rows**: org files that round-trip byte for byte, edits to one unit, and links and breaks as data.
- **Hosts that drive the loop.** A host drives the step loop through its own world and records every step in the same rows.

## Measured so far

- **Progress is predictable from the rows.** An offline study of 4,515 steps of app building found whether a step makes progress predictable from the move and where the work stood: AUROC 0.82 on todos the model hadn't seen. The same study found Jev overconfident in the building stage. Rank mode is the test of acting on that.
- **Gates checked against the record.** Of the first eight gates measured, one held (undo after a regression), one didn't (thinking before fixing again after two stalls: 44% against a 38% base rate), and the rest had too few steps to tell or no effect that speaks to their reason.
- **Model speed.** Median call times from 368 traced calls: Jev 0.20 s, Mercury 0.77 s, a TabPFN prediction 3.0 s.

## Being measured

- **The evaluation protocol.** Twelve todos, four held out, several seeds and rephrasings each, with the code frozen. It reports whether apps ship, work and do what was asked, how many steps they took, what they cost, and the gain from shared experience with its confidence interval.
- **TabPFN deciding.** Rank mode against Jev alone: as many apps shipped and working, in fewer steps.
- **Unit edits.** Editing one unit at a time against writing whole files: fewer rewrites and steps, with outcomes no worse.
- **Breaks.** How many failed runs the break views catch before tests run. So far, fewer than the target.

## Next

- Retire gates one at a time through A/Bs, and move behaviour that was hand-written to what was learned.
- Use the ship head to stop runs early once it has been shown to hold over time.
- Decoders for other file formats (CSV, JSON, Markdown, SQL), so more of an app is rows.
- Retire the older tagged page format (`.lui`) once pages written as Lua hold up in the evaluation.

## Following along

The code is at [github.com/OpenRelationship/tablua](https://github.com/OpenRelationship/tablua). Issues and pull requests are welcome.
