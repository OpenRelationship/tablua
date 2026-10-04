---
name: arock-log
description: arock-log, the log under everything an agent does, in portable Lua and SQL — one SQLite file holding the append-only log of who did what (Robot keywords and an actor), the state folded from it, full-text recall over both and the log as Robot rows; use when appending events, reading the files or history, recalling, undoing, or changing an event kind.
summary: alog.open(db, {clock?, hash?, replicated?}) -> log, where db:exec(sql, params) -> rows; log:append(task, keyword, args, actor) -> seq; log:undo(seq, actor); log:events(after), :history(task), :file(path), :paths(), :files_at(seq), :recall(q), :robot(), :rebuild(), :snapshot(); alog.tokens(text). Required as arock-log, arock-log.org, arock-log.kinds and the rest; arock-log.ffi is the LuaJIT test host's database port.
do:
  - Log every change as an event through append; the state is only ever folded from the log.
  - Give content arguments (a * in arock-log.kinds) as bytes; the log keeps them once as blobs.
  - Open a file Litestream streams with replicated = true.
dont:
  - Do not change the log itself; the triggers refuse it.
  - Do not require arock-log.ffi from core code; it is the test host's port.
  - Do not let SQLite parse an agent's text; recall tokenizes in Lua (tokens.lua, pinned by tokens_vectors.lua).
---

# core/arock-log

One log under everything an agent does. arock-log keeps an agent's whole record in one SQLite file: an append-only
log of who did what (Robot keywords with string arguments, and an actor: the agent, its person or its host), the
state folded from that log, full-text recall over both (its own index, so SQLite never parses an agent's
text), and the log written as Robot rows that Robot reads back
exactly. Arock's agent writes to it, and so does Moss, the agent's own computer: its file writes, its runs, its
app's requests and its mail are events on the computer's log, so a computer's history is its log.

It is portable Lua (LuaJIT, Lua 5.4/5.5, Luerl and tv-labs `lua`: no FFI in the core, no `goto`, no `//`, no
`utf8`) and SQL for SQLite. The database is a port the host supplies: anything with `exec(sql, params) -> rows`.

```lua
local alog = require("arock-log")
local log = alog.open(db, { replicated = true, hash = sha256 })   -- db:exec(sql, params) -> rows
log:append("rock-7", "Write File", { "/home/todo.txt", "water the fern" }, "agent")
log:append("rock-7", "Run Command", { "cat todo.txt", "/home", "0", "1.2", "water the fern", "" })
print(log:robot())                                                  -- the log, as Robot rows
```

## The API

- `alog.open(db, opts)`: `opts.clock()` gives an event's time (UTC ISO 8601 by default), `opts.hash(bytes)` a
  blob id (a portable 64-bit hash by default), and `opts.replicated` applies the settings Litestream needs.
- `append(task, keyword, args, actor)` logs and folds in one transaction and returns the seq; `undo(seq, actor)`
  logs an Undo and refolds; `load(task, source, entries)` brings a repository in as one Load Workspace event.
  The triggers refuse any change to the log itself.
- `events(after)`, `history(task)` read the log; `alog.fields(event)` names an event's arguments; `blob(id)` is a
  content argument's bytes.
- `file(path)`, `paths()`, `search_files(q, n)` read the files; `files_at(seq)` is the files as of an event;
  `artifact(name)` and `artifact_at(name, seq)` are the last Publish Artifact, now or just before an event.
- `rebuild()` folds the log back into the state; `snapshot()` keeps the state at the newest event, so `rebuild`
  and `undo` fold only what came after it. `recall(q)` searches events (with their content's text) and files;
  `robot()` renders the log; `settings()` reports the SQLite settings Litestream depends on.
- `alog.tokens(text)` is the tokenizer recall indexes and searches by.

## Recall

arock-log indexes in its own Lua, into plain tables, and ranks with bm25 in Lua (FTS5's k1 = 1.2 and b = 0.75): SQLite
stores the tokens and compares them as bound values, and never parses an agent's text (Arock's PROJECT.md §14.7,
item 9). `tokens.lua` specifies the tokenizer exactly and `tokens_vectors.lua` pins it, since Moss implements it
again in Elixir: words are runs of ASCII letters and digits and bytes 0x80-0xFF, ASCII folded to lower case, at
most 64 bytes a token and 10,000 tokens a text. `recall.lua` says what each table holds: an event's postings and
a text blob's are written as they arrive to `recall_pending`, in doc order, and packed by term into
`recall_blocks` every 50,000 rows by one fixed statement (`FLUSH_SQL`); a file's path is a row of
`recall_paths`.

## Event kinds

`arock-log.kinds` declares each keyword's arguments, and `append` checks them. A `*` argument is content: the caller
gives the bytes, arock-log keeps them once in `blobs` and logs the blob's id, so a body written twice, or a file that
`cat` prints, is stored once. A `#` argument must read as a number; a `?` one may be left off.

| Keyword | Arguments | Folds into |
| --- | --- | --- |
| Write File | path, content* | `files` (replaces a file) |
| Make Folder | path | `files` (a folder row) |
| Delete File | path | removes it, a folder with all under it |
| Move File | from, to | moves it, a folder with all under it; replaces a file at `to` |
| Run Command | line, cwd, status#, ms#, out*, err* | nothing: a command or Lua run, its status (124 and 137 are its time and memory limits) |
| Serve Request | method, path, status#, ms#, form*, page* | nothing: one request to the computer's app |
| Send Mail | to, subject, body*, outcome, letter | nothing: a letter sent, and what the post did with it |
| Receive Mail | from, subject, body*, letter | nothing: a letter delivered to this computer |
| Start Task, Enter State, Test Result | machine, goal?; state; result, detail? | `tasks` |
| Publish Artifact | name | `artifacts` |
| Load Workspace, Undo | by `load` and `undo` only | `files`; `undone` |
| Add Entry, Edit Entry | path, id, entry*; id, entry* | `org_entries`: an org entry's text, as `arock-log.org_log` wrote it |
| Archive Entry, Move Entry, Set Header | id; path, order; path, header* | `org_entries` (archived, order); `org_files` |
| Set State, Set Date, Set Property, Link | id, from, to; id, which, date; id, key, value; id, target | nothing: what an org edit changed, for refine |
| Add Note, Edit Note, Move Note | note, folder, text*; note, text*; note, folder | nothing: the person's notes, every version kept (Arock feature notes) |
| Set Character | rock, part, text*, from | nothing: a rock's character or focus as a writ composed it, after the person's yes; from is `note-<n>@<version>#<bytes>` (Arock feature notes) |
| Set Writ Line | rock, kind, key, value*, from | nothing: a line a writ built after the person's yes (a character, focus, tool, reach, term, route or asked feature), "" when taken away; rock `*` for every rock (Arock feature notes) |
| Decide, Grade, Outcome | at, who, options, choice, confidence?; target, score, confidence?, why?; target, outcome, detail? | nothing: a choice with every option, a grade, an outcome (feature refine) |

Any other keyword is logged and recalled only. An org file is written through `arock-log.org_log.write` (its new text checked
whole against the history by `arock-log.org_diff`, refused by line, its events appended in one `batch`) and read back
with `arock-log.org_log.read`; `arock-log.org` is the subset it speaks, `arock-log.manifest` and `arock-log.org_kinds` what a manifest
and each kind of org file must hold. Blob ids are opaque strings: the host's digest when it gives one,
and a second content with the same id is kept as `id.2`, since arock-log compares bytes before it reuses a blob.

## What a host reads

The state is tables a host may read directly: `files` (path, dir, blob, seq), `tasks`, `artifacts`, `undone`,
`org_entries` (id, path, pos, keyword, title, archived, text, seq), `org_files` (path, header, seq), and
the view `entries` (path, dir, data, size, at, seq), each path with its bytes and the time of the event that last
changed it. The state is folded from the log and nothing else: when its shape changes (`alog_state.version`),
`open` drops it and folds the log again, and the log is never touched; the recall index of the log is built
again then too. Recall indexes text only (no NUL byte), at most 64 KB of each content.

## Streamed to R2

`litestream.yml` is the node's Litestream (0.5.4 or later) config, which arock-server writes and runs itself: the directory
watcher over the node's `computers/*.sqlite`, each file streamed every 5 s to a file replica on the node as
immutable segments, `replica/<id>.sqlite/ltx/<level>/<min>-<max>.ltx`. It holds no key, and the node holds none to
the bucket. Every minute arock-server's packer gathers every awake computer's new segments into one pack and puts it
through Arock's service with the node's own token (`/moss/packs/<node>/<name>`), so a node writes one object a
minute however many computers work. A computer sleeps as its whole file (`vacuum into`, one write), then
`litestream sync -wait` and `litestream stop`, and goes from the node once the service holds it; it wakes from
that file (one read). Packs matter only to a node that lost its disk: it reads their headers, takes each awake
computer's segments with ranged reads and runs `litestream restore -o <file> file://<segments>`.

A streamed file is opened with `replicated = true`: journal mode WAL, `synchronous = normal`,
`wal_autocheckpoint = 0` (Litestream checkpoints, the app never does) and `busy_timeout = 5000`. Writes take
`begin immediate`, so a second writer waits rather than failing, and a reader (Litestream, or a page showing the
log) reads beside the writer without waiting. The app never leaves WAL, never VACUUMs in place (`vacuum into`
another file only reads), and never deletes the file or its `-wal` while Litestream watches it.

`arock-log.ffi` is the LuaJIT test host's port over the system SQLite (`AROCK_SQLITE` names the library). Core code
never requires it; every other host brings its own.

Tests: `alog_test.lua`, `disk_test.lua`, `runs_test.lua`, `snapshot_test.lua`, `litestream_test.lua`,
`recall_test.lua` and `tokens_test.lua`, run by
Arock's build (`just test //submodules/vmoss/core/arock-log/...`) and on moss-lua by VMOSS (`submodules/vmoss`,
`mix test test/moss/gate0_test.exs`).
