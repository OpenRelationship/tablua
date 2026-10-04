# 🍄 Shroomi

Shroomi is how an agent publishes its work. Everything an agent shows a person on its computer goes through it: a page, an app, a report, a form. A page is a `.lui` file, HTML with Lua in it, compiled to Shroomi's elements, styled by Basecoat's components and Tailwind's utility names, and moved by htmx. The agent writes no JavaScript and no CSS file, and the host holds every page to one policy, so a page is safe to open whoever wrote it.

```html
<lua>
  local d = db.open("data/plants.dbl")
  page.title = "Plants"
  function post.water(req) d:exec("update plant set watered = date('now') where name = ?", req.form.name) end
</lua>
<card title="Plants">
  <ul>
    {% for _, p in ipairs(d:query("select * from plant order by name")) do %}
      <li class="flex justify-between">{{ p.name }}
        <button size="sm" post="water" vals={{ { name = p.name } }}>Water</button>
      </li>
    {% end %}
  </ul>
</card>
```

That is the whole page. `post="water"` names the action defined above it; the action changes the database and returns nothing, and the page is rendered again and merged into the one the person sees ([idiomorph](https://github.com/bigskysoftware/idiomorph), so focus, scroll and what they typed stay). Nothing to target, no fragment to keep in step: everything is wired in one place.

## A .lui page

- A `<lua>` block on top, run on every request: it reads what the page shows and defines its actions, `post.<name>` and `get.<name>`, and `page.title`. Below it, markup: `{{ e }}` is text, always escaped; `{{{ e }}}` is markup as it is (still cleaned); `{% lua %}` is a statement (`{% for _, p in ipairs(list) do %}` ... `{% end %}`).
- Kit components are tags (`<card>`, `<button>`, `<data_table>`). `attr="text {{ e }}"` is a string; `attr={{ e }}` passes the value itself, a table or a boolean. `<slot name="footer">...</slot>` gives the element around it that prop as markup.
- Every tag is closed (`<x/>` or `</x>`; `br`, `hr`, `img` and `input` may stand alone).
- An action runs, then the page runs again from its top and renders. It returns nothing for the whole page, `"#id"` for that element alone (when a page is costly to send), `{ redirect = "path" }`, or any other value, which the markup reads as `result` (a form's errors, say).
- An unknown tag, class or action, a tag left open, Lua that does not parse, and the habits of other template languages (`{% endfor %}`) fail at compile time with the page's file and line. Lua's errors when it runs carry the page's lines too.
- `ui/index.lui` is an app's `/`, `ui/list.lui` its `/list`; links in an app are relative to it (`?note=garden`, `list`).

## The method

1. **Build, don't concatenate.** `ui.<tag>{...}` and the kit's components escape every text and attribute. `ui.raw(html)` passes markup through (from Markdown, say), and the host cleans it anyway.
2. **Style with the kit, then with classes.** Basecoat's components (`ui.button`, `ui.card`, `ui.input`, `ui.data_table`, `ui.tabs`, `ui.dialog`, ...) look finished on their own. Utility classes (`flex gap-4 md:grid-cols-3 text-muted-foreground`) arrange them; Shroomi writes CSS for the ones a page uses. `ui.check(html)` names any class it does not know.
3. **Move with actions, and htmx.** In a .lui page an action is named once (`post="water"`); in Lua, `post = "plants"`, `target = "#list"`, `swap = "outerHTML"` become `hx-post`, `hx-target` and `hx-swap`. Addresses are relative to the app (`plants`, not `/plants`). Behaviour beyond htmx comes only from Shroomi's own reviewed scripts: dialogs open with `data-open="id"`.
4. **Make components.** `ui.component("plant", function(props, children) ... end)` adds `ui.plant{...}`. A component is a function from props to nodes, so it can be put anywhere a page goes.
5. **Light and dark come free.** A page follows its person's system, as Basecoat's theme does with its `dark`
   class; `ui.page{ dark = true }` or `dark = false` fixes it. Use the theme's colours (`bg-card`,
   `text-muted-foreground`), not fixed ones, and a page reads in both.
6. **Read it back.** The agent's computer reads the same page as words and controls (`open app`), the way the person's browser draws it.

## Safety

The page is the agent's writing, so none of it runs as code.

- **[policy.lua](policy.lua)** names the elements, attributes, URL schemes, htmx attributes and assets a page may use. Script, iframe, object, embed and base elements are never allowed, nor are `on*` handlers, `javascript:` addresses, `hx-on` or `hx-vars`. The one `<style>` is the CSS `ui.page` writes in the head; a style element anywhere else is taken out, and CSS that names a script address or a binding (`url(javascript:)`, `expression()`, `behavior:`, `-moz-binding`) is dropped, in the head and in `style` attributes.
- **The host enforces the policy** on every page, outside the agent's own run. A page written without Shroomi's helpers is held to it all the same. Moss parses and cleans pages in Elixir, so no page an agent writes reaches C, and it checks itself against DOMPurify's 223-vector corpus.
- **Assets are pinned by SHA-384** and served by the host: Basecoat 1.0.2 (MIT), htmx 2.0.4 (0BSD), idiomorph 0.7.3 (0BSD, its core only: its htmx extension evaluates swap options as code) and `shroomi.js` (dialogs, light or dark as the system is, and merging an action's page). They are the only scripts a page loads, and the host's Content-Security-Policy allows nothing else.
- **Where a page is shown.** The person opens the app in their browser (`/computers/<id>/app/`), or in the computer's desktop as its App window: a sandboxed frame with an opaque origin and no cookies, opened by a one-hour pass for that computer and reloaded when the agent changes its files. The agent reads the same page as words and controls (`open app`).

## Extending

- **A new component** is Lua, in `components.lua` for the kit or by an agent with `ui.component`.
- **A new utility** is a line in `utilities.lua`.
- **A new behaviour** that needs script (a rich-text editor, a chart) comes in as a reviewed, pinned asset with its component. It never comes in as script from a page.

## Files

| File | What it is |
| --- | --- |
| `init.lua` | Elements, escaping, components, pages |
| `lui.lua`, `lui_scan.lua` | .lui pages: read, checked, compiled to elements |
| `page.lua` | A page and its actions: run, rendered again, merged |
| `components.lua` | The kit: Basecoat's components as Lua |
| `css.lua`, `utilities.lua` | Utility classes as CSS, over Basecoat's theme |
| `markdown.lua` | Markdown to safe HTML |
| `icons.lua` | Lucide's icons as data, for `ui.icon` |
| `policy.lua` | What a page may hold, enforced by the host |
| `examples/` | The gallery: six apps under `apps/`, and the pages that show them (see below) |
| `assets/` | The pinned scripts and styles a page loads |

## The gallery

`examples/` is a computer's `/home`: six apps under `apps/<name>/`, each one `.lui` page, written only in Shroomi: a plant tracker (a database and actions), Markdown notes with a preview that follows your typing, a dashboard, a settings form the server checks, a report, and an inbox. `ui/index.lui` is the gallery, and `ui/source.lui` shows the page that made each one. To open it, put the folder on a computer from Moss: `mix moss.put shroomi-gallery <path>/examples --owner <you>`, then open `/computers/shroomi-gallery/app/`, or the computer's desktop, where it is the App window.

Portable Lua: it runs unchanged on LuaJIT, Lua 5.4/5.5 and tv-labs `lua`. Tests are `*_test.lua` (buck2 `lua_test`; Moss runs them in tv-labs `lua` too).
