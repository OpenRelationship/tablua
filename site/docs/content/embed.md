---
description: Use Tablua's harness from your own Lua program - record each step as rows, and let TabPFN rank the moves from them.
---

# Embed the harness in Lua

This guide shows how to use Tablua's harness in your own Lua program: record each step your agent takes as rows, and ask TabPFN to rank the next moves from those rows.

You'll need the [Quickstart](/start/quickstart) set up, and for the ranking, a Prior Labs API key.

## How the pieces fit

| Module | What it does |
| --- | --- |
| `tablua` | the tables: write a step's rows, read training sets |
| `agent.learn` | asks TabPFN to rank moves, from the `tablua` rows |
| `ports.tabpfn` | talks to Prior Labs' TabPFN API |
| `ports.sqlite` | SQLite for LuaJIT; on other Lua runtimes, supply any object with `db:exec(sql, params) -> rows` |

The harness is portable Lua: it runs unchanged on LuaJIT, Lua 5.4 and 5.5, and any other Lua VM. Only the SQLite binding and the HTTP client are specific to where it runs, and you can supply your own.

## 1. Open the agent's file

```lua
package.path = "core/?.lua;core/?/init.lua;" .. package.path
local sqlite = require("ports.sqlite")
local tablua = require("tablua")

local t = tablua.open(sqlite.open("agent.sqlite"))
```

`tablua.open` creates the tables if they don't exist. The file can already hold other tables; Tablua only touches its own, which all start with `tablua_`.

## 2. Record each step

For every step, write four things: where the work stood, the options, the choice and the outcome.

```lua
local function record(todo, n, state, options, chosen, by, result)
  state.todo, state.n = todo, n
  t:state(state)
  t:candidates(todo, n, options)
  t:decision{ todo = todo, n = n, chosen = chosen, by = by }
  return t:outcome{ todo = todo, n = n, verb = chosen, outcome = result.outcome,
    passed = result.passed, total = result.total }
end

record("ticket-1", 1,
  { stage = "building", passed = 0, total = 3, last_verb = "", stalls = 0 },
  { { move = "write_code", jev_p = 0.6 }, { move = "run_test", jev_p = 0.3 } },
  "write_code", "jev",
  { outcome = "complete", passed = 1, total = 3 })
```

`outcome` should be `complete`, `broken` or `no_effect`. `passed` and `total` are optional; when you give them, a step that makes more of them pass always counts as progress. `t:outcome` returns the step's progress label, 1 or 0.

When a run ends, record how it went:

```lua
t:run{ todo = "ticket-1", shipped = true, works = true, steps = 6 }
```

> [!TIP]
> Use your own stages and moves. Tablua doesn't require its app-building vocabulary. What matters is that they stay the same from run to run, so rows line up.

## 3. Rank the next moves

`agent.learn` fits TabPFN on your rows and ranks a list of moves for the current situation:

```lua
local curl = require("ports.curl")                -- an HTTP client for LuaJIT
local tabpfn = require("ports.tabpfn").new({ fetch = curl.fetch, now = curl.now },
  { key = os.getenv("PRIORLABS_API_KEY") })
local learn = require("agent.learn").new{ tablua = t, tabpfn = tabpfn }

local ranked, why = learn:rank("step",
  { stage = "building", pass = 1/3, stalls = 0, last_verb = "write_code", last_outcome = "complete", n = 2,
    todo = "ticket-1", at = 2 },
  { "write_code", "run_test", "write_page" })

if ranked then
  for _, r in ipairs(ranked) do print(r.name, r.p) end    -- best first
else
  print("no ranking:", why)                               -- for example, too few rows yet
end
```

- With fewer than 12 labelled rows, or fewer than 3 of either label, `rank` returns `nil` and says why. Keep going and record more steps.
- Each ranking is logged as `tablua_prediction` rows when you pass `todo` and `at`. `learn:record("step")` scores them once their outcomes land.
- One fit serves many rankings. A new fit happens after 25 new outcomes.

## 4. Use the ranking

How much weight to give the ranking is up to you. The pattern the harness's own checkpoints follow:

- show it to your decision model as evidence, after a couple of failed steps;
- record it without using it (shadow mode) until you have measured how good it is;
- then let it decide when it clearly leads and the decision model isn't sure.

Whatever you choose, record who decided in `by`. See [How Tablua learns](/concepts/learning).

## 5. Share rows between agents (optional)

To learn from other agents' rows, attach their file before ranking:

```lua
t:attach("shared", "experience.sqlite")
```

See [Shared experience](/concepts/shared-experience).

## Next

- [Read an agent's file with SQL](/guides/query)
- [Lua API reference](/reference/lua-api)
