# 🌙🌸 moss-browser

moss-browser is the browser engine of VMOSS (Arock's Moss), its own repository (owner, 2026-10-02), attached inside
Moss at `submodules/moss-browser`. README.md is the method; these are the rules for changing it.

- **A library, not a host.** Nothing here knows a computer, a person or a session. Settings arrive as options;
  `lib/` never reads `Application.get_env`. What belongs to a computer (tabs, history, commands, where a jar is
  kept) stays in Moss.
- **Elixir in `lib/`.** The one exception is the look module (`look/`, next): Rust from pinned upstream sources
  (Blitz), built to WebAssembly by CI only, published as a release asset and pinned by SHA-384 where it is used.
  Its build output is never committed. Nothing an agent writes is ever compiled or run as WebAssembly here.
- **The web is hostile.** Only http and https to public addresses; caps counted on inflated bytes; nothing from
  a page runs. A failure of the look falls back to reading without it.
- **Files stay under 400 lines**, split by responsibility. No placeholder modules.
- **Tested or it does not exist.** Every module has a test under `test/moonflower`; write the failing case first.
- **Keys and tokens are never logged, printed or written to files.** Cookie values are never listed.
