# volvox-server

The Elixir host for [Volvox](submodules/volvox): it runs the Volvox core in tv-labs `lua`, the Colm
suite as WebAssembly under Wasmex, and one SQLite file per run, and shows a run live in Phoenix
LiveView. Local only; there is no remote and no deploy config.

```
git submodule update --init --recursive   # Volvox, and its monomono (for mono.spec in the tests)
mix setup
mix test                                  # mix test --only r2 adds a real R2 round trip
mix phx.server                            # then /runs/<id>
```

The Colm modules come from the Volvox repo's build (`just build-script suite`, which writes
`~/volvox/.cache/volvox/suite/*.wasm`); set `VOLVOX_SUITE` to use another directory.

- `lib/volvox_server/lua.ex`, `lua/`: the base Lua state (core modules loaded, kept in
  `:persistent_term`) and the host ports bound per call: db, clock, now, sleep, fetch, colm, key.
- `priv/lua/`: `require` over the sources, and `host.lua`, the glue the host calls (`volvox.*`).
- `lib/volvox_server/run.ex`, `run/`: one GenServer per run: wake, start_task, step, append, sleep.
- `lib/volvox_server/objects*`: where sleeping runs live: R2 (wrangler's OAuth token) or a directory.
- `lib/volvox_server/colm.ex`: one Wasmex instance per suite module, recycled like `suite.runner`.
- `lib/volvox_server_web/live/run_live.ex`: the run page.
- `test/fixtures/outline/`: the LuaJIT side of the Colm parity test, and the script that writes it.
