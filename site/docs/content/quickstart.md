---
description: Write your first agent rows with Tablua's harness in about five minutes, using LuaJIT and SQLite.
---

# Quickstart

In this quickstart you write one step of an agent's work as Tablua rows, read back the training row a model would learn from, and open the file with SQLite. It takes about five minutes.

You don't need any API keys for this. You are using the harness directly, the same code the agent uses, without the models.

## Before you start

You need:

- **Git**
- **LuaJIT** (`brew install luajit` on macOS, `apt install luajit` on Debian or Ubuntu)
- **SQLite**, which macOS and most Linux systems already have. The `sqlite3` command line tool is handy for looking at the file.

## 1. Get the code

```sh
git clone https://github.com/OpenRelationship/tablua.git
cd tablua
```

The harness is the `core/` folder. It is plain Lua with no dependencies beyond SQLite.

## 2. Write a step

Create a file called `try.lua` in the `tablua` folder:

```lua
package.path = "core/?.lua;core/?/init.lua;" .. package.path
local sqlite = require("ports.sqlite")   -- SQLite for LuaJIT
local tablua = require("tablua")

local t = tablua.open(sqlite.open("agent.sqlite"))

-- where the work stood when the agent decided
t:state{ todo = "plants", n = 1, stage = "building", passed = 0, total = 4 }

-- every move it could have made, with Jev's probability for each
t:candidates("plants", 1, {
  { move = "write_keywords", jev_p = 0.61 },
  { move = "write_page",     jev_p = 0.27 },
})

-- the move it took, and who took it
t:decision{ todo = "plants", n = 1, chosen = "write_keywords", by = "jev" }

-- how it turned out: two of four tests pass now
local progress = t:outcome{ todo = "plants", n = 1, verb = "write_keywords",
  outcome = "complete", passed = 2, total = 4 }
print("progress:", progress)

-- what a tabular model would learn from
local train, labels = t:training("progress")
print("columns:", table.concat(train.columns, ", "))
print("row:", table.concat(train.rows[1], " | "), "label:", labels[1])
```

## 3. Run it

```sh
luajit try.lua
```

> [!TIP]
> If it says `no SQLite library found`, tell it where SQLite is: on Debian or Ubuntu, either `apt install libsqlite3-dev` or run `TABLUA_SQLITE=/usr/lib/x86_64-linux-gnu/libsqlite3.so.0 luajit try.lua`.

You should see something like this:

```text
progress:	1
columns:	move, stage, pass, stalls, last_verb, last_outcome, cause, own_checks, n, jev_p, jev_margin, ask_dates, ...
row:	write_keywords | building | 0 | 0 |  |  |  | 0 | 1 | 0.61 | -1 | ...	label:	1
```

Three things happened:

1. **The outcome was labelled for you.** More tests pass than before, so `progress` is 1. You didn't write that label; Tablua worked it out from the state and the outcome.
2. **The step became one training row.** The move, where the work stood, and Jev's probability, with the label beside it. Missing numbers are `-1`.
3. **Everything is in `agent.sqlite`.**

## 4. Look at the file

```sh
sqlite3 agent.sqlite "select todo, n, chosen, by from tablua_decision"
```

```text
plants|1|write_keywords|jev
```

List every table Tablua made:

```sh
sqlite3 agent.sqlite ".tables"
```

These are ordinary SQLite tables. Any tool that reads SQLite can read an agent's history.

## What's next

- [A tour of one step](/start/tour) shows a full run, row by row.
- [Embed the harness in Lua](/guides/embed) adds the learning: TabPFN ranking the moves from rows like these.
- [Read an agent's file with SQL](/guides/query) has useful queries for a real agent's file.
- [Run an agent in your host](/guides/run-agent) drives the whole loop from your own Lua, models and all.
