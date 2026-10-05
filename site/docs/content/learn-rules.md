---
description: Module 8. How Tablua writes its rules (gates) as checkable tests, why each rule carries its reason, and how rules are retired as learning takes over.
---

# 8. Rules as data

## Why an agent needs rules

Left alone, agents fall into loops. They fix the same failure again and again, read the help over and over, or rewrite a page that was already right. Every harness adds rules to stop this. Usually those rules live inside a prompt as sentences like "don't fix the same error twice". Nobody can tell whether a rule still helps, so rules pile up.

## Gates

In Tablua a rule is a **gate**: it holds one move back in one situation. Gates are written once, as tasks in Robot Framework's syntax, each with its **reason**:

```robot
*** Test Cases ***
Fixing the same failure again waits on thinking it through
    [Documentation]    because: fix_failure | 2+ stalls | Same Keyword Failing | more
    [Tags]    gate:stuck_fix
    Given Same Failure after 2 changes running
    When the last move was not think
    Then fix_failure is not offered
```

Read it as: *after two changes that left the same failure, don't offer `fix_failure` again until the agent has stopped to think.* The `because` line in its documentation is a claim the harness can check against recorded runs: after 2 or more stalls, fixing again leads to "Same Keyword Failing" more often.

When a run starts, the gates in force are written as `tablua_gate` rows, so every run records which rules it ran under.

## Some gates in plain words

| Gate | Holds back |
| --- | --- |
| `stuck_fix` | fixing the same failure again, until the agent thinks |
| `think_twice` | thinking twice in a row (it changes nothing) |
| `help_twice` | reading the help twice in a row |
| `publish_looked` | publishing before the app was actually used since it changed |
| `give_up` | after many stalls, everything but a rewrite, changing the tests, stopping or publishing |
| `blocked_trouble` | saying "I'm blocked" when nothing is actually wrong, or before testing a change |

Some rules aren't policy at all but facts about what a move can do (you can only undo a change that broke something). Those are marked fixed and never turned off.

## Stalls

Many gates count **stalls**: steps in a row that changed nothing. A step stalls when the same failure remains, when no more tests pass, or, when nothing is failing, when the work is still in the same stage for the same reason. The count is a column in the state row (`stalls`), so gates and TabPFN both see it.

## Retiring a gate

Every gate but the fixed ones can be turned off for a run. To find out whether a gate still earns its place, Tablua runs an **A/B test**: the same tasks with the gate on and with it off. If turning it off doesn't make things worse, the gate is retired.

The evaluation also checks every gate's `because` line against the effects recorded across all runs. A gate whose reason doesn't hold is the first candidate for retiring.

The aim is for the hand-written rules to shrink over time, as the learned model (Module 7) takes over the judgement they used to encode.

## Remember

- A gate holds one move back in one situation; gates are written as Robot tests with a reason.
- The gates in force are rows in every run, so their effect can be measured.
- Stalls (steps that changed nothing) trigger many gates.
- Gates are retired one at a time through A/B tests, as learning takes over.

## Next

[Module 9: Putting it together](/learn/together)
