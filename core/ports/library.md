---
name: ports
description: Arock Core's two minds and its web search behind host-supplied fetch — the Jev port (typed decisions, OpenRouter), the Mercury port (fill, next edit and chat on Inception's API, laid out for its prompt cache) and the search port (Parallel, turbo mode) and the TabPFN port (Prior Labs' hosted TabPFN-3.5, an optional batch calibrator) and the image port (Qwen3-VL-235B-A22B on OpenRouter, frames in, text out) — plus the JSON they speak; use when calling either model or changing a request's shape.
summary: jev.new(host, {key}):decide(state, questions) -> answers, record; mercury.new(host, {key}):fill/edit/chat -> text, record; search.new(host, {key, mode}):search(objective, queries) -> results, record; tabpfn.new(host, {key, model}):estimate(q) -> tokens, record, see.new(host, {key, model?}):look(frames, text) -> reply, record (frames = base64 PNGs in order), chat.new(host, {key, model, service?, thinking?, sort?}):chat{system, user | messages, max_tokens} -> text, record (any OpenRouter or Cerebras model; thinking = false for a spoken reply), :fit(table, labels, {cache, model, thinking}) -> fitted, record, :predict(fitted, table) -> probas, record, where a table is {columns, rows}. arock.new(host, {key = session, base?}) is Arock's service with Mercury's fill/edit/chat and Jev's decide, plus :account() and :voice(), :see(), :search(), :tabpfn() (ports.chat, see, search and tabpfn pointed at the service), its refusals raised as { message, status } in the service's own words; search.new(host, {key, bearer = true}) sends the key as a Bearer token. host = { fetch, now?, sleep? }. The record is what the log keeps and never holds the key. ports.curl is the LuaJIT test host's fetch.
do:
  - Put every question about one state in one Jev call; Jev has no cache and bills per call.
  - Order Mercury context from least to most likely to change; the cache matches only on the prompt's start.
  - Log the record a call returns, not the request.
  - Search the web through ports.search (Parallel, turbo by default); raise the mode per call only when turbo's results fall short.
  - Call tabpfn:estimate before any TabPFN fit or predict; every TabPFN-3.5 predict costs at least 10,000 tokens.
  - Ask the person for a service's credential only when connect says a call needs it (err.needs), and keep it on the host.
dont:
  - Do not put a service's credential in a record, a log row or a model's prompt; connect's record holds neither the address nor a header.
  - Do not send Mercury through OpenRouter; it never caches there (tag caching).
  - Do not send chat temperature below 0.5; Mercury silently resets it to 1.
  - Do not require ports.curl from core code; it is the test host's fetch.
---

# core/ports

Spec: `context/projects/arock/features/ports`. Modules: `json.lua` (sorted keys, so equal requests
are equal bytes), `call.lua` (one POST, one retry on network, 429 or 5xx, error text trimmed to the
service's own messages), `jev.lua`, `mercury.lua`, `chat.lua` (any OpenRouter chat model behind Mercury's `chat` shape, with its own cost and a reasoning allowance, so a model such as Kimi K2 Thinking can be the writer), `see.lua` (the image model: one frame or a sequence as successive images; the caller asks for a
format and validates it), `search.lua` (Parallel's Search API, key in `x-api-key`, keychain
item `arock-parallel`), `tabpfn.lua` (Prior Labs' REST flow: prepare upload, PUT CSV to the signed URL
without the key, fit, predict; keychain item `arock-priorlabs`), `connect.lua` (other people's apps through connectory's directory and its `port_http`; PROJECT.md §17), `arock.lua` (Arock's service, app/worker: the Mercury and Jev ports pointed at its /v1 paths with the app's session as the bearer; spec `features/arock-service`), `writs.lua` (the person's writs kept on arock.ai too, every version, with the same session; `sync` sends only what the service lacks; feature notes) and `curl.lua` (the test host's fetch over the
system libcurl). `just tool ports-live` makes one real call of each kind and prints latency, cost and
cache hits.
