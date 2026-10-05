This is Tablua (see README.md): the embeddable agent harness, in native Lua. Tablua is the harness and nothing else
(owner, 2026-10-04): the agent's own computer, Moss, is its own repository (OpenRelationship/moss, with moss-lua,
moss-browser, Shroomi, uspx and arock-log), and Arock is the app of Moss and Tablua.

## Tablua rules

- Tablua is attached to the Arock repository at `submodules/tablua` and to Moss at `tablua/`. Its Lua is `core/`:
  the harness (`tablua`, `agent`) and the model ports (`ports`); read `core/AGENTS.md` before editing there.
- Lua is the harness, not the output (owner, 2026-10-05): the agent's work may be in any language its computer
  runs. The harness itself is portable Lua, embedded through whatever Lua VM a host has, and reaches the world only
  through the ports the host supplies. No WebAssembly, no native code.
- `site/` is tablua.com, the one place TypeScript, React and Node tooling are allowed (owner, 2026-10-04). Nothing
  the harness runs reaches it.
- Files stay under 400 lines, split by responsibility. No placeholder modules.
- Keys and tokens (model keys, page tokens) are never logged, printed or written to files.
