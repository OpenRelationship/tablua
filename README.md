# 🌿 VMOSS

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

VMOSS is attached to the Arock repository at `submodules/vmoss`, and reads Arock Core's Lua (the Jev port,
arock-log and arock-mail) from that repository's `library/`; `AROCK_ROOT` names another checkout.

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
