# arock-log

The append-only log under Arock and Moss. Read `library.md` for what it does and the contract a host calls.

## Rules

- Record every action as a Robot keyword with string arguments; give it a fold only if it changes the state.
  A keyword a host relies on is declared in `kinds.lua`, with its arguments in order.
- Content goes to `blobs` by id (a `*` argument), never as an argument itself, so the log and the Robot rows stay
  small and a body is kept once.
- Undo by logging an Undo, never by touching rows; the triggers refuse changes to the log (events, args, blobs,
  loads).
- Keep no state that cannot be rebuilt from the log; `rebuild()` must reproduce it exactly, from a snapshot or
  from the start. A change to the state's shape bumps `schema.version`, so `open` drops and refolds it; the log's
  tables only ever gain.
- Never checkpoint, VACUUM or leave WAL from arock-log: Litestream owns the file's checkpoints (`alog.LITESTREAM`).
- Portable Lua only in the core (no FFI, `goto`, `//` or `utf8`) and SQL for SQLite. `ffi.lua` is the test host's
  port: core code never requires it.
- 400 lines per code file. Every module is covered by a `*_test.lua` that passes on LuaJIT (buck2) and in tv-labs
  `lua` (Moss's gate0); a test that needs real files skips its file checks where the host gives only memory.
