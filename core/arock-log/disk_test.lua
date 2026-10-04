-- A computer's disk on the log: folders, moves, removes, blobs, the entries
-- view a host reads, and the state the log folds to.
local spec = require("mono.spec")
local alog = require("arock-log")
local sqlite = require("arock-log.ffi")

local function fresh(opts)
  opts = opts or {}
  opts.clock = opts.clock or function() return "2026-10-01T00:00:00Z" end
  return alog.open(sqlite.open(":memory:"), opts)
end

local function n(s, sql) return s.db:exec(sql)[1].n end

spec.test("a file's content is kept once as a blob, and the log holds its id", function()
  local s = fresh()
  local one = s:append("pc", "Write File", { "/a.txt", "same words" })
  s:append("pc", "Write File", { "/b.txt", "same words" })
  spec.eq(n(s, "select count(*) as n from blobs"), 1)
  local e = s:events()[1]
  spec.eq(e.seq, one)
  spec.ok(e.args[2] ~= "same words", "the log keeps the id, not the content")
  spec.eq(s:blob(e.args[2]), "same words")
  spec.eq(s:file("/b.txt"), "same words")
  spec.eq(alog.fields(e).content, e.args[2])
  spec.eq(alog.fields(e).path, "/a.txt")
end)

spec.test("the portable hash gives the same id on every Lua", function()
  local blobs = require("arock-log.blobs")
  spec.eq(blobs.hash(""), "0000000000000000-0")
  spec.eq(blobs.hash("the fern needs water"), "69a5347135dbfc29-20")
  spec.eq(blobs.hash(("\255"):rep(1000)), "bc24c2e92178003c-1000")
end)

spec.test("a host's own digest names the blobs, and a clash keeps both contents", function()
  local s = fresh({ hash = function(c) return "h" .. (#c % 2) end })
  s:append("pc", "Write File", { "/a", "xy" })
  s:append("pc", "Write File", { "/b", "zw" })
  s:append("pc", "Write File", { "/c", "xy" })
  spec.eq(s:file("/a"), "xy"); spec.eq(s:file("/b"), "zw"); spec.eq(s:file("/c"), "xy")
  spec.eq(n(s, "select count(*) as n from blobs"), 2)
  spec.eq(s:events()[1].args[2], "h0")
end)

spec.test("folders are made, and a remove takes a folder with all under it", function()
  local s = fresh()
  s:append("pc", "Make Folder", { "/notes" })
  s:append("pc", "Make Folder", { "/notes/old" })
  s:append("pc", "Write File", { "/notes/old/a", "1" })
  s:append("pc", "Write File", { "/notes-b", "2" })
  s:append("pc", "Delete File", { "/notes" })
  spec.same(s:paths(), { "/notes-b" })
  spec.eq(#s:recall("1", 5).files, 0)
end)

spec.test("a move carries a folder and everything in it, replacing a file there", function()
  local s = fresh()
  s:append("pc", "Make Folder", { "/a" })
  s:append("pc", "Write File", { "/a/x", "moved words" })
  s:append("pc", "Write File", { "/b", "old" })
  s:append("pc", "Move File", { "/a/x", "/b" })
  s:append("pc", "Make Folder", { "/c" })
  s:append("pc", "Move File", { "/a", "/c/a" })
  spec.same(s:paths(), { "/b", "/c", "/c/a" })
  spec.eq(s:file("/b"), "moved words")
  spec.eq(s:recall("moved", 5).files[1].path, "/b")
  local at = s:files_at(s:count())
  spec.eq(at["/b"], "moved words"); spec.eq(at["/a/x"], nil); spec.eq(at["/c/a"], nil)
end)

spec.test("the entries view gives a host each path, folder or not, its bytes and when it changed", function()
  local s = fresh()
  s:append("pc", "Make Folder", { "/" })
  s:append("pc", "Write File", { "/t.bin", "a\0b" })
  local rows = s.db:exec("select path, dir, data, size, at from entries order by path")
  spec.eq(#rows, 2)
  spec.eq(rows[1].path, "/"); spec.eq(rows[1].dir, 1); spec.eq(rows[1].data, nil)
  spec.eq(rows[2].data, "a\0b"); spec.eq(rows[2].size, 3); spec.eq(rows[2].at, "2026-10-01T00:00:00Z")
end)

spec.test("binary content is kept exactly but not indexed for recall", function()
  local s = fresh()
  s:append("pc", "Write File", { "/img", "zebra\0\1\2" })
  s:append("pc", "Write File", { "/txt", "zebra" })
  spec.eq(s:file("/img"), "zebra\0\1\2")
  local found = s:recall("zebra", 5).files
  spec.eq(#found, 1); spec.eq(found[1].path, "/txt")
end)

spec.test("rebuild folds the log back into exactly the state the appends left", function()
  local s = fresh()
  local seqs = {}
  for i = 1, 40 do
    local p = "/d" .. (i % 3) .. "/f" .. (i % 5)
    if i % 3 == 1 then seqs[#seqs + 1] = s:append("pc", "Make Folder", { "/d" .. (i % 3) }) end
    seqs[#seqs + 1] = s:append("pc", "Write File", { p, ("v%d"):format(i % 4) })
    if i % 7 == 0 then s:append("pc", "Delete File", { "/d" .. (i % 3) }) end
    if i % 11 == 0 then s:append("pc", "Move File", { "/d1", "/e" .. i }) end
    if i % 13 == 0 then s:undo(seqs[#seqs - 2]) end
  end
  local before = s:dump()
  s:rebuild()
  spec.eq(s:dump(), before)
end)

spec.test("a store from before blobs opens with its state rebuilt and its log kept", function()
  local db = sqlite.open(":memory:")
  db:exec([[create table events (seq integer primary key, at text not null, task text not null,
      keyword text not null, actor text not null default 'agent');
    create table args (seq integer not null, pos integer not null, value text not null, primary key (seq, pos));
    create table files (path text primary key, content text not null);
    create table tasks (task text primary key, machine text, state text, result text, detail text);
    insert into events values (1, 't', 'a', 'Start Task', 'agent');
    insert into args values (1, 1, 'code');
    insert into files values ('x', 'old state');]])
  local s = alog.open(db)
  spec.eq(s:task("a").machine, "code")
  spec.eq(s:file("x"), nil)
  spec.eq(s:count(), 1)
  s:append("a", "Write File", { "y", "new" })
  spec.eq(s:file("y"), "new")
end)

spec.run()
