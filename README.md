# 🍄 Shroomi

Shroomi is how an agent publishes its work. Everything an agent shows a person on its computer goes through it: a page, an app, a report, a form. A page is Lua that builds HTML, styled by Basecoat's components and Tailwind's utility names, and moved by htmx. The agent writes no JavaScript and no CSS file, and the host holds every page to one policy, so a page is safe to open whoever wrote it.

```lua
local ui = require("shroomi")

return function(req)
  local plants = { "fern", "moss" }
  local rows = {}
  for i, name in ipairs(plants) do rows[i] = ui.li{ class = "flex justify-between", name } end
  return ui.page{ title = "Plants",
    ui.container{
      ui.card{ title = "Plants", description = #plants .. " in the window",
        ui.ul{ class = "space-y-2", rows },
        ui.form{ post = "plants", ui.input{ name = "name", label = "Name" }, ui.button"Add" },
      },
    },
  }
end
```

## The method

1. **Build, don't concatenate.** `ui.<tag>{...}` and the kit's components escape every text and attribute. `ui.raw(html)` passes markup through (from Markdown, say), and the host cleans it anyway.
2. **Style with the kit, then with classes.** Basecoat's components (`ui.button`, `ui.card`, `ui.input`, `ui.data_table`, `ui.tabs`, `ui.dialog`, ...) look finished on their own. Utility classes (`flex gap-4 md:grid-cols-3 text-muted-foreground`) arrange them; Shroomi writes CSS for the ones a page uses. `ui.check(html)` names any class it does not know.
3. **Move with htmx.** `post = "plants"`, `target = "#list"`, `swap = "outerHTML"` become `hx-post`, `hx-target` and `hx-swap`. Addresses are relative to the app (`plants`, not `/plants`). Behaviour beyond htmx comes only from Shroomi's own reviewed scripts: dialogs open with `data-open="id"`.
4. **Make components.** `ui.component("plant", function(props, children) ... end)` adds `ui.plant{...}`. A component is a function from props to nodes, so it can be put anywhere a page goes.
5. **Light and dark come free.** A page follows its person's system, as Basecoat's theme does with its `dark`
   class; `ui.page{ dark = true }` or `dark = false` fixes it. Use the theme's colours (`bg-card`,
   `text-muted-foreground`), not fixed ones, and a page reads in both.
6. **Read it back.** The agent's computer reads the same page as words and controls (`open app`), the way the person's browser draws it.

## Safety

The page is the agent's writing, so none of it runs as code.

- **[policy.lua](policy.lua)** names the elements, attributes, URL schemes, htmx attributes and assets a page may use. Script, style, iframe, object, embed and base elements are never allowed, nor are `on*` handlers, `javascript:` addresses, `hx-on` or `hx-vars`.
- **The host enforces the policy** on every page, outside the agent's own run. A page written without Shroomi's helpers is held to it all the same.
- **Assets are pinned by SHA-384** and served by the host: Basecoat 1.0.2 (MIT), htmx 2.0.4 (0BSD) and `shroomi.js`. They are the only scripts a page loads, and the host's Content-Security-Policy allows nothing else.

## Extending

- **A new component** is Lua, in `components.lua` for the kit or by an agent with `ui.component`.
- **A new utility** is a line in `utilities.lua`.
- **A new behaviour** that needs script (a rich-text editor, a chart) comes in as a reviewed, pinned asset with its component. It never comes in as script from a page.

## Files

| File | What it is |
| --- | --- |
| `init.lua` | Elements, escaping, components, pages |
| `components.lua` | The kit: Basecoat's components as Lua |
| `css.lua`, `utilities.lua` | Utility classes as CSS, over Basecoat's theme |
| `template.lua` | Mustache, for pages written as text |
| `markdown.lua` | Markdown to safe HTML |
| `icons.lua` | Lucide's icons as data, for `ui.icon` |
| `policy.lua` | What a page may hold, enforced by the host |
| `examples/` | The gallery: six apps and the app that shows them (see below) |
| `assets/` | The pinned scripts and styles a page loads |

## The gallery

`examples/` holds apps written only in Shroomi: a plant tracker (a database and htmx), Markdown notes with a live preview, a dashboard, a settings form the server validates, a report, and an inbox. `examples/app.lua` is the gallery itself, which shows each one and the Lua that made it. To open it, put the folder on a computer from Moss: `mix moss.put shroomi-gallery <path>/examples --as examples --app app.lua --owner <you>`, then open `/computers/shroomi-gallery/app/`.

Portable Lua: it runs unchanged on LuaJIT, Lua 5.4/5.5 and tv-labs `lua`. Tests are `*_test.lua` (buck2 `lua_test`; Moss runs them in tv-labs `lua` too).
