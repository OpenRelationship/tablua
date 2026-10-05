---
description: A short course that teaches Tablua from nothing - what an agent harness is, why it keeps everything as tables, and how Lua, Gherkin and org each fit in.
---

# Learn Tablua: the course

This course explains Tablua from the ground up, one idea at a time. You don't need to know anything about agents, machine learning, Lua, Gherkin or org mode before you start. Each module introduces one idea, shows a small example, and ends with what to remember.

If you already know what Tablua is and want to use it, the [Quickstart](/start/quickstart) is faster. This course is for understanding why each piece exists and how the pieces connect.

## The modules

| # | Module | You will learn |
| --- | --- | --- |
| 1 | [An agent is a loop](/learn/loop) | What an AI agent does, and what a harness adds around it |
| 2 | [Writing it down as rows](/learn/rows) | Why Tablua records every step as rows in tables, and the tables for one step |
| 3 | [Gherkin: saying what "done" means](/learn/gherkin) | How the agent turns a person's words into tests before it builds anything |
| 4 | [Lua: the one language](/learn/lua) | Why everything the agent writes is Lua: its code, its tests and its pages |
| 5 | [Org: one file holds it all](/learn/org) | How an app lives in one readable file, and how that file becomes rows |
| 6 | [Three models, three jobs](/learn/models) | Who decides, who writes and who learns, and why each is a different model |
| 7 | [Learning from the past](/learn/learning) | How past rows become training data, and how predictions guide the next step |
| 8 | [Rules as data](/learn/rules) | How the harness's rules are written down, checked and retired |
| 9 | [Putting it together](/learn/together) | One whole step end to end, and a map of every table |

Each module takes about five minutes to read. Read them in order the first time: each one builds on the one before.

## The one-sentence version

Tablua is a harness that runs an AI agent one step at a time and writes everything about each step (where the work stood, what it could do, what it did, and how that turned out) as typed rows in one SQLite file, so that a model built for tables can learn from those rows which moves work.

By the end of the course, every word in that sentence will make sense.

## Next

Start with [Module 1: An agent is a loop](/learn/loop).
