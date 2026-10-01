# Moss

The agent's own computer, inside the BEAM (Arock PROJECT.md §14). Every agent gets a computer of its own: a
process per agent, its disk one SQLite file, its programs WebAssembly modules (Python, JavaScript, Lua, SQLite,
Ruby, C and C++, Zig, Go) whose system calls Moss answers in Elixir, a shell of Moss's own, a headless browser,
and mail between computers that Jev reads. A person watches a computer and the post on pages behind a sign-in.

Moss is attached to the Arock repository at `submodules/moss`, and reads Arock Core's Lua (the Jev port, the
store) from that repository's `library/`; `AROCK_ROOT` names another checkout.

```
just build-script computer                # in the Arock repo: the programs and their /usr
mix setup
mix test                                  # mix test --only r2 adds a real R2 round trip
mix run bench/computers.exs 20000 400     # how many computers a node holds, and what each costs (measure on Linux)
MOSS_PAGE_TOKENS=me:<a long secret> mix phx.server   # then /computers/<id> and /mail
```

- `lib/moss/computer.ex`, `computer/`: one GenServer per computer (wake from its disk, sleep to the object
  store); `wasi.ex`, `files.ex` and `paths.ex` answer WASI preview 1; `programs.ex` compiles each program once
  per node; `clang.ex` and `go.ex` drive the compilers' steps; `shell.ex` and `commands.ex` are the shell;
  `page.ex`, `browser.ex` and `net.ex` are the browser and the web rules; `mailbox.ex` is `mail`.
- `lib/moss/mail.ex`, `mail/`: the post: routes, free checks, Jev's batched reading, letters held for a person.
- `lib/moss/lua.ex`, `lua/`, `priv/lua/`: Arock Core in tv-labs `lua`, its ports bound per call (`arock.*`).
- `lib/moss/objects*`: where sleeping computers live: R2 (wrangler's OAuth token) or a directory.
- `lib/moss_web/`: sign-in (`auth.ex`), the computer page and the post's page.
