# Core

Tablua's core Lua, moved here from Arock's `library/` (arock issue #1, M7, 2026-10-04): the harness (`tablua`, the
agent's work as typed rows; `agent`, the decide-and-act loop), the model ports (`ports`: Jev, Mercury, chat, see,
search, TabPFN, the service) and arock-log, the log (`arock-log`). Moss reads it from here (`Moss.Lua.Sources`);
Arock's desktop, iPhone app, server and scripts read it at `submodules/vmoss/core`.

## Rules

- One folder per domain, each with a `library.md` (front matter for skill generation) and a `BUCK`: the BUCK files
  are Arock's build graph (`//submodules/vmoss/core/<domain>`), where every module's `lua_test` runs.
- Portable Lua: it runs unchanged on LuaJIT, Lua 5.4/5.5, Luerl and moss-lua. No FFI except in host files that say
  so (`arock-log.ffi`, `ports.curl`), which Moss leaves out and supplies itself; no `goto`, `//` or `utf8`.
- Consumers depend on targets, never on file paths across domains. 400 lines a file at most.
- Do not add a domain until two real modules have nowhere else to go.
