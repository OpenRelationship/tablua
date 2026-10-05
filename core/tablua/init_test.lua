-- Unit cases for tablua: typed rows in a real SQLite file (arock-log's LuaJIT host), progress worked out from the
-- rows, and TabPFN's training rows read back by a query, shared files included.
local spec = require("mono.spec")
local tablua = require("tablua")
local sqlite = require("arock-log.ffi")

local function fresh(path) return tablua.open(sqlite.open(path or ":memory:"), { clock = function() return "t" end }) end

local function step(t, task, n, verb, before, after, outcome)
  t:state{ task = task, n = n, stage = "building", passed = before, total = 2 }
  t:candidates(task, n, { { move = verb, jev_p = 0.5, jev_margin = 0.1 } })
  t:decision{ task = task, n = n, chosen = verb, by = "jev" }
  return t:outcome{ task = task, n = n, verb = verb, outcome = outcome, passed = after, total = 2 }
end

spec.test("a decision's state, candidates and choice are typed rows", function()
  local t = fresh()
  t:state{ task = "r1", n = 1, stage = "building", passed = 1, total = 2, last_verb = "write_steps" }
  t:candidates("r1", 1, { { move = "rewrite", jev_p = 0.6 }, { move = "write_page", jev_p = 0.3 } })
  t:decision{ task = "r1", n = 1, chosen = "rewrite", by = "jev", propensity = 1 }
  spec.eq(t:count("state"), 1)
  spec.eq(t:count("candidate"), 2)
  spec.eq(t:count("decision"), 1)
  local s = t.db:exec("select stage, pass from tablua_state where task = 'r1'")[1]
  spec.eq(s.stage, "building")
  spec.eq(s.pass, 0.5)
end)

spec.test("progress: more passing, or a complete step that was not a change going nowhere", function()
  spec.eq(tablua.progress({ verb = "rewrite", outcome = "broken", passed = 2 }, { passed = 1, total = 2 }), 1)
  spec.eq(tablua.progress({ verb = "rewrite", outcome = "complete", passed = 1 }, { passed = 1, total = 2 }), 0)
  spec.eq(tablua.progress({ verb = "rewrite", outcome = "no_effect", passed = 1 }, { passed = 1, total = 2 }), 0)
  spec.eq(tablua.progress({ verb = "run_test", outcome = "complete", passed = 1 }, { passed = 1, total = 2 }), 1)
  spec.eq(tablua.progress({ verb = "publish", outcome = "complete" }, { passed = 2, total = 2 }), 1)
end)

spec.test("training rows are a query: progress per step, and ship from the run's ending", function()
  local t = fresh()
  spec.eq(step(t, "r1", 1, "write_steps", 0, 1, "complete"), 1)
  spec.eq(step(t, "r1", 2, "rewrite", 1, 1, "no_effect"), 0)
  local train, labels = t:training("progress")
  spec.same(labels, { 1, 0 })
  spec.eq(train.rows[1][1], "write_steps")
  spec.eq(train.rows[1][2], "building")
  spec.eq(#train.columns, #train.rows[1])
  local _, none = t:training("ship")
  spec.same(none, {})
  t:run{ task = "r1", shipped = true, answered = true, works = true }
  local _, ship = t:training("ship")
  spec.same(ship, { 1, 1 })
end)

spec.test("before Jev answers, a step is its first columns alone, and a move's row for a state is built alike", function()
  local t = fresh()
  step(t, "r1", 1, "write_steps", 0, 1, "complete")
  t:features("r1", 1, { done = 0.5 }, "score")
  local train, labels = t:training("progress", { before = true })
  spec.same(labels, { 1 })
  spec.eq(#train.columns, tablua.before)
  spec.eq(#train.rows[1], tablua.before)
  spec.eq(train.columns[tablua.before], "n")
  local row = tablua.row({ stage = "building", pass = 0.5, stalls = 2, last_verb = "run_test", last_outcome = "broken",
    cause = "the_steps", own_checks = 1, n = 7 }, "rewrite")
  spec.same(row, { "rewrite", "building", 0.5, 2, "run_test", "broken", "the_steps", 1, 7 })
  spec.eq(#tablua.row({}, "think"), tablua.before)
end)

spec.test("another file's rows are read first, then this one's", function()
  -- Moss's test host keeps the files it opens in a folder of its own, which an attach by path does not reach;
  -- Moss attaches the node's real shared file (Moss.Computer.Tablua), tested there
  if rawget(_G, "__test") then return end
  local shared = os.tmpname()
  os.remove(shared)
  local other = fresh(shared)
  step(other, "r9", 1, "write_page", 0, 1, "complete")
  local t = fresh()
  step(t, "r1", 1, "rewrite", 1, 1, "no_effect")
  t:attach("shared", shared)
  local train, labels = t:training("progress")
  spec.same(labels, { 1, 0 })
  spec.eq(train.rows[1][1], "write_page")
  os.remove(shared)
end)

spec.test("Jev's fan-out answers are feature columns of the step; a missing one is -1", function()
  local t = fresh()
  step(t, "r1", 1, "write_page", 0, 1, "complete")
  t:features("r1", 1, { done = 0.5, ask_dates = 1 }, "score")
  local train = t:training("progress")
  local at = {}
  for i, c in ipairs(train.columns) do at[c] = i end
  spec.eq(train.rows[1][at.done], 0.5)
  spec.eq(train.rows[1][at.ask_dates], 1)
  spec.eq(train.rows[1][at.ask_delete], -1)
  spec.eq(t:count("feature"), 2)
end)

spec.test("a program kept as rows compiles back to the same org, and a file put again replaces its rows", function()
  local src = require("tablua.source")
  local t = fresh()
  local rows = src.from_files({
    notes = "Plants, watered on time.\n",
    feature = "Feature: Plants\n\n  Scenario: one\n    When I open the page\n    Then I see \"Plants\"\n",
    lua = 'local d = db.open("data/plants.dbl")\nfunction post.water(req) end\n',
  })
  t:put_program("ui/index.org", rows)
  spec.eq(t:compile("ui/index.org"), src.compile(rows))
  spec.eq(t:count("unit"), 2)
  spec.eq(t:count("line"), 2)
  local line = t.db:exec("select keyword, text from tablua_line where file = 'ui/index.org' and n = 2")[1]
  spec.same(line, { keyword = "Then", text = 'I see "Plants"' })
  t:put_program("ui/index.org", src.from_files({ lua = "print(1)\n" }))
  spec.eq(t:count("unit"), 1)
  spec.eq(t:count("scenario"), 0)
  spec.same(t:files(), { "ui/index.org" })
  spec.eq(t:compile("ui/none.org"), nil)
end)

spec.test("links with nothing at their end are breaks, and a step written later in another file mends a line", function()
  local src = require("tablua.source")
  local t = fresh()
  t:put_program("ui/index.org", src.decode(table.concat({
    "* Feature", "#+begin_src feature", "Feature: Plants", "", "  Scenario: water",
    '    Given there is a plant named "Fern"', "    When I open the page", "#+end_src",
    "* Code", "#+begin_src lua", "function post.water(req) print(req.form.plant, req.form.when) end", "#+end_src",
    "* Page", "#+begin_src lua", 'return ui.form{ post = "water", ui.input{ name = "plant" } },',
    '  ui.button{ post = "remove" }', "#+end_src", "" }, "\n")))
  local why = {}
  for _, b in ipairs(t:breaks()) do why[#why + 1] = b.kind .. " " .. b.target end
  spec.same(why, { 'line there is a plant named "Fern"', "post post.remove", "reads when" })
  t:put_program("code/steps/plants.lua", src.from_files({ steps = 'test.step("there is a plant named {string}", '
    .. "function(w, n) end)\n" }))
  spec.eq(#t:breaks(), 2)
  -- an action nothing posts to is an orphan; one the page calls to read what it shows is reached
  t:put_program("code/more.lua", src.from_files({ lua = "function post.extra(req) end\nfunction get.view() end\n" }))
  t:put_program("ui/list.org", src.decode("* Page\n#+begin_src lua\nreturn ui.ul{ get.view() }\n#+end_src\n"))
  local orphans = {}
  for _, b in ipairs(t:breaks()) do if b.kind == "orphan" then orphans[#orphans + 1] = b.target end end
  spec.same(orphans, { "post.extra" })
end)

spec.test("Jev's hindsight labels each step once, in batches, and contrib trains on the labelled steps only", function()
  local hindsight = require("tablua.hindsight")
  local t = fresh()
  for n = 1, 3 do step(t, "r1", n, n == 2 and "undo" or "write_page", 0, 1, "complete") end
  t:run{ task = "r1", shipped = true, answered = true, works = true }
  local asked = {}
  local jev = { decide = function(_, state, q)
    asked[#asked + 1] = { state = state, q = q }
    local out = {}
    for id in pairs(q) do out[id] = { noul = id == "s2" and 0.1 or 0.9 } end
    return out, { cost = 0.001 }
  end }
  hindsight.batch = 2
  local n, cost = hindsight.label(t, jev, "r1")
  spec.eq(n, 3)
  spec.eq(#asked, 2)
  spec.ok(asked[1].state:find("shipped yes", 1, true))
  spec.ok(asked[1].state:find("2. [building] undo -> complete", 1, true))
  spec.eq(cost, 0.002)
  spec.eq(hindsight.label(t, jev, "r1"), 0)
  local train, labels = t:training("contrib")
  spec.eq(#train.rows, 3)
  spec.same(labels, { 1, 0, 1 })
  spec.same(train.keys[2], { task = "r1", n = 2 })
  local _, none = fresh():training("contrib")
  spec.same(none, {})
  hindsight.batch = 25
end)

spec.test("the log's step windows become each step's effects, and an effect is a head", function()
  local telemetry = require("tablua.telemetry")
  local t = fresh()
  t.db:exec([[create table events (seq integer primary key, at text, task text, keyword text, actor text default 'agent');
    create table args (seq integer, pos integer, value text, primary key (seq, pos))]])
  local seq = 0
  local function ev(keyword, ...)
    seq = seq + 1
    t.db:exec("insert into events (seq, at, task, keyword) values (?, 't', 'x', ?)", { seq, keyword })
    for i, v in ipairs({ ... }) do t.db:exec("insert into args values (?, ?, ?)", { seq, i, v }) end
  end
  local red = '{"total":1,"passed":0,"undefined":[],"failing":[{"scenario":"add","step":"When I open the page","why":"no page"}]}'
  ev("Decide", "r1/step/1", "jev")
  ev("Outcome", "/home/features/a.feature", "red", red)
  ev("Run Command", "cd '/home' && test", "/home", "1")
  ev("Outcome", "r1/step/1", "broken")
  ev("Decide", "r1/step/2", "jev")
  ev("Outcome", "/home/features/a.feature", "green", '{"total":1,"passed":1,"undefined":[],"failing":[]}')
  ev("Serve Request", "GET", "/", "200")
  ev("Outcome", "r1/step/2", "complete")
  step(t, "r1", 1, "run_test", 0, 0, "broken")
  step(t, "r1", 2, "write_page", 0, 1, "complete")
  spec.eq(telemetry.derive(t, "r1"), 2)
  spec.eq(telemetry.derive(t, "r1"), 0)
  local e = {}
  for _, r in ipairs(t.db:exec("select keyword, arg from tablua_effect where task = 'r1' and n = 2")) do e[r.keyword] = r.arg end
  spec.eq(e["Scenario Turned Green"], "add")
  spec.eq(e["Line Fixed"], "open")
  spec.ok(e["All Green"] and e["More Passing"])
  local first = {}
  for _, r in ipairs(t.db:exec("select keyword, arg from tablua_effect where task = 'r1' and n = 1")) do first[r.keyword] = r.arg end
  spec.ok(first["Tests First Ran"] and first["Command Failed"] == "test")
  local _, labels = t:training("effect:All Green")
  spec.same(labels, { 0, 1 })
end)

spec.test("the harness's gates are rows, each saying what turned it off", function()
  local t = fresh()
  t:gate{ name = "stuck_fix", predicate = "fixing the same failure again waits on thinking it through" }
  t:gate{ name = "give_up", predicate = "giving up leaves only a rewrite", retired_by = "gates_off" }
  spec.eq(t:count("gate"), 2)
  local g = t.db:exec("select retired_by from tablua_gate where name = 'give_up'")[1]
  spec.eq(g.retired_by, "gates_off")
end)

spec.test("fits are kept by head and schema", function()
  local t = fresh()
  spec.eq(t:fitted("progress", "1"), nil)
  t:fit("progress", "1", "fit-abc", 40)
  spec.same(t:fitted("progress", "1"), { id = "fit-abc", rows = 40 })
end)

spec.test("a connection that holds the shared file from an earlier open attaches it again", function()
  local path = os.tmpname()
  os.remove(path)
  local db = sqlite.open(":memory:")
  tablua.open(db):attach("shared", path)
  local t = tablua.open(db)
  t:attach("shared", path)
  spec.same(t.sources, { "main", "shared" })
  os.remove(path)
end)

spec.run()
