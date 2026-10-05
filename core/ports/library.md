---
name: ports
description: The two minds and web search behind host-supplied fetch — the Jev port (typed decisions, OpenRouter), the Mercury port (fill, next edit and chat on Inception's API, laid out for its prompt cache) and the search port (Parallel, turbo mode) and the TabPFN port (Prior Labs' hosted TabPFN-3.5, an optional batch calibrator) and the image port (Qwen3-VL-235B-A22B on OpenRouter, frames in, text out) — plus the JSON they speak; use when calling either model or changing a request's shape.
summary: jev.new(host, {key}):decide(state, questions) -> answers, record; mercury.new(host, {key}):fill/edit/chat -> text, record; search.new(host, {key, mode}):search(objective, queries) -> results, record; tabpfn.new(host, {key, model}):estimate(q) -> tokens, record, see.new(host, {key, model?}):look(frames, text) -> reply, record (frames = base64 PNGs in order), chat.new(host, {key, model, service?, thinking?, sort?}):chat{system, user | messages, max_tokens} -> text, record (any OpenRouter or Cerebras model; thinking = false for a spoken reply), :fit(table, labels, {cache, model, thinking}) -> fitted, record, :predict(fitted, table) -> probas, record, where a table is {columns, rows}. A port's refusal is raised as { message, status } in the service's own words; search.new(host, {key, bearer = true}) sends the key as a Bearer token (for a service that proxies the search API). host = { fetch, now?, sleep? }. The record is what the log keeps and never holds the key. ports.curl is the LuaJIT test host's fetch.
do:
  - Put every question about one state in one Jev call; Jev has no cache and bills per call.
  - Order Mercury context from least to most likely to change; the cache matches only on the prompt's start.
  - Log the record a call returns, not the request.
  - Search the web through ports.search (Parallel, turbo by default); raise the mode per call only when turbo's results fall short.
  - Call tabpfn:estimate before any TabPFN fit or predict; every TabPFN-3.5 predict costs at least 10,000 tokens.
dont:
  - Do not put a credential in a record, a log row or a model's prompt.
  - Do not send Mercury through OpenRouter; it never caches there (tag caching).
  - Do not send chat temperature below 0.5; Mercury silently resets it to 1.
  - Do not require ports.curl from core code; it is the test host's fetch.
---

# core/ports

Modules: `json.lua` (sorted keys, so equal requests
are equal bytes), `call.lua` (one POST, one retry on network, 429 or 5xx, error text trimmed to the
service's own messages), `jev.lua`, `mercury.lua`, `chat.lua` (any OpenRouter chat model behind Mercury's `chat` shape, with its own cost and a reasoning allowance, so a model such as Kimi K2 Thinking can be the writer), `see.lua` (the image model: one frame or a sequence as successive images; the caller asks for a
format and validates it), `search.lua` (Parallel's Search API, key in `x-api-key`), `tabpfn.lua` (Prior Labs' REST flow: prepare upload, PUT CSV to the signed URL
without the key, fit, predict), `stream.lua` (a chat route's server-sent events, read as they come) and `curl.lua`
(the test host's fetch over the system libcurl). Every port takes its key from the host; none reads a keychain.
