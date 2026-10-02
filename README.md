# 🌙🌸 moss-browser

The browser engine of VMOSS, the agent's own computer in [Arock](https://arock.ai)'s Moss. An Elixir library: it
fetches a page the way a browser does, reads it the way a screen reader does, and (next) looks at it the way a
person's browser lays it out. Moss keeps what belongs to a computer (tabs, history, the commands, the jar kept in
its session); moss-browser is the part that knows nothing of computers.

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

- **`Moonflower.Look`**: the look (Arock PROJECT.md §16.3, feature `look`). Blitz (html5ever, Stylo, Taffy,
  Parley) built to WebAssembly (`look/`, Rust from Blitz pinned at `d2827fb`), run by wasmex in a node of its own
  (`Moonflower.Look.Node`, `:peer` over stdio): the module checked by its SHA-384, each look a fresh instance
  under fuel and a 256 MB cap, with no directory, environment or arguments. It answers which elements are shown
  at a width and a theme, and their boxes. A Shroomi page takes 40 to 70 ms end to end, Wikipedia's Octopus
  (8,263 elements) about 500 ms.

## Use

```elixir
{:ok, %{body: html, url: url}} = Moonflower.Fetch.get("https://example.com/", browser: true)
page = Moonflower.Page.new(url, html)
Moonflower.Page.text(page)
Moonflower.Page.outline(page)   # [3] field "Email" (required) ...
```

Options are passed, never read from the application's environment: `:resolver`, `:max`, `:agent` and
`:req_options` are how a host (Moss) sets its own.

```elixir
{:ok, node} = Moonflower.Look.Node.start_link(path: "priv/look.wasm", sha384: pinned)
{:ok, look} = Moonflower.Look.look(node, html, width: 390, base: url)
Moonflower.Look.shown?(look, "button", "Menu")
```

## The look module

CI builds it (`.github/workflows/look.yml`) and a `v*` tag publishes `look.wasm` and its SHA-384 as a release
asset; the host pins the hash. To run the look's tests locally, put it at `priv/look.wasm`: download a release's
asset, or build it (`cargo build --release --target wasm32-wasip1 --manifest-path look/Cargo.toml`, then
`wasm-opt -Oz`; Stylo wants several GB of disk to build). The font inside it is Inter (OFL, `look/fonts/OFL.txt`).

## Test

`mix test`. The tokenizer's fixtures are html5lib-tests (MIT, `test/fixtures/html5lib/LICENSE`). Without
`priv/look.wasm`, the look's tests are left out and the run says so.
