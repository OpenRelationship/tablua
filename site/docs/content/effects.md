---
description: The closed vocabulary of effects Tablua records after each step - what changed in the tests, the pages, the commands and the stage.
---

# Effects vocabulary

After each step, the host records what changed, as keywords from this closed list. Each is a `tablua_effect` row. Some carry an argument, such as a page's path. Together they describe every step as *Given* a state, *When* a move, *Then* these effects, and each common effect can be a TabPFN head (`t:training("effect:<Keyword>")`).

Effects are written by the harness from what it measured, never by a model.

## The step itself

| Keyword | Meaning |
| --- | --- |
| `Step Complete` | the step did its job |
| `Step Broken` | the step left something broken |
| `Step No Effect` | the step changed nothing |
| `Step Blocked` | the agent said it was blocked |
| `Undone Next` | the next step undid this one |

## Tests

| Keyword | Meaning |
| --- | --- |
| `Tests First Ran` | the tests ran for the first time |
| `More Passing` | more tests pass |
| `Fewer Passing` | fewer tests pass |
| `All Green` | every test passes, and didn't before |
| `Regressed` | a test that passed fails now |
| `Same Failure` | the same failure as before the step |
| `Test Turned Green` | a test passes now (arg: its name) |
| `Test Turned Red` | a test fails now (arg: its name) |
| `Keyword Fixed` | a failing test's failing keyword passes now (arg: the keyword's kind) |
| `Failure Moved On` | a test still fails, at another keyword (arg: the new keyword's kind) |
| `Same Keyword Failing` | a test fails at the same keyword for the same reason (arg: the keyword's kind) |
| `Reached Further` | a failing test passed more keywords before failing than it did |
| `Fell Back` | a failing test passed fewer keywords before failing than it did |
| `Undefined Keywords` | calls no keyword answers |

A keyword's *kind* is which of the page's keywords it is: `open`, `type`, `press`, `press_for`, `see`, `see_for`, `see_before`, `not_see`, or `own` for a keyword of the app's own. A `Given`, `When` or `Then` before it is ignored.

`Reached Further` and `Fell Back` read a failing test's **reach**: how many keywords passed before it failed, from the test run's rows (`tablua_result`). A step that leaves a test failing, but further along, shows up here even when no more tests pass.

## Pages and commands

| Keyword | Meaning |
| --- | --- |
| `Page Broke` | a page answers 500 now (arg: its path) |
| `Page Fixed` | a page answers 200 now (arg: its path) |
| `Check Passed` | check found nothing wrong |
| `Check Failed` | check found something wrong |
| `Command Failed` | a command exited non-zero (arg: its name) |

## Stage and publishing

| Keyword | Meaning |
| --- | --- |
| `Stage Became` | the stage changed (arg: the new stage) |
| `Published` | the app was published |
