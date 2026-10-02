# 🌙🌸 moonflower

The browser engine of VMOSS, the agent's own computer in [Arock](https://arock.ai)'s Moss. An Elixir library: it
fetches a page the way a browser does, reads it the way a screen reader does, and (next) looks at it the way a
person's browser lays it out. Moss keeps what belongs to a computer (tabs, history, the commands, the jar kept in
its session); moonflower is the part that knows nothing of computers.

- **`Moonflower.Fetch`**: http and https to public addresses only, every redirect checked again, a name resolved
  once and the checked address dialled; a browser's headers and an honest user-agent (`Arock/1.0 (an AI agent
  browsing for a person; +https://arock.ai/agent)`); gzip and deflate inflated under a size cap counted on the
  inflated bytes; a cookie jar carried through redirects.
- **`Moonflower.Cookies`**: domain, path, secure and expiry rules, a short public-suffix list, bounded; listed by
  name, never by value.
- **`Moonflower.Charset`**: a page's bytes as UTF-8, by header then meta; windows-1252 and Latin labels decoded; a
  set it does not decode is said, not guessed.
- **`Moonflower.HTML`**: an HTML parser in Elixir (the tokenizer is tested against html5lib-tests).
- **`Moonflower.Page`**: a page kept small: its words as blocks by region and section, its headings, its controls
  as an accessibility tree (roles, names as a screen reader gives them, states), the data it carries (meta,
  JSON-LD, framework JSON), and a gzipped copy without scripts for a person watching. Read in parts by landmark.

Next: **the look** (Arock PROJECT.md §16.3, feature `look`): Blitz (html5ever, Stylo, Taffy, Parley) built to
WebAssembly, run by wasmex in a node of its own, so a page's stylesheet-hidden parts, boxes and faults are known.

## Use

```elixir
{:ok, %{body: html, url: url}} = Moonflower.Fetch.get("https://example.com/", browser: true)
page = Moonflower.Page.new(url, html)
Moonflower.Page.text(page)
Moonflower.Page.outline(page)   # [3] field "Email" (required) ...
```

Options are passed, never read from the application's environment: `:resolver`, `:max`, `:agent` and
`:req_options` are how a host (Moss) sets its own.

## Test

`mix test`. The tokenizer's fixtures are html5lib-tests (MIT, `test/fixtures/html5lib/LICENSE`).
