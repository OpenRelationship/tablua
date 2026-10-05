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
| `Tests First Ran` | the features ran for the first time |
| `More Passing` | more scenarios pass |
| `Fewer Passing` | fewer scenarios pass |
| `All Green` | every scenario passes, and didn't before |
| `Regressed` | a scenario that passed fails now |
| `Same Failure` | the same failure as before the step |
| `Scenario Turned Green` | a scenario passes now (arg: its name) |
| `Scenario Turned Red` | a scenario fails now (arg: its name) |
| `Line Fixed` | a failing scenario's failing line passes now (arg: the line's kind) |
| `Failure Moved On` | a scenario still fails, at a later line (arg: the new line's kind) |
| `Same Line Failing` | a scenario fails at the same line for the same reason (arg: the line's kind) |
| `Undefined Steps` | lines no step matches |

A line's *kind* is what it does in the app's own words: `open`, `type`, `press`, `see`, `not_see` and a few more, or `own` for a line in the agent's own words.

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
