-- The kinds a computer logs besides its files: runs, app requests and mail,
-- each checked against its declared arguments.
local spec = require("mono.spec")
local alog = require("arock-log")
local sqlite = require("arock-log.ffi")

local function fresh()
  return alog.open(sqlite.open(":memory:"), { clock = function() return "t" end })
end

spec.test("a run keeps its line, status and time, its output as blobs found by recall", function()
  local s = fresh()
  local seq = s:append("pc", "Run Command", { "lua sum.lua", "/home", "0", "6.8", "the total is 385\n", "" })
  local e = s:events()[1]
  local f = alog.fields(e)
  spec.eq(f.line, "lua sum.lua"); spec.eq(f.status, "0"); spec.eq(f.ms, "6.8")
  spec.eq(s:blob(f.out), "the total is 385\n"); spec.eq(s:blob(f.err), "")
  local hit = s:recall("total 385", 5).events[1]
  spec.eq(hit.seq, seq)
end)

spec.test("a run stopped at its limits is a run with that status", function()
  local s = fresh()
  s:append("pc", "Run Command", { "lua loop.lua", "/home", "124", "120000", "", "lua: stopped after 120 s\n" })
  spec.eq(alog.fields(s:events()[1]).status, "124")
end)

spec.test("a kind's arguments are checked: count, numbers, and optional ones last", function()
  local s = fresh()
  spec.err(function() s:append("pc", "Run Command", { "ls", "/" }) end, "Run Command takes")
  spec.err(function() s:append("pc", "Run Command", { "ls", "/", "ok", "1", "", "" }) end, "status is not a number")
  spec.err(function() s:append("pc", "Write File", { "/a", "x", "extra" }) end, "Write File takes")
  spec.err(function() s:append("pc", "Undo", { "1" }) end, "alog:undo")
  s:append("pc", "Test Result", { "pass" })
  s:append("pc", "Test Result", { "fail", "detail" })
  s:append("pc", "Anything Else", { "free", "form" })
  spec.eq(s:count(), 3)
end)

spec.test("an app request keeps its method, path, status, time, form and page", function()
  local s = fresh()
  s:append("pc", "Serve Request", { "POST", "/todo", "200", "7.4", "item=fern", "<li>fern</li>" }, "user")
  local e = s:events()[1]
  local f = alog.fields(e)
  spec.eq(e.actor, "user"); spec.eq(f.method, "POST")
  spec.eq(s:blob(f.form), "item=fern"); spec.eq(s:blob(f.page), "<li>fern</li>")
end)

spec.test("mail sent and received are events on each computer's log", function()
  local s = fresh()
  s:append("rock-1", "Send Mail", { "rock-2", "fern", "the fern needs water", "delivered", "17" })
  s:append("rock-1", "Receive Mail", { "rock-2", "re: fern", "watered", "18" }, "host")
  local sent, got = alog.fields(s:events()[1]), alog.fields(s:events()[2])
  spec.eq(sent.to, "rock-2"); spec.eq(sent.outcome, "delivered"); spec.eq(sent.letter, "17")
  spec.eq(s:blob(got.body), "watered"); spec.eq(got.from, "rock-2")
  spec.eq(s:recall("water", 5).events[1].keyword, "Send Mail")
end)

spec.test("robot rows name blob ids, so the rows stay small and Robot still reads them", function()
  local s = fresh()
  s:append("pc", "Write File", { "/a", "a very long body" })
  local id = s:events()[1].args[2]
  local rows = s:robot()
  spec.ok(rows:find("Write File    /a    " .. id, 1, true), rows)
  spec.ok(not rows:find("a very long body", 1, true), "content stays out of the rows")
end)

spec.test("fields name a free keyword's arguments by position", function()
  local f = alog.fields({ keyword = "Say", args = { "hi" } })
  spec.eq(f[1], "hi")
end)

spec.run()
