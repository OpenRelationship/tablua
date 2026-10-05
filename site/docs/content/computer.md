---
description: Moss, the computer each Tablua agent gets - its disk, shell, browser and mailbox, all in one SQLite file, run on the BEAM.
---

# The agent's computer

Each Tablua agent gets a computer of its own, called **Moss**. The agent builds and runs its apps there, and the computer, like the agent's tables, lives in one SQLite file.

You don't need Moss to use the harness: the harness is portable Lua and can drive any world you give it. But Moss is where Tablua's own agent works, and it is built to suit the harness.

## What the computer has

- **A disk**: files and folders, stored as rows in the computer's SQLite file.
- **A shell**: commands such as `ls`, `cat`, `test` and `check`, answered by Moss itself. It is not a shell on the host machine.
- **One language, Lua**: the agent's apps, test steps and pages are Lua, run with the computer's own library (files, a database, dates, pages, mail, the web under its rules).
- **A browser**: so the agent can open its app and use it as a person would.
- **A mailbox**: agents talk to each other and to people only by mail.

## Contained by design

Everything an agent can reach is inside its computer. Nothing it does touches the host's real files, a real shell, or another computer. Each Lua run is a separate process with limits on instructions, memory, output and time. There is no WebAssembly and no native code an agent can reach: Moss is Elixir and Lua, and the Lua runs on the BEAM, the virtual machine Erlang and Elixir run on.

When an agent needs something outside, such as another service's API, it goes through a port the host provides, under rules the person sets.

## One file, many computers

Because a computer is one SQLite file, it is cheap. A computer that isn't working is just a file at rest. When work arrives it wakes in milliseconds, takes its step and can sleep again. One machine can hold a large number of computers this way.

The agent's tables (`tablua_*`), the log of everything that happened (`events` and `args`) and the computer's own files all sit side by side in the same file. Copying the file copies the agent, its history and its work.

## The host

Moss is a library. Whatever runs the computers is their **host**, and it supplies what a computer can't provide for itself: where its file is kept while it sleeps, how mail is delivered, the model keys. On its own, Moss uses a simple local host that keeps computers on disk and reads model keys from the environment. A server can supply its own host to run computers for many people.

## Next

To use the harness from your own code, see [Embed the harness in Lua](/guides/embed). To run Tablua's own agent on a computer, see [Run an agent on its computer](/guides/run-agent).
