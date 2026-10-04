-- Recall: arock-log's own index in plain tables, ranked by bm25 in Lua, so SQLite
-- only stores and compares the agent's bytes and never parses them.
--
-- Against the FTS5 index it replaces (schema version 2), on ASCII text the
-- results, their order and their bm25 scores are the same (the corpus below
-- was run through both). What differs: words are split and folded by
-- alog.tokens (bytes 0x80-0xFF are word bytes and keep their case, where FTS5's
-- unicode61 folded and split Unicode too); a word repeated in a query counts
-- once, and words joined by "_" are each a word where FTS5 took them as a
-- phrase; equal scores go in seq order (events) and path order (files).
local spec = require("mono.spec")
local alog = require("arock-log")
local recall = require("arock-log.recall")
local sqlite = require("arock-log.ffi")

local function fresh(db)
  return alog.open(db or sqlite.open(":memory:"), { clock = function() return "t" end })
end

local function corpus()
  local s = fresh()
  s:append("pc", "Say", { "the fern needs water every morning" }, "user")
  s:append("pc", "Say", { "water water water the garden" }, "user")
  s:append("pc", "Run Command", { "ls garden", "/home", "0", "3", "fern.txt garden.txt tools\n", "" })
  s:append("pc", "Say", { "a long note about many things that are not the fern but mention water once in passing today" })
  s:append("pc", "Write File", { "/notes/fern.txt", "fern fern fern; water weekly" })
  s:append("pc", "Write File", { "/notes/garden.md", "Garden plan: tomatoes, water daily, compost" })
  s:append("pc", "Write File", { "/water/log.txt", "nothing here" })
  s:append("pc", "Say", { "compost" })
  return s
end

-- bm25(recall_log) and bm25(recall_files) from FTS5 on the same corpus, best first
local FTS5 = {
  events = {
    ["water"] = { { 2, -1.69937369519833e-06 }, { 1, -1.1105047748976808e-06 }, { 7, -1.1105047748976808e-06 },
      { 5, -9.6789536266349572e-07 }, { 6, -9.2816419612314715e-07 }, { 4, -6.9871244635193141e-07 } },
    ["fern water"] = { { 5, -2.6367831125353562e-06 }, { 1, -2.2210095497953616e-06 }, { 2, -1.69937369519833e-06 },
      { 4, -1.3974248927038628e-06 }, { 7, -1.1105047748976808e-06 }, { 6, -9.2816419612314715e-07 },
      { 3, -8.9156626506024097e-07 } },
    ["garden compost"] = { { 6, -1.4769531333138433 }, { 8, -1.4064852011796261 }, { 3, -0.57352438149158003 },
      { 2, -0.52785637120064366 } },
    ["notes"] = { { 5, -0.92483509661395147 }, { 6, -0.88687151226035721 } },
    ["txt log"] = { { 7, -2.289220124758808 }, { 3, -0.57352438149158003 }, { 5, -0.43747430526379139 } },
  },
  files = {
    ["garden compost"] = { { "/notes/garden.md", -1.1275575010871468 } },
    ["notes"] = { { "/notes/fern.txt", -9.6414342629482082e-07 }, { "/notes/garden.md", -9.1493383742911171e-07 } },
    ["txt log"] = { { "/water/log.txt", -0.58726861259558083 }, { "/notes/fern.txt", -9.6414342629482082e-07 } },
    ["water"] = { { "/water/log.txt", -1.1496437054631828e-06 }, { "/notes/fern.txt", -9.6414342629482082e-07 },
      { "/notes/garden.md", -9.1493383742911171e-07 } },
  },
}

local function close(a, b) return math.abs(a - b) <= 1e-12 * math.max(1, math.abs(b)) end

spec.test("events rank in FTS5's order with its bm25 scores", function()
  local s = corpus()
  for q, want in pairs(FTS5.events) do
    local got = recall.events(s.db, q, 10)
    spec.eq(#got, #want, q)
    for i, w in ipairs(want) do
      spec.eq(got[i].seq, w[1], q .. " #" .. i)
      spec.ok(close(-got[i].score, w[2]), q .. " #" .. i .. " score " .. got[i].score .. " vs " .. w[2])
    end
  end
end)

spec.test("files rank in FTS5's order with its bm25 scores", function()
  local s = corpus()
  for q, want in pairs(FTS5.files) do
    local got = recall.files(s.db, q, 10)
    spec.eq(#got, #want, q)
    for i, w in ipairs(want) do
      spec.eq(got[i].path, w[1], q .. " #" .. i)
      spec.ok(close(-got[i].score, w[2]), q .. " #" .. i .. " score")
    end
  end
  spec.same(s:search_files("notes", 1), { "/notes/fern.txt" })
end)

spec.test("postings packed into blocks are found and ranked as pending ones are", function()
  local was = recall.FLUSH
  recall.FLUSH = 7
  local packed = corpus()
  recall.FLUSH = was
  spec.ok(packed.db:exec("select count(*) as n from recall_blocks")[1].n > 0, "some postings were packed")
  local pending = corpus()
  spec.eq(pending.db:exec("select count(*) as n from recall_blocks")[1].n, 0)
  spec.eq(packed:dump(), pending:dump())
  for q in pairs(FTS5.events) do
    spec.same(recall.events(packed.db, q, 10), recall.events(pending.db, q, 10), q)
    spec.same(recall.files(packed.db, q, 10), recall.files(pending.db, q, 10), q)
  end
  recall.settle(pending.db, true)
  spec.eq(pending.db:exec("select count(*) as n from recall_pending")[1].n, 0)
  spec.eq(pending:dump(), packed:dump())
end)

spec.test("recall finds an event by its content's words and a limit keeps the best", function()
  local s = corpus()
  local found = s:recall("compost garden", 2)
  spec.eq(#found.events, 2)
  spec.eq(found.events[1].seq, 6); spec.eq(found.events[1].keyword, "Write File")
  spec.eq(found.events[2].seq, 8)
  spec.eq(found.files[1].path, "/notes/garden.md")
  spec.eq(#s:recall("", 5).events, 0)
  spec.eq(#s:recall("tomatoes", 5).events, 1)
  spec.eq(#s:recall("TOMATOES", 5).files, 1)
end)

spec.test("a move finds a file under its new path's words, and a delete finds it no more", function()
  local s = fresh()
  s:append("pc", "Make Folder", { "/old" })
  s:append("pc", "Write File", { "/old/plan.txt", "the zebra plan" })
  s:append("pc", "Write File", { "/keep.txt", "zebra too" })
  s:append("pc", "Move File", { "/old", "/new" })
  spec.same(s:search_files("old", 5), {})
  spec.same(s:search_files("new", 5), { "/new/plan.txt" })
  spec.same(s:search_files("plan zebra", 5), { "/new/plan.txt", "/keep.txt" })
  s:append("pc", "Move File", { "/keep.txt", "/new/plan.txt" })
  spec.same(s:search_files("zebra", 5), { "/new/plan.txt" })
  spec.same(s:search_files("keep", 5), {})
  s:append("pc", "Delete File", { "/new" })
  spec.same(s:search_files("zebra", 5), {})
end)

spec.test("a folder's move and delete take the paths under it byte for byte, and no neighbour", function()
  local s = fresh()
  local odd = "/d\255\195\169"
  for _, p in ipairs({ odd .. "/x", odd .. "0", odd .. ".txt", odd .. "-b", odd .. "/y/z" }) do
    s:append("pc", "Write File", { p, "kept words" })
  end
  s:append("pc", "Move File", { odd, "/e" })
  spec.same(s:paths(), { odd .. "-b", odd .. ".txt", odd .. "0", "/e/x", "/e/y/z" })
  spec.same(s:search_files("e", 5), { "/e/x", "/e/y/z" })
  s:append("pc", "Delete File", { "/e" })
  spec.same(s:paths(), { odd .. "-b", odd .. ".txt", odd .. "0" })
  spec.eq(#s:search_files("kept", 5), 3)
end)

spec.test("a content written twice is tokenized once, and a refold tokenizes no content again", function()
  local s = fresh()
  s:append("pc", "Write File", { "/a", "same words here" })
  s:append("pc", "Write File", { "/b", "same words here" })
  spec.eq(s.db:exec("select count(*) as n from recall_blobs")[1].n, 1)
  local calls, real = 0, alog.tokens
  recall.tokens = function(t) calls = calls + 1; return real(t) end
  s:rebuild()
  recall.tokens = real
  spec.eq(calls, 2, "only the two paths")
  spec.same(s:search_files("words", 5), { "/a", "/b" })
end)

-- Every statement arock-log sends, with its bound values: the agent's words reach
-- SQLite only as values, and no statement asks SQLite to parse text.
spec.test("SQLite never parses the agent's text: it arrives only as bound values", function()
  local real, seen = sqlite.open(":memory:"), {}
  local db = { exec = function(_, sql, p) seen[#seen + 1] = sql; return real:exec(sql, p) end }
  local s = fresh(db)
  local mark = "Qx7marker"
  s:append("pc", "Write File", { "/" .. mark .. ".txt", mark .. " ' \" ) OR * NEAR( {} json_each" })
  s:append("pc", "Run Command", { mark .. " --x", "/", "0", "1", mark .. "%_", "" })
  s:append("pc", "Move File", { "/" .. mark .. ".txt", "/b/" .. mark })
  s:recall(mark .. " OR NEAR(x) \"", 5)
  s:search_files(mark .. "*", 5)
  s:rebuild()
  recall.settle(s.db, true)
  spec.eq(#s:recall(mark, 5).events, 3)
  for _, sql in ipairs(seen) do
    local low = sql:lower()
    spec.ok(not sql:find(mark, 1, true), "agent text in SQL: " .. sql)
    for _, word in ipairs({ "fts5", " match ", "json_", " like ", " glob ", "regexp", "substr", "instr(" }) do
      spec.ok(not low:find(word, 1, true), word .. " in SQL: " .. sql)
    end
  end
end)

-- The schema at version 2, with FTS5 recall, and one event written as it wrote them.
local OLD = [[
create table events (seq integer primary key, at text not null, task text not null, keyword text not null,
  actor text not null default 'agent' check (actor in ('agent', 'user', 'host')));
create table args (seq integer not null references events (seq), pos integer not null, value text not null,
  primary key (seq, pos)) without rowid;
create table blobs (id text primary key, content text not null) without rowid;
create table loads (seq integer not null references events (seq), path text not null,
  blob text not null references blobs (id), primary key (seq, path)) without rowid;
create table alog_state (version integer not null);
create virtual table recall_log using fts5 (keyword, args, content = '');
create table tasks (task text primary key, machine text, state text, result text, detail text);
create table files (path text primary key, dir integer not null default 0, blob text, seq integer not null);
create table artifacts (name text primary key, seq integer not null, task text not null);
create table undone (seq integer primary key);
create virtual table recall_files using fts5 (path, content);
create table snapshots (seq integer primary key);
create table snap_tasks (seq integer not null, task text, machine text, state text, result text, detail text);
create table snap_files (seq integer not null, path text, dir integer, blob text, fseq integer);
create table snap_artifacts (seq integer not null, name text, aseq integer, task text);
create table snap_undone (seq integer not null, undone integer);
create view entries as select f.path, f.dir, b.content as data, length(cast(b.content as blob)) as size, e.at, f.seq
  from files f left join blobs b on b.id = f.blob join events e on e.seq = f.seq;
insert into alog_state values (2);
insert into events values (1, 't', 'pc', 'Write File', 'agent');
insert into blobs values ('b1', 'the fern needs water');
insert into args values (1, 1, '/fern.txt'), (1, 2, 'b1');
insert into recall_log (rowid, keyword, args) values (1, 'Write File', '/fern.txt the fern needs water');
insert into files values ('/fern.txt', 0, 'b1', 1);
insert into recall_files (path, content) values ('/fern.txt', 'the fern needs water');
insert into events values (2, 't', 'pc', 'Say', 'user');
insert into args values (2, 1, 'water the garden');
insert into recall_log (rowid, keyword, args) values (2, 'Say', 'water the garden');
]]

spec.test("a store made with FTS5 recall opens with it dropped and its index built from the log", function()
  local db = sqlite.open(":memory:")
  db:exec(OLD)
  local s = fresh(db)
  spec.eq(db:exec("select count(*) as n from sqlite_master where sql like '%fts5%' or name like 'recall_log%'")[1].n, 0)
  spec.eq(db:exec("select version from alog_state")[1].version, require("arock-log.schema").version)
  spec.eq(s:count(), 2)
  spec.eq(s:file("/fern.txt"), "the fern needs water")
  local found = s:recall("fern", 5)
  spec.eq(#found.events, 1); spec.eq(found.events[1].seq, 1)
  spec.eq(found.files[1].path, "/fern.txt")
  spec.eq(s:recall("water", 5).events[1].seq, 2)
  s:append("pc", "Say", { "fern again" })
  spec.eq(#s:recall("fern", 5).events, 2)
end)

spec.test("the index kept as events arrive is exactly the one built from the log, and rebuild keeps it", function()
  local s = fresh()
  local seqs = {}
  for i = 1, 40 do
    local p = "/d" .. (i % 3) .. "/f" .. (i % 5)
    if i % 3 == 1 then s:append("pc", "Make Folder", { "/d" .. (i % 3) }) end
    seqs[#seqs + 1] = s:append("pc", "Write File", { p, ("v%d words %d"):format(i % 4, i % 7) })
    s:append("pc", "Run Command", { "cat " .. p, "/", "0", "1", ("out %d"):format(i), "" })
    if i % 7 == 0 then s:append("pc", "Delete File", { "/d" .. (i % 3) }) end
    if i % 11 == 0 then s:append("pc", "Move File", { "/d1", "/e" .. i }) end
    if i % 13 == 0 then s:undo(seqs[#seqs - 2]) end
    if i == 20 then s:snapshot() end
    if i == 30 then recall.settle(s.db, true) end
  end
  local live = s:dump()
  spec.ok(live:find("words", 1, true), "the dump holds the index")
  s:rebuild()
  spec.eq(s:dump(), live)
  s.db:exec("update alog_state set version = 0")
  local again = fresh(s.db)
  spec.eq(again:dump(), live)
end)

spec.run()
