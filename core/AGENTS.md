# Core

Tablua's Lua: the harness (`tablua`, the agent's work as typed rows; `agent`, the decide-and-act loop; `robot`,
the agent's tests in Robot Framework's syntax, parsed and run in Lua with every keyword's result kept as rows; `term`,
the agent's terminal: a shell session driven by keystrokes, its screens read into rows, foreseen by a world model) and the
model ports (`ports`: Jev, Mercury, chat, see, search, TabPFN, and `ports.sqlite`, a LuaJIT host's database). A host
reads it as Lua modules by name (`core/tablua/source.lua` is `tablua.source`).

## Rules

- One folder per domain, each with a `library.md` (front matter for skill generation). A module's tests sit beside
  it as `<module>_test.lua`, written with Tablua's own `spec` (`test/spec.lua`) and run by `luajit test/run.lua`.
  No build system: no BUCK, no nomimono (owner, 2026-10-05).
- Portable Lua: it runs unchanged on LuaJIT, Lua 5.4/5.5, Luerl and any other Lua VM a host embeds. No FFI except in host
  files that say so (`ports.sqlite`, `ports.curl`), which a host without FFI leaves out and supplies itself; no `goto`, `//` or `utf8`.
- No host's names: nothing here names a product built on Tablua. A host's own ports and stores live with the host.
- Consumers depend on targets, never on file paths across domains. 400 lines a file at most.
- Do not add a domain until two real modules have nowhere else to go.
