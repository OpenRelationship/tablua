# 🌿 Moss

The agent's own computer, inside the BEAM (Arock PROJECT.md §14). Every agent gets a computer of its own: a
process per agent, its disk one SQLite file, a shell of Moss's own, a headless browser, mail between computers
that Jev reads, and one language, Lua, run on the BEAM by tv-labs `lua` with the computer as its library (files,
the web under its rules, JSON, mail). Everything is Elixir and Lua: no WebAssembly, no native code an agent can
reach. Each Lua run is a process of its own, bounded in instructions, memory, output and time. A person watches
a computer and the post on pages behind a sign-in.

Moss is attached to the Arock repository at `submodules/terrarium`, and reads Arock Core's Lua (the Jev port, and arock-log, the log) from that repository's `library/` and
`submodules/arock-log`; `AROCK_ROOT` names another checkout.

```
mix setup
mix test                                  # mix test --only service adds a real round trip through arock.ai
mix run bench/computers.exs 20000 400     # how many computers a node holds, and what each costs (measure on Linux)
mix run --no-start bench/packs.exs load 1000 300   # the node's packs under load, with the real Litestream
deploy/fly/stage.sh && fly deploy         # the test node on Fly (deploy/fly/; benches through deploy/fly/bench.sh)
MOSS_PAGE_TOKENS=me:<a long secret> mix phx.server   # then /computers/<id> and /mail
```

- `lib/moss/computer.ex`, `computer/`: one GenServer per computer (wake from its disk, sleep to the object
  store); `script.ex` and `priv/lua/computer.lua` are `lua` and its library; `shell.ex` and `commands.ex` are the shell;
  `page.ex`, `browser.ex` and `net.ex` are the browser and the web rules; `mailbox.ex` is `mail`.
- `lib/moss/mail.ex`, `mail/`: the post: routes, free checks, Jev's batched reading, letters held for a person.
  The rules are arock-mail's (Arock's `submodules/arock-mail`, Lua run through `arock.mail`); Moss keeps the letters.
- `lib/moss/lua.ex`, `lua/`, `priv/lua/`: Arock Core in tv-labs `lua`, its ports bound per call (`arock.*`).
- `lib/moss/objects*`: where sleeping computers live: Arock's service, by this node's own token, or a directory.
  Asleep, a computer is its whole file (`objects/snapshot.ex`); awake, Litestream streams it to the node's replica
  and the packer puts every awake computer's new segments in one pack a minute (`objects/packer.ex`). A computer
  awake longer than `snapshot_ms` (4 hours) is cut where it is (`computer/keeping.ex`), so its old packs go.
- `lib/moss/computer/session.ex`: the session kept after every command, tried again while Litestream holds the file.
- `deploy/fly/`: the Linux image (Moss, Litestream, the Arock sources it reads) and its node settings: `+SDio 1024`
  (SQLite and file calls queue on the BEAM's dirty I/O threads at a thousand computers) and a raised open-file limit.
- `lib/moss_web/`: sign-in (`auth.ex`), the computer page and the post's page.
