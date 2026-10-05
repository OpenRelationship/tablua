---
description: Tablua is an agent harness that keeps everything an agent is and does as typed rows in one SQLite file, so a tabular model can learn from them which moves make progress.
---

# What is Tablua?

Tablua is an AI agent that keeps everything it is and does in tables. Every situation it was in, every move it could have made, the move it chose, who chose it and how it turned out is a typed row in one SQLite file. A tabular model reads those rows and learns which moves make progress.

Most agents keep their history as text: a long prompt, a chat log, or notes in a vector store. Tablua keeps it as data with columns. That one choice changes what you can do with an agent. You can query it, measure it, and teach it from its own record, the way you would with any other dataset.

{{diagram:loop}}

## What Tablua is made of

Tablua has two parts that work together:

- **The harness.** The part that runs the agent: its tables, its step loop, and the code that decides when each model is asked what. The harness is portable Lua. You can embed it in your own program, and it runs unchanged on LuaJIT, standard Lua and any other Lua VM.
- **The computer.** Wherever the agent's code is written, run and tested. The host that embeds the harness supplies it, and can keep it in the same SQLite file as the agent's tables.

These docs are mostly about the harness, because that is where Tablua differs most from other agents.

## Three models, each with one job

Tablua uses three models, and none of them does another's job:

| Model | Its job | What it writes |
| --- | --- | --- |
| **Jev** | Decides the next move, with a probability for each option | candidate and decision rows |
| **TabPFN** | Learns from past rows which moves make progress | each move's chance of progress |
| **Mercury** | Writes what the chosen move needs: code, tests, pages | action rows |

The host, the program that runs the agent, writes the rest: where the work stands and how each step turned out. Those facts come from running checks, never from a model's opinion. [Three models, one table](/concepts/three-models) explains why it is split this way.

## Where to start

- **New to Tablua?** Read [Why an agent as tables](/start/why-tables), then take [A tour of one step](/start/tour). Neither needs code.
- **Want to try it?** The [Quickstart](/start/quickstart) writes your first rows in about five minutes, with LuaJIT and nothing else.
- **Want to understand how it learns?** Read [How Tablua learns](/concepts/learning) and [Shared experience](/concepts/shared-experience).
- **Looking something up?** The [Reference](/reference/tables) lists every table, column, move and function.

> [!NOTE]
> Tablua is open source under the Apache-2.0 license, and in active development. [Status and roadmap](/reference/status) says what works today, what has been measured, and what is still being built.
