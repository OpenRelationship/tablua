---
description: Module 3. How the agent turns a person's ask into Robot Framework tests before writing any code, how those tests run, and how every keyword's result becomes rows.
---

# 3. Robot: saying what "done" means

## The problem

"A little app for my house plants" is vague. Before an agent writes a line of code, someone has to decide what "done" looks like. If nobody does, the agent can't check its own work, and the person can't tell whether they got what they asked for.

## Robot Framework in one minute

**Robot Framework** is a format for tests made of keywords. A test is a name and a list of keyword calls, one per line. Each call is a keyword's name followed by its arguments, with cells set apart by two or more spaces:

```robot
*** Settings ***
Test Setup    Open    /

*** Test Cases ***
Add a plant
    Type    Plant name    Fern
    Press    Add
    See    Fern

Water a plant
    There is a plant Fern
    Press For    Water    Fern
    See For    watered today    Fern
```

- `*** Settings ***` holds what every test shares, here a setup that opens the page first.
- `*** Test Cases ***` holds the tests. A line at the left margin names a test; the indented lines under it are its calls.
- `Type    Plant name    Fern` calls the keyword `Type` with two arguments: the field and what to type.

A test can also call keywords written in the same file, under `*** Keywords ***`. Such a **user keyword** is a list of calls with a name, and it can take arguments:

```robot
*** Keywords ***
Add Plant
    [Arguments]    ${name}
    Type    Plant name    ${name}
    Press    Add
```

Robot also has variables (`${name}`), `FOR` and `IF` blocks, setup and teardown, and a library of common keywords called BuiltIn (`Should Be Equal`, `Should Contain`, `Evaluate` and the rest). A call may start with `Given`, `When`, `Then`, `And` or `But`; Robot ignores the word. That's most of what Tablua uses.

Tablua used Gherkin before schema 12 and moved to Robot (owner, 2026-10-05) because the models, not people, read and write the tests, and Robot's tree of keywords shows how far a test got where Gherkin gave one flat line.

## How the agent uses it

The agent's first move on any todo is `write_tests`: it turns the person's words into tests like the ones above. Then it **waits for the person to agree**. Only after they agree does building start.

From then on, the tests are the definition of done:

- The harness runs them and counts how many pass.
- "1 of 3 tests pass" in the state row is exactly this count.
- The app can only be published when every test passes.

## Keywords: connecting words to code

A call like `There is a plant Fern` is just words. To run it, something has to say what it means. That's a **keyword**: a user keyword written in Robot, or a small piece of Lua the agent writes with `keyword`:

```lua
keyword("There is a plant ${name}", function(name)
  plants.add(name)
end)
```

`${name}` in the keyword's name is an embedded argument: it matches part of the call and hands it to the function as `name`. When a test runs, each call is matched to a keyword in this order: the file's user keywords, then the Lua keywords, then BuiltIn's.

The page's keywords (`Open`, `Type`, `Press`, `Press For`, `See`, `See For`, `See Before`, `Do Not See`) are already defined by the agent's computer. They use the real page in a real browser engine, so a passing test means a person could really do it.

## Every keyword's result is a row

Tablua runs the tests itself, in portable Lua (`core/robot`), and keeps the result of every keyword of every test run: its place in the tree, its arguments, whether it passed, failed, was skipped or never ran (`PASS`, `FAIL`, `SKIP`, `NOT RUN`), the message, and how long it took. These are `tablua_result` rows.

For a failing test the harness also keeps its **reach**: how many keywords passed before it failed. A step that leaves the test failing but further along has still moved it, and the rows show that.

## Tasks: doing again what worked

A test checks a job; a **task** does one. Robot writes tasks under `*** Tasks ***`, in the same keyword language, run the same way (this is what Robot calls RPA, robotic process automation):

```robot
*** Tasks ***
Plant the usual
    Open    /
    Add Plant    Fern
    Add Plant    Ivy
```

Tasks are Tablua's own idea, not a host's. They sit in the same Tests section as the tests, each under a `** Task:` heading in the org file, and each is a `tablua_test` row of kind `task`. A change block adds, replaces or removes one with `%% task`.

- **Made from what worked.** `robot.record(test)` writes a passing test's run as a task: the keywords it called, in the order they ran, with the values they had. What took the models many steps to get right becomes one routine.
- **Run with no model deciding.** `robot.run(suite, { rpa = true })` runs the tasks instead of the tests. Each run's keyword tree is kept like a test's, its own row typed `task`.
- **Checked by their record.** `tablua_task_record` keeps each task's runs, how many passed, and the keyword it fails at most. A task that keeps passing is a move worth offering; one that keeps failing at the same keyword is that keyword to mend, not the whole task to redo.

## Tests set the stages

Because the tests are so central, the stage of the work (a column in the state row) is worked out from them:

| Stage | Means |
| --- | --- |
| `no_tests` | No tests yet: write them |
| `awaiting_agreement` | Written, waiting for the person's yes |
| `building` | Agreed; some tests don't pass yet |
| `ready` | Every test passes and every page answers |
| `awaiting_yes` | Asked the person to publish |
| `shipped` | Published |

Each stage allows only certain moves. You can't publish while `building`, and you can't write code before there are agreed tests.

## Why this matters for learning

Tests give every step an honest score that doesn't depend on any model's opinion: the count of passing tests before and after, and for each failing test the keyword it failed at and its reach. That count is what tells Tablua whether a step made **progress**, which is the label it learns from (Module 7).

## Remember

- Robot Framework describes behaviour as tests made of keyword calls.
- The agent writes the tests first; the person agrees before building starts.
- Keywords connect a test's words to checks: user keywords in Robot, library keywords in Lua, and the page's keywords from the computer.
- Every keyword's result is a row; passing tests set the stage and score each step, with no model involved.
- A task is a test that does a job; a passing test can be recorded as one and run again with no model deciding, and its record says whether to trust it.

## Next

On a computer that runs Lua, keywords are Lua, as is everything else the agent writes there. [Module 4: Lua](/learn/lua)
