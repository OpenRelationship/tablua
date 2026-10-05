---
description: Module 1. What an AI agent actually does, step by step, and what a harness is.
---

# 1. An agent is a loop

## What an agent is

A language model on its own answers one message and stops. An **agent** is a language model put in a loop, with tools it can use, so it can work on a todo over many steps until the todo is done.

Every agent, however it is built, repeats the same five things:

1. **Look.** Where does the work stand right now?
2. **Choose.** What should I do next?
3. **Act.** Do it: write a file, run a test, open a page.
4. **Check.** Did that help?
5. **Remember.** Keep what happened, so the next step knows.

Then it goes back to step 1. The loop ends when the todo is done, when the agent is stuck and says so, or when it runs out of steps.

## What a harness is

The model does the choosing and some of the acting. Everything else is the **harness**: the program around the model that runs the loop. The harness:

- gathers the facts the model looks at (which tests pass, which files exist),
- offers the moves the model may choose from,
- carries out the move and runs the checks,
- decides when the loop stops,
- and keeps the record of what happened.

A useful way to think about it: the model is the driver, and the harness is the car, the road and the rules of the road.

## A tiny example

Say a person asks for "a little app to track my house plants". Here are the first few turns of the loop:

| Step | Look | Choose | Act | Check |
| --- | --- | --- | --- | --- |
| 1 | No plan for the app exists | Write down what the app must do | Writes a test description | The person agrees to it |
| 2 | Tests exist, none pass | Write the code | Writes the code | 1 of 3 tests pass |
| 3 | 1 of 3 pass, "Water button missing" | Fix that failure | Adds the button | 3 of 3 pass |
| 4 | Everything passes | Publish | Asks the person | They say yes |

Nothing here is magic. Each step is a small decision made from facts, followed by a check that a program (not a model) does.

## What usually goes wrong

Most agents keep their memory as a **transcript**: a long chat log of everything said and done. That works for a few steps, but it has problems:

- It gets long, and the model reads less of it carefully.
- It is text, so you can't easily ask "how often does fixing the same error twice work?"
- The agent's rules ("don't publish until tests pass") live in a prompt, where nobody can measure whether they help.

Tablua's answer to all three is the subject of the next module.

## Remember

- An agent is a model in a loop: look, choose, act, check, remember.
- The **harness** is everything around the model: facts, moves, checks, stopping and the record.
- Tablua is a harness. Its big idea is how it keeps the record.

## Next

[Module 2: Writing it down as rows](/learn/rows)
