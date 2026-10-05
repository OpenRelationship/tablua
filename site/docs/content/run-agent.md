---
description: Run Tablua's own agent on a Moss computer from Elixir - give it a task, play the person's part, and read what it did.
---

# Run an agent on its computer

This guide runs Tablua's own agent, the one that builds small apps, on a Moss computer, with all three models.

> [!IMPORTANT]
> Today a full agent run needs two small Lua modules from **uspx**, Tablua's post between agents, which is not public yet. Until it is, the harness itself runs from a public clone (see the [Quickstart](/start/quickstart) and [Embed the harness in Lua](/guides/embed)), and this guide describes the run for when uspx is published or for those who have it. [Status and roadmap](/reference/status) tracks it.

## What you need

- **Elixir 1.15 or newer**, with Erlang/OTP
- API keys for the three models:

| Model | Variable | Where to get it |
| --- | --- | --- |
| Jev | `OPENROUTER_API_KEY` | [openrouter.ai](https://openrouter.ai) |
| Mercury | `INCEPTION_API_KEY` | [inceptionlabs.ai](https://www.inceptionlabs.ai) |
| TabPFN (optional) | `PRIORLABS_API_KEY` | [priorlabs.ai](https://priorlabs.ai) |

## 1. Set up

```sh
git clone https://github.com/OpenRelationship/tablua.git
cd tablua
mix setup
mix moss.look          # fetches the browser's page-reading module
```

## 2. Start a computer

```sh
iex -S mix
```

```elixir
Moss.Computer.run("plants", "ls")
```

A computer named `plants` now exists, with its own SQLite file. Its name can be lower-case letters, digits and dashes.

## 3. Give the agent a task

```elixir
ask = "I'd like a little app for my house plants. It should list each plant with when I last " <>
      "watered it, let me add a plant, and let me mark one as watered today."

Moss.Computer.Agent.run("plants", ask)
```

The agent takes steps until it finishes, stops, or needs you. It returns a map:

```elixir
%{outcome: "waiting", why: "waiting for ...", steps: 2, counts: %{"jev" => 2, "mercury" => 1, ...}}
```

`outcome` is one of `done`, `blocked`, `waiting`, `stopped` or `error`.

## 4. Play the person's part

The agent never agrees to its own feature or approves its own publish. Those are yours.

**Agree to the feature** it wrote, after reading it:

```elixir
Moss.Computer.run("plants", "cat features/plants.feature").out |> IO.puts()
Moss.Computer.agree("plants", "features/plants.feature")
```

Then run the agent again. It picks up where it stopped:

```elixir
Moss.Computer.Agent.run("plants", ask)
```

**Say yes to publishing** when it asks. The log shows the request the agent made; answer it with the same line:

```elixir
Moss.Computer.answer("plants", line, true)
```

To automate the person's part, for example in a test, pass a function as `between:`. It is called with the computer's id after every step.

## 5. Read what it did

Every step is in the computer's file as Tablua rows. Locally, a computer's file is `priv/work/computers/<id>.sqlite`:

```sh
sqlite3 priv/work/computers/plants.sqlite "select n, chosen, by from tablua_decision"
```

The queries in [Read an agent's file with SQL](/guides/query) work on it directly.

## Options

`Moss.Computer.Agent.run/3` takes these options:

| Option | What it does |
| --- | --- |
| `learn: "shadow"` or `"rank"` | how TabPFN's estimates are used ([Turn learning on](/guides/learning-modes)) |
| `gates_off: "stuck_fix,give_up"` | switch gates off for this run ([Retire a gate](/guides/gate-ab)) |
| `edits: "rows"` | Mercury changes one unit of a file at a time ([The program as rows](/concepts/program-as-rows)) |
| `max_steps: 150` | stop after this many steps |
| `between: fn id -> ... end` | called after each step: the person's part, in a test |
| `filler:` / `decider:` | another model in Mercury's or Jev's place, for a comparison |

## Next

- [The step loop](/concepts/step-loop)
- [Turn learning on](/guides/learning-modes)
