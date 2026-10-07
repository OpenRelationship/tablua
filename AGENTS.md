This is Tablua (see README.md): the embeddable agent harness, in native Lua. Tablua is the harness and nothing else
(owner, 2026-10-04): it knows no host. A host embeds it in its own Lua VM and gives it a computer and the ports
it reaches the world through; nothing here names one.

## Tablua rules

- Tablua is outfitted for Moonsplice (owner, 2026-10-06): its world is building games and videos as Lua comps, and
  its rows, columns and learner are shaped for that world. This narrows "knows no host" above: Moonsplice's words
  (comp, gate, critic, frame) may name Tablua's columns and docs; Moonsplice's own code and stores still live in
  Moonsplice. TabICL runs locally, in Moonsplice's binary through Candle (reached as host.tabicl), never on a hosted
  service. `docs/overview.md` is how it fits.
- The harness works the way pi does (owner, 2026-10-07; badlogic/pi-mono's pi-agent-core is the guide): one model in
  one loop with a short system prompt and a few tools, calling tools until it answers without one; its context is
  the transcript itself; a run ends when the model says it is done, never on a step, token or turn cap; a person or
  a hook steers mid-run or queues a follow-up; tool errors go back to the model as results. MiniMax M3 drives. Jev and
  TabICL are hooks, not the driver: Jev judges a look, TabICL learns from every tool call's rows and may annotate one.

- Its Lua is `core/`:
  the harness (`tablua`, `agent`, `robot`) and the model ports (`ports`); read `core/AGENTS.md` before editing there.
- A program is org plus Robot Framework (owner, 2026-10-05): org holds the plan and the code, Robot the tests and
  tasks; both cut into rows, and the tests run in Lua (`core/robot`), every keyword's result kept as rows. No Gherkin.
- What the agent is asked to do is a todo (owner, 2026-10-05: org's word for a thing to be done), the key of every
  log table (`todo`, `n`). "Task" means only a Robot task: a test that does a job rather than checks one.
- Lua is the harness, not the output (owner, 2026-10-05): the agent's work may be in any language its computer
  runs. The harness itself is portable Lua, embedded through whatever Lua VM a host has, and reaches the world only
  through the ports the host supplies. No WebAssembly, no native code.
- `site/` is tablua.com, the one place TypeScript, React and Node tooling are allowed (owner, 2026-10-04). Nothing
  the harness runs reaches it.
- Tests: `luajit test/run.lua` runs every `core/**/*_test.lua` in its own process (`luajit test/run.lua tree edit`
  runs the files whose path holds one of the words; `TABLUA_LUA=lua` runs them on another VM, where the tests that open
  SQLite through LuaJIT's FFI fail). The test library is `test/spec.lua`: `test`, `eq`, `ok`, `same`, `err`, `run`.
- Files stay under 400 lines, split by responsibility. No placeholder modules.
- Keys and tokens (model keys, page tokens) are never logged, printed or written to files.
- Claims are Robot tests in `.robot/` (owner, 2026-10-06): before saying a change "works", "fixed" or "better" when
  something will be built on it, write the claim with its kill number and a ` (red)` proof, commit it, then measure
  (`luajit .robot/run.lua fetch <label>` after a bench run, `luajit .robot/run.lua`) and commit the ledger. Say which
  level was shown (consistent, correct, informative, useful). `.robot/README.md` says how and `/claim` walks it;
  `luajit .robot/test.lua` tests the framework, and `luajit .robot/mutate.lua .robot/mutations/*.lua` checks that
  tests can fail.
