-- Unit cases for arock-log and its Robot cells, on the LuaJIT test host.
local spec = require("mono.spec")
local alog = require("arock-log")
local robot = require("arock-log.robot")
local sqlite = require("arock-log.ffi")

local function fresh()
  return alog.open(sqlite.open(":memory:"), { clock = function() return "t" end })
end

spec.test("a connection waits for another's write lock rather than failing at once", function()
  local db = sqlite.open(":memory:")
  local rows = db:exec("pragma busy_timeout")
  spec.eq(tonumber(rows[1].timeout or rows[1].busy_timeout or select(2, next(rows[1]))), sqlite.BUSY_MS)
  assert(sqlite.BUSY_MS >= 5000, "a reader waits at least 5 s for a writer")
end)

spec.test("cells escape what Robot would read differently", function()
  local cases = {
    { "plain", "plain" }, { "a b", "a b" }, { "a  b", "a \\x20b" }, { " a", "\\x20a" },
    { "a ", "a\\x20" }, { " ", "\\x20" }, { "", "\\" }, { "\\", "\\\\" }, { "x\ny", "x\\ny" },
    { "${v}", "\\${v}" }, { "@{l}[0]", "\\@{l}[0]" }, { "$ {", "$ {" }, { "#c", "\\#c" },
    { "a#b", "a#b" }, { "a\194\160b", "a\\xa0b" }, { "\226\128\131", "\\u2003" }, { "\1", "\\x01" },
    { "é", "é" },
  }
  for _, c in ipairs(cases) do spec.eq(robot.cell(c[1]), c[2], c[1]) end
end)

spec.test("a keyword must be words with single spaces", function()
  local s = fresh()
  spec.err(function() s:append("t", "write file", {}) end, "capitalised")
  spec.err(function() s:append("t", "Write  File", {}) end, "capitalised")
  spec.err(function() s:append("a task", "Note", {}) end, "plain name")
  spec.err(function() s:append("t", "Note", { 1 }) end, "not a string")
end)

spec.test("a failed append leaves nothing behind", function()
  local s = fresh()
  s.db:exec("create trigger boom before insert on files begin select raise(abort, 'boom'); end")
  spec.err(function() s:append("t", "Write File", { "a", "x" }) end, "boom")
  spec.eq(s:count(), 0)
end)

spec.test("undoing an event in the middle keeps the later ones", function()
  local s = fresh()
  s:append("t", "Write File", { "a", "1" })
  local two = s:append("t", "Write File", { "b", "2" })
  s:append("t", "Write File", { "a", "3" })
  s:undo(two)
  spec.eq(s:file("a"), "3")
  spec.eq(s:file("b"), nil)
end)

spec.test("a third undo in a chain cancels the write again", function()
  local s = fresh()
  local w = s:append("t", "Write File", { "a", "1" })
  local u1 = s:undo(w)
  local u2 = s:undo(u1)
  spec.eq(s:file("a"), "1")
  s:undo(u2)
  spec.eq(s:file("a"), nil)
end)

spec.test("recall ignores query syntax and marks undone events", function()
  local s = fresh()
  local w = s:append("t", "Remember", { "auth", "use tokens" })
  s:undo(w)
  local found = s:recall('auth" OR (', 5)
  spec.eq(#found.events, 1)
  spec.eq(found.events[1].undone, true)
  spec.eq(#s:recall("!!", 5).events, 0)
end)

spec.test("state follows tasks through their states and results", function()
  local s = fresh()
  s:append("t", "Start Task", { "code" })
  s:append("t", "Enter State", { "run_tests" })
  s:append("t", "Test Result", { "pass" })
  local t = s:task("t")
  spec.eq(t.machine, "code"); spec.eq(t.state, "run_tests"); spec.eq(t.result, "pass")
end)

spec.test("history reads one task's events with their arguments", function()
  local s = fresh()
  s:append("a", "Start Task", { "code", "goal" })
  s:append("b", "Note", {})
  s:append("a", "Note", { "", "x" }, "user")
  local h = s:history("a")
  spec.eq(#h, 2)
  spec.eq(h[1].args[2], "goal"); spec.eq(h[2].args[1], ""); spec.eq(h[2].actor, "user")
  spec.eq(#s:history("b")[1].args, 0)
end)

spec.test("an actor must be agent, user or host", function()
  local s = fresh()
  spec.err(function() s:append("t", "Note", {}, "robot") end, "actor")
  spec.err(function() s.db:exec("insert into events (at, task, keyword, actor) values ('t', 't', 'N', 'x')") end, "CHECK")
end)

spec.test("files at a seq ignore later undos and see deletes", function()
  local s = fresh()
  local w = s:append("t", "Write File", { "a", "1" })
  s:append("t", "Write File", { "b", "2" })
  local d = s:append("t", "Delete File", { "b" })
  s:undo(w)
  spec.eq(s:files_at(d).a, "1"); spec.eq(s:files_at(d).b, nil)
  spec.eq(s:files_at(d - 1).b, "2")
  spec.eq(s:files_at(s:count()).a, nil)
end)

spec.test("the artifact at a seq is the version live just before it", function()
  local s = fresh()
  local one = s:append("t", "Publish Artifact", { "app" })
  local two = s:append("t", "Publish Artifact", { "app" })
  s:undo(two)
  spec.eq(s:artifact_at("app", two).seq, one)
  spec.eq(s:artifact_at("app", two + 1).seq, two)
  spec.eq(s:artifact("app").seq, one)
  spec.eq(s:artifact_at("app", one), nil)
end)

spec.test("a workspace load is its own call, fixed once logged, and undone as one event", function()
  local s = fresh()
  spec.err(function() s:append("t", "Load Workspace", { "repo", "0" }) end, "alog:load")
  local seq = s:load("t", "repo@abc", { { path = "a.py", blob = "b1", content = "x = 1\n" },
    { path = "b.py", blob = "b2", content = "y = 2\n" } })
  spec.eq(s:file("a.py"), "x = 1\n")
  spec.same(s:paths(), { "a.py", "b.py" })
  spec.err(function() s.db:exec("update blobs set content = 'z'") end, "the log is append")
  spec.err(function() s.db:exec("delete from loads") end, "the log is append")
  s:undo(seq)
  spec.eq(s:file("a.py"), nil)
  spec.eq(s:files_at(seq)["b.py"], "y = 2\n")
end)

spec.test("events after a seq are only the newer ones, for a reader that follows the log", function()
  local s = fresh()
  local one = s:append("t", "Say", { "a" }, "user")
  s:append("t", "Say", { "b" })
  local newer = s:events(one)
  spec.eq(#newer, 1)
  spec.same(newer[1].args, { "b" })
  spec.eq(#s:events(), 2)
end)

spec.test("a note's every version comes back as it was typed", function()
  local s = fresh()
  local texts = { "# Pebbles\n\n- answers email first\n", "Pebbles answers email first.  She never rushes me.\r\n\t", "" }
  s:append("note-1", "Add Note", { "note-1", "Rocks/Pebbles", texts[1] }, "user")
  s:append("note-1", "Edit Note", { "note-1", texts[2] }, "user")
  s:append("note-1", "Edit Note", { "note-1", texts[3] }, "user")
  s:append("note-1", "Move Note", { "note-1", "Workflows" }, "user")
  local got = {}
  for _, e in ipairs(s:history("note-1")) do
    if e.keyword ~= "Move Note" then got[#got + 1] = s:blob(alog.fields(e).text) end
  end
  spec.eq(#got, 3)
  for i, t in ipairs(texts) do spec.eq(got[i], t, "version " .. i) end
  spec.err(function() s:append("note-1", "Edit Note", { "note-1" }) end, "takes note, text")
end)

spec.run()
