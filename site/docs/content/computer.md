---
description: The computer the agent's code runs on - what a host gives the harness, and why it should be contained and cheap.
---

# The agent's computer

The harness decides and records; it doesn't do the work itself. The work happens on a **computer**: wherever the agent's code is written, run and tested. Tablua never names one. The host that embeds the harness supplies it, as the world the step loop acts on.

## What the harness needs from it

The step loop asks a world for four things, all through plain Lua tables (see [Run an agent in your host](/guides/run-agent)):

- **The facts**: where the work stands, such as which tests pass and which keyword each failing one stopped at. They become the state row.
- **The moves**: the tools the agent may use there, each with a one-line description. They become the candidate rows.
- **An act**: doing what a move means on the computer, and saying how it went.
- **The rows' file**: a SQLite connection, `db:exec(sql, params) -> rows`, that holds the `tablua_*` tables.

Anything that can answer those is a computer to the harness: a sandbox, a container, a worker, a VM, or a person's own machine with their permission.

## Contained by design

What the agent can reach should be what the computer offers and nothing else. A host that keeps the agent's files, its commands and its tests inside one sandbox, and reaches other services only through ports under rules the person sets, can run agents it doesn't trust. The harness helps by keeping to its own tables: every name starts `tablua_`, so a host can give it a connection that reaches those tables and no others.

## One file per agent

The harness keeps an agent's whole history in one SQLite file. A host can keep the computer's own state in the same file: then copying the file copies the agent, its history and its work, and an agent that isn't working is a file at rest. Nothing in the loop yields or blocks, so a host can wake an agent, take one step and put it back to sleep.

## Next

To use the harness from your own code, see [Embed the harness in Lua](/guides/embed). To drive the whole loop with a world of your own, see [Run an agent in your host](/guides/run-agent).
