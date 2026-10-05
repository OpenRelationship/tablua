---
description: The stages of Tablua's app-building agent, the moves allowed in each, and what each move does.
---

# Stages and moves

The stages and moves of the app-building agent Tablua is measured with. If you embed the harness, you can use your own.

## Stages

The stage is worked out by code, from facts, in this order:

| Stage | When |
| --- | --- |
| `answered` | the task has been answered |
| `changing` | the app shipped before this task, which asks to change it |
| `shipped` | the app is published, the task not yet answered |
| `awaiting_yes` | publishing waits for the person's yes |
| `no_feature` | no feature has been written yet |
| `awaiting_agreement` | a feature is written and the person hasn't agreed to it |
| `building` | something still fails: a scenario, a missing step, a page |
| `ready` | every scenario passes and every page answers |

## Moves allowed in each stage

| Stage | Moves |
| --- | --- |
| `no_feature` | `write_feature`, `read_help`, `think`, `blocked` |
| `awaiting_agreement` | `wait_for_agreement`, `write_feature`, `think`, `blocked` |
| `building` | `undo`, `write_feature`, `write_steps`, `write_code`, `write_page`, `run_test`, `run_check`, `fix_failure`, `rewrite`, `look_at_app`, `read_help`, `think`, `plan`, `next_part`, `blocked` |
| `ready` | `publish`, `undo`, `look_at_app`, `fix_failure`, `rewrite`, `write_page`, `run_test`, `think`, `blocked` |
| `awaiting_yes` | `wait_for_yes` |
| `changing` | `write_feature`, `write_page`, `write_code`, `write_steps`, `read_help`, `think`, `blocked` |
| `shipped` | `answer_task`, `think`, `blocked` |
| `answered` | `answer` |

Gates can hold some of these back in particular situations ([Policy as data](/concepts/policy-as-data)).

## What each move does

| Move | What it does |
| --- | --- |
| `write_feature` | writes the person's ask, in their words, as Gherkin scenarios |
| `wait_for_agreement` | waits for the person to agree to the feature |
| `write_steps` | writes the Lua steps that check each scenario against the app's real behaviour |
| `write_code` | writes the app's code and its database |
| `write_page` | writes or fixes the app's pages |
| `run_test` | runs the feature's tests |
| `run_check` | checks the pages and code for problems |
| `fix_failure` | fixes what the last test, check or page named as failing |
| `undo` | puts back the files the last change wrote; offered only after a change broke what passed |
| `rewrite` | writes the failing file again whole |
| `look_at_app` | opens the app as the person will, and uses it |
| `read_help` | reads the computer's help on a kind of file or a command |
| `publish` | publishes the app, for the person's yes |
| `wait_for_yes` | waits for that yes |
| `answer_task` | answers the task with a letter naming what shipped and where |
| `answer` | the task is answered; the run ends |
| `think` | goes over the task and the steps so far, and says what is wrong and what to do next |
| `plan`, `next_part` | splits a larger task into parts, and moves to the next |
| `blocked` | stops and reports that the agent's own tools keep failing |

## Causes

When a step fails, Jev is also asked where the problem most likely is. The answer is the state's `cause` column:

| Cause | Meaning |
| --- | --- |
| `the_steps` | a test step doesn't match its line, or checks the wrong thing |
| `the_app_code` | the app's code or database does the wrong thing |
| `the_page` | the page doesn't compile, or its action or markup is wrong |
| `a_library_call` | a call into the computer's library was made the wrong way |
| `the_feature` | the feature as written can't pass; changing it needs the person's agreement again |
| `unclear` | it can't be told from what is shown |
