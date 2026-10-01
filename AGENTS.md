# Shroomi

Shroomi is how an agent publishes its work on its own computer (Arock's Moss): Lua that builds HTML, styled by Basecoat and utility classes, moved by htmx, and held by the host to `policy.lua`. README.md is the method; these are the rules for changing it.

- **Portable Lua only.** It runs unchanged on LuaJIT, Lua 5.4/5.5 and tv-labs `lua`: no FFI, no `goto`, no `//`, no `utf8`, no `require` outside `shroomi.*`. Keep every file under 400 lines, split by responsibility.
- **Tested or it does not exist.** Every module has a `*_test.lua` (mono.spec, a buck2 `lua_test`). Write the failing case first.
- **Nothing an agent writes runs as code.** Never add a tag, attribute or scheme to `policy.lua` that can carry script: no `script`, `style`, `iframe`, `object`, `embed`, `base`, `meta` or `link`; no `on*`, `hx-on` or `hx-vars`; no `javascript:` or `data:` addresses. A component never emits an inline handler. Behaviour that needs script is a reviewed asset.
- **Assets are pinned.** A file in `assets/` is a named upstream release, or Shroomi's own reviewed script. Its SHA-384 lives in `policy.lua` and changes in the same commit as the file. Upstream licences sit beside them.
- **`policy.lua` is pure data.** No function and no `require`, so any host can read it as a table.
- **Escaping is the default.** Text and attribute values are escaped; only `ui.raw` passes markup, and the host still cleans it.
