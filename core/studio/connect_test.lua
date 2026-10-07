-- studio.connect over a fake of connectory's port: a call with no credential asks the person to connect (once), a
-- call that changes something waits for approval and runs once approved, a declined one is not made, and none of it
-- puts a credential where the model, a row or the log could read it. Then a whole run: the system prompt names the
-- tool, and the run's result says what still waits on the person.
local spec = require("spec")
local json = require("ports.json")
local connect = require("studio.connect")
local session = require("studio.session")

local KEY = "sk-live-s3cret"

-- connectory's port, faked: acme has a read and a write; its key is whatever the host's store holds
local function port(store)
  local p = { sent = {} }
  local dir = { { slug = "acme", name = "Acme", categories = { "ticketing" }, operations = 2, docs = "https://acme.test" } }
  local methods = { ["acme.tickets_list"] = "GET", ["acme.tickets_create"] = "POST" }
  function p.directory() return dir, { acme = dir[1] } end
  function p.find() return { { service = "acme", name = "Acme", categories = { "ticketing" }, operations = 2,
    docs = "https://acme.test" } } end
  function p.operations(_, service)
    if service ~= "acme" then return nil, "no service called " .. tostring(service) end
    return { { op = "acme.tickets_create", name = "Create a ticket", about = "Opens one.", args = { "title*", "body" } },
      { op = "acme.tickets_list", name = "List tickets", about = "", args = { "state" } } }
  end
  function p.method(_, op) return methods[op] end
  function p.reads(_, op) return methods[op] == "GET" end
  function p.call(_, op, args)
    local rec = { service = "acme", op = op, method = methods[op], seconds = 0.1 }
    if not store.ACME_TOKEN then
      return nil, { code = "denied", message = "Acme needs ACME_TOKEN", needs = { service = "acme", name = "Acme",
        docs = "https://acme.test/keys", fields = { { name = "ACME_TOKEN", label = "token", secret = true } },
        missing = { "ACME_TOKEN" } } }, rec
    end
    p.sent[#p.sent + 1] = { op = op, args = args, key = store.ACME_TOKEN }
    rec.status = 200
    return { id = 7, title = args.title }, rec
  end
  return p
end

local function harness()
  local store, asked, answers = {}, {}, {}
  local s = { todo = "r", n = 1, o = { connect = {
    port = port(store),
    ask = function(a) asked[#asked + 1] = a return { how = "they run ./moonsplice connect " .. a.service } end,
    approval = function(service, op) return answers[service .. " " .. op] end } } }
  s.t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  s.port = s.o.connect.port
  return s, connect.tool(s), store, asked, answers
end

spec.test("find and calls read the directory; a call with no credential asks the person, once", function()
  local s, tool, _, asked = harness()
  spec.ok(tool.execute({ action = "find", words = "tickets" }).content:find("acme (Acme): ticketing", 1, true))
  spec.ok(tool.execute({ action = "calls", service = "acme" }).content:find("acme.tickets_create: Create a ticket "
    .. "(title*, body)", 1, true))
  local r = tool.execute({ action = "call", op = "acme.tickets_list", args = { state = "open" }, why = "the chart" })
  spec.ok(r.content:find("Acme is not connected (token)", 1, true), r.content)
  spec.ok(r.content:find("they run ./moonsplice connect acme", 1, true))
  spec.ok(r.content:find("must not ask for it in the conversation", 1, true))
  spec.same({ #asked, asked[1].kind, asked[1].fields[1].name, asked[1].docs }, { 1, "connect", "ACME_TOKEN",
    "https://acme.test/keys" })
  s.n = 2
  tool.execute({ action = "call", op = "acme.tickets_list", args = {} })
  spec.eq(#asked, 1)
  spec.eq(#connect.open(s), 1)
  local row = s.t.db:exec("select kind, service, fields, docs, how from tablua_ask")[1]
  spec.same({ row.kind, row.service, json.decode(row.fields)[1].label }, { "connect", "acme", "token" })
  spec.eq(#s.t.db:exec("select 1 from tablua_connect where outcome = 'needs'"), 2)
end)

spec.test("once connected, a read runs; the credential never reaches the model, a row or the log", function()
  local s, tool, store = harness()
  tool.execute({ action = "call", op = "acme.tickets_list", args = {} })
  store.ACME_TOKEN = KEY
  local r = tool.execute({ action = "call", op = "acme.tickets_list", args = { state = "open" } })
  spec.ok(r.content:find("Acme answered 200", 1, true), r.content)
  spec.eq(#connect.open(s), 0)
  spec.eq(s.port.sent[1].key, KEY)
  for _, tbl in ipairs({ "tablua_connect", "tablua_ask" }) do
    for _, row in ipairs(s.t.db:exec("select * from " .. tbl)) do
      for k, v in pairs(row) do spec.ok(not tostring(v):find(KEY, 1, true), tbl .. "." .. k) end
    end
  end
  spec.ok(not r.content:find(KEY, 1, true))
end)

spec.test("a call that changes something waits for approval, runs once approved, and a declined one is not made",
  function()
    local s, tool, store, asked, answers = harness()
    store.ACME_TOKEN = KEY
    local r = tool.execute({ action = "call", op = "acme.tickets_create", args = { title = "help" }, why = "report" })
    spec.ok(r.content:find("POST acme.tickets_create changes something in Acme", 1, true), r.content)
    spec.same({ #asked, asked[1].kind, asked[1].op, asked[1].why }, { 1, "approve", "acme.tickets_create", "report" })
    spec.eq(#s.port.sent, 0)
    answers["acme acme.tickets_create"] = "once"
    r = tool.execute({ action = "call", op = "acme.tickets_create", args = { title = "help" } })
    spec.ok(r.content:find("Acme answered 200", 1, true), r.content)
    spec.eq(#s.port.sent, 1)
    spec.eq(#connect.open(s), 0)
    answers["acme acme.tickets_create"] = "deny"
    r = tool.execute({ action = "call", op = "acme.tickets_create", args = { title = "again" } })
    spec.ok(r.content:find("The person declined acme.tickets_create", 1, true))
    spec.eq(#s.port.sent, 1)
    spec.err(function() tool.execute({ action = "call", op = "acme.nope" }) end, "no call is named acme.nope")
  end)

spec.test("a run with connect: the prompt names the tool, and the result says what waits on the person", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local engine = { rows = function() return { schema = "msr/1", digest = "d0", tables = { comp = {} } } end,
    brief = function() return "comp" end, lint = function() return {} end, check = function() return {} end }
  local seen, script = {}, {
    { calls = { { "connect", { action = "call", op = "acme.tickets_list", args = {} } } } },
    { text = "Acme is not connected yet; the person has been asked." },
    { text = "Still waiting on the person to connect Acme." } }
  local m = { chat = function(_, req)
    seen[#seen + 1] = req
    local r = assert(table.remove(script, 1), "the model was asked more than its script")
    local calls
    for i, c in ipairs(r.calls or {}) do
      calls = calls or {}
      calls[i] = { id = "c" .. i, type = "function", ["function"] = { name = c[1], arguments = json.encode(c[2]) } }
    end
    return r.text or "", { tool_calls = calls or {}, finish = calls and "tool_calls" or "stop" }
  end }
  local store, logged = {}, {}
  local s = session.new{ engine = engine, model = m, tablua = t, comp = "/w/c.lua", sheet = "/w/s.png", ask = "x",
    todo = "r", exec = function() return { code = 0, stdout = "" } end, log = function(l) logged[#logged + 1] = l end,
    connect = { port = port(store), ask = function() return { how = "the person runs ./moonsplice connect acme" } end } }
  local out = s:run()
  spec.ok(seen[1].system:find("- connect: reach another app", 1, true))
  spec.ok(seen[1].system:find("Never ask for a key, token or password", 1, true))
  local names = {}
  for _, tl in ipairs(seen[1].tools) do names[#names + 1] = tl["function"] and tl["function"].name or tl.name end
  spec.ok(table.concat(names, ","):find("connect", 1, true), table.concat(names, ","))
  spec.same({ #out.asks, out.asks[1].service, out.asks[1].how }, { 1, "acme", "the person runs ./moonsplice connect acme" })
  local hit
  for _, l in ipairs(logged) do if l:find("[ask] connect acme", 1, true) then hit = true end end
  spec.ok(hit, table.concat(logged, "\n"))
end)

spec.run()
