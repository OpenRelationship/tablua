---
description: Drive Tablua's step loop from your own Lua host - give it a world, the models, and play the person's part.
---

# Run an agent in your host

This guide drives the whole step loop (`core/agent`) from your own Lua program: Jev decides each step, Mercury writes what a step needs, and your world does the work. For recording rows and ranking moves without the loop, see [Embed the harness in Lua](/guides/embed).

## What you need

- The [Quickstart](/start/quickstart) set up, and a Lua VM: LuaJIT, Lua 5.4 or 5.5, or another.
- API keys for the models:

| Model | Variable | Where to get it |
| --- | --- | --- |
| Jev | `OPENROUTER_API_KEY` | [openrouter.ai](https://openrouter.ai) |
| Mercury | `INCEPTION_API_KEY` | [inceptionlabs.ai](https://www.inceptionlabs.ai) |
| TabPFN (optional) | `PRIORLABS_API_KEY` | [priorlabs.ai](https://priorlabs.ai) |

## 1. The ports

The ports reach the models through an HTTP client the host supplies. `ports.curl` is one for LuaJIT; on another runtime, pass any `{ fetch, now }` of your own.

```lua
package.path = "core/?.lua;core/?/init.lua;" .. package.path
local curl = require("ports.curl")
local host = { fetch = curl.fetch, now = curl.now }
local jev = require("ports.jev").new(host, { key = os.getenv("OPENROUTER_API_KEY") })
local mercury = require("ports.mercury").new(host, { key = os.getenv("INCEPTION_API_KEY") })
```

## 2. A world

A world is a table. It lists the tools, asks Jev's question, says what both models read, and does a tool's verb on your computer:

```lua
local world = {
  tools = { { name = "run_test", what = "Run the tests." }, { name = "write_code", what = "Change the code." } },
  question = function()
    return { kind = "choice", text = "What should the agent do next?",
      options = { run_test = "Run the tests.", write_code = "Change the code.", answer = "The work is done." } }
  end,
  state = function(_, req, for_jev) return "Task: " .. req.text .. "\n" .. my_facts() end,
  think = function(_, req) return { system = "Think the todo through.", user = req.text } end,
  ask = function(_, req) return { system = "Write one question for the person.", user = req.text } end,
  form = function(written) return { question = written } end,
  act = function(_, req, verb, step)
    local result = my_computer(verb)          -- your computer does the move
    step.lines[#step.lines + 1] = result.summary
    step.outcome = result.outcome             -- "complete", "broken" or "no_effect"
  end,
}
```

`my_facts` and `my_computer` are yours: the facts as text, and the move done on whatever computer you run.

## 3. Drive the loop

The loop is a state machine you step. Nothing in it yields, so the same code runs on a Lua with no coroutines.

```lua
local agent = require("agent")
local a = agent.new({ jev = jev, mercury = mercury }, world)
local req = a:begin("Make a page that lists my plants.")

while true do
  local next = a:step(req)                   -- Jev decides
  if next[1] == "done" then print(next[2] or "done") break end
  local step = next[2]
  local out = a:perform(req, step)           -- the agent's own verb, or the world's act
  if out and out[1] == "ask" then
    a:answered(step, out[2], { value = io.read() })   -- the person's part
  end
  a:close(req, step)                         -- recorded, and learned from
  if out and out[1] == "done" then break end
end
```

`perform` returns `nil` when the step is over, `{ "ask", form }` when the agent asks the person, `{ "wait", what }` when it waits on the world, and `{ "done", said }` to end the request.

## 4. Record and learn

Give the agent a `learn` (from `agent.learn`, over a `tablua` file) in the first argument to `agent.new`, and each step's TabPFN ranking reaches Jev after failed steps. Write each step's rows as [Embed the harness in Lua](/guides/embed) shows, from your world's `act`, so the next run has them to learn from.

## Next

- [The step loop](/concepts/step-loop)
- [Turn learning on](/guides/learning-modes)
