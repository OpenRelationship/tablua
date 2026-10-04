# Tablua

An embeddable agent and its own computer. Tablua keeps everything an agent is and does as tables in one SQLite
file: where the work stands, every move it could make with each model's numbers, the move taken and by whom, how
the step turned out, and every run's ending. A TabPFN model learns from those rows which moves make progress;
Jev's probabilities are its features; Mercury writes the cells that need prose or code. Policy is data too: the
gates and moves are rows. The host that runs an agent is a stateless stepper over its file.

Tablua is three parts, in this repository:

- **the harness**, the Continual Tabular Agent Harness: the `tablua_*` tables and the agent's step loop
  (`priv/lua/world/`; the table library and the agent core are moving in from Arock's `library/`);
- **🌿 Moss** (VMOSS), the agent's personal computer, below;
- **🍄 Shroomi** (`shroomi/`), how the agent publishes its work on that computer: pages and apps a person opens.

Arock (the Mac and iPhone apps, and the server that runs thousands of computers) is built on Tablua.
The site is at [tablua.com](https://tablua.com) (`site/`). Licensed under Apache-2.0.

## 🌿 Moss, the computer

The agent's own computer, its operating system on the BEAM (Arock PROJECT.md §14). Every agent gets a computer
of its own: a process per agent, its disk one SQLite file, a shell of VMOSS's own, a headless browser, a mailbox,
and one language, Lua, run on the BEAM with the computer as its library (files, the web under its rules, JSON,
mail). Everything is Elixir and Lua: no WebAssembly, no native code an agent can reach. Each Lua run is a
process of its own, bounded in instructions, memory, output and time. VMOSS and Moss name the same thing; the
Elixir modules are `Moss.*`.

VMOSS is a library. Whoever runs computers is their host (`Moss.Host`): on its own (`Moss.Host.Local`) a
computer sleeps where it is, has no post and takes its model keys from the environment; Arock's server
(`app/server` in the Arock repository, `ArockServer.Host`) keeps them in its object store, carries their mail
and serves the pages a person watches them on.

For now Tablua is attached to the Arock repository at `submodules/vmoss`, and reads the rest of the core's Lua
from that repository: the model ports and arock-log from its `library/`, uspx from its submodules; `AROCK_ROOT`
names another checkout. Shroomi is this repository's own `shroomi/`.

```
mix setup
mix test
mix run bench/computers.exs 20000 400     # how many computers a node holds, and what each costs (measure on Linux)
mix moss.look                             # fetch moss-browser's look module, the release pinned in config
```

- `lib/moss/computer.ex`, `computer/`: one GenServer per computer (wake from its disk, sleep through its host);
  `script.ex` and `priv/lua/computer.lua` are Lua and its library; `shell.ex` and `commands.ex` are the shell;
  `browser.ex` and `net.ex` are the browser and the web rules; `mailbox.ex` is `mail`.
- `lib/moss/host.ex`, `host/`: what a computer asks of whoever runs it, and the host it has on its own.
- `lib/moss/lua.ex`, `lua/`, `priv/lua/`: Arock Core in moss-lua, its ports bound per call (`arock.*`).
- `lib/moss/computer/session.ex`: the session kept after every command.
- `lua/`: moss-lua, our fork of tv-labs `lua`, the Lua VM on the BEAM (its own AGENTS.md).
- `browser/`: moss-browser, the browser engine (its own AGENTS.md).
- `shroomi/`: Shroomi, pages and apps as `.lui` files (its own README and AGENTS.md).
- `site/`: tablua.com.
