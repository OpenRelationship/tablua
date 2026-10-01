# 🌿 Moss

The agent's own computer, inside the BEAM (Arock PROJECT.md §14). Every agent gets a computer of its own: a
process per agent, its disk one SQLite file, a shell of Moss's own, a headless browser, mail between computers
that Jev reads, and one language, Lua, run on the BEAM by tv-labs `lua` with the computer as its library (files,
the web under its rules, JSON, mail). Everything is Elixir and Lua: no WebAssembly, no native code an agent can
reach. Each Lua run is a process of its own, bounded in instructions, memory, output and time. A person watches
a computer and the post on pages behind a sign-in.

Moss is attached to the Arock repository at `submodules/moss`, and reads Arock Core's Lua (the Jev port, and alog, the log) from that repository's `library/` and
`submodules/alog`; `AROCK_ROOT` names another checkout.

```
mix setup
mix test                                  # mix test --only service adds a real round trip through arock.ai
mix run bench/computers.exs 20000 400     # how many computers a node holds, and what each costs (measure on Linux)
MOSS_PAGE_TOKENS=me:<a long secret> mix phx.server   # then /computers/<id> and /mail
```

- `lib/moss/computer.ex`, `computer/`: one GenServer per computer (wake from its disk, sleep to the object
  store); `script.ex` and `priv/lua/computer.lua` are `lua` and its library; `shell.ex` and `commands.ex` are the shell;
  `page.ex`, `browser.ex` and `net.ex` are the browser and the web rules; `mailbox.ex` is `mail`.
- `lib/moss/mail.ex`, `mail/`: the post: routes, free checks, Jev's batched reading, letters held for a person.
- `lib/moss/lua.ex`, `lua/`, `priv/lua/`: Arock Core in tv-labs `lua`, its ports bound per call (`arock.*`).
- `lib/moss/objects*`: where sleeping computers live: Arock's service, by this node's own token, or a directory.
- `lib/moss_web/`: sign-in (`auth.ex`), the computer page and the post's page.
