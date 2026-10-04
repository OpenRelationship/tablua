-- Snapshots: the state at a seq, kept so rebuild and undo fold only the
-- events after it, and dropped when an undo reaches behind it.
local spec = require("mono.spec")
local alog = require("arock-log")
local sqlite = require("arock-log.ffi")

local function fresh()
  return alog.open(sqlite.open(":memory:"), { clock = function() return "t" end })
end

local function n(s, sql) return s.db:exec(sql)[1].n end

local function work(s, from, to)
  for i = from, to do
    s:append("pc", "Write File", { "/f" .. (i % 4), "v" .. i })
    if i % 5 == 0 then s:append("pc", "Delete File", { "/f" .. (i % 3) }) end
  end
  s:append("t", "Start Task", { "code" })
  s:append("t", "Publish Artifact", { "app" })
end

spec.test("an empty log has nothing to snapshot", function()
  spec.eq(fresh():snapshot(), nil)
end)

spec.test("rebuild from a snapshot gives the same state as folding the whole log", function()
  local s = fresh()
  work(s, 1, 20)
  local at = s:snapshot()
  spec.eq(at, s:count())
  work(s, 21, 30)
  local live = s:dump()
  s:rebuild()
  spec.eq(s:dump(), live)
  s.db:exec("delete from snapshots")
  s:rebuild()
  spec.eq(s:dump(), live)
end)

spec.test("rebuild after a snapshot reads only the events after it", function()
  local s = fresh()
  work(s, 1, 20)
  s:snapshot()
  local read = 0
  local real = s.db
  s.db = { exec = function(_, sql, p)
    if sql:find("from events e left join args", 1, true) then read = read + 1; assert(p and p[1], "reads after a seq") end
    return real:exec(sql, p)
  end }
  s:rebuild()
  spec.eq(read, 1)
end)

spec.test("only the newest snapshot is kept", function()
  local s = fresh()
  work(s, 1, 5)
  s:snapshot()
  work(s, 6, 9)
  local at = s:snapshot()
  spec.eq(n(s, "select count(*) as n from snapshots"), 1)
  spec.eq(n(s, "select count(distinct seq) as n from snap_files"), 1)
  spec.eq(s.db:exec("select seq from snapshots")[1].seq, at)
end)

spec.test("an undo that reaches behind the snapshot refolds from the start", function()
  local s = fresh()
  local w = s:append("pc", "Write File", { "/a", "1" })
  local u = s:undo(w)
  s:append("pc", "Write File", { "/b", "2" })
  s:snapshot()
  s:undo(u)
  spec.eq(s:file("/a"), "1")
  local live = s:dump()
  s.db:exec("delete from snapshots")
  s:rebuild()
  spec.eq(s:dump(), live)
end)

spec.test("an undo after the snapshot of an event after it uses the snapshot", function()
  local s = fresh()
  work(s, 1, 10)
  s:snapshot()
  local w = s:append("pc", "Write File", { "/z", "zz" })
  s:undo(w)
  spec.eq(s:file("/z"), nil)
  spec.eq(s.db:exec("select count(*) as n from undone")[1].n, 1)
end)

spec.run()
