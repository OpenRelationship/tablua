-- The SQLite settings Litestream needs of a log it streams, and a reader
-- beside the writer. Where the host gives no files (a test host whose
-- databases are all in memory), the WAL checks are skipped: memory has no WAL.
local spec = require("mono.spec")
local alog = require("arock-log")
local sqlite = require("arock-log.ffi")

local function tmpfile()
  local path = os.tmpname()
  os.remove(path)
  return path
end

local function on_disk(s) return s:settings().journal_mode ~= "memory" end

spec.test("a replicated log is in WAL, syncs normally, never checkpoints and waits for locks", function()
  local s = alog.open(sqlite.open(tmpfile()), { replicated = true })
  local got = s:settings()
  spec.eq(got.synchronous, 1)
  spec.eq(got.wal_autocheckpoint, 0)
  spec.ok(got.busy_timeout >= 5000, "busy_timeout " .. tostring(got.busy_timeout))
  if on_disk(s) then spec.eq(got.journal_mode, "wal") end
  spec.same(alog.LITESTREAM, {
    "pragma journal_mode = wal", "pragma synchronous = normal",
    "pragma wal_autocheckpoint = 0", "pragma busy_timeout = 5000",
  })
end)

spec.test("a log not asked to replicate keeps the host's settings", function()
  local s = alog.open(sqlite.open(":memory:"))
  spec.ok(s:settings().wal_autocheckpoint ~= 0, "autocheckpoint left on")
end)

spec.test("a reader beside the writer sees only what is committed, without waiting", function()
  local path = tmpfile()
  local w = alog.open(sqlite.open(path), { replicated = true })
  if not on_disk(w) then return end
  w:append("pc", "Write File", { "/a", "1" })
  local r = alog.open(sqlite.open(path), { replicated = true })
  w.db:exec("begin immediate")
  w.db:exec("insert into events (at, task, keyword, actor) values ('t', 'pc', 'Note', 'host')")
  spec.eq(r:count(), 1)
  spec.eq(r:file("/a"), "1")
  w.db:exec("commit")
  spec.eq(r:count(), 2)
  os.remove(path); os.remove(path .. "-wal"); os.remove(path .. "-shm")
end)

spec.test("appends leave the WAL for Litestream to checkpoint", function()
  local path = tmpfile()
  local s = alog.open(sqlite.open(path), { replicated = true })
  if not on_disk(s) then return end
  for i = 1, 300 do s:append("pc", "Write File", { "/f", ("x"):rep(4000) .. i }) end
  local wal = io.open(path .. "-wal", "rb")
  spec.ok(wal, "a WAL file")
  local size = #wal:read("*a")
  wal:close()
  -- past SQLite's default 1000-page autocheckpoint, so a checkpoint would have reset it
  spec.ok(size > 1000 * 4096, "WAL holds " .. size .. " bytes")
  os.remove(path); os.remove(path .. "-wal"); os.remove(path .. "-shm")
end)

spec.run()
