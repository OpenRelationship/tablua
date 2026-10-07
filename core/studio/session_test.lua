-- A whole studio run over fakes of the engine, the model and Jev: the model writes a treatment, reads the comp,
-- patches it (one breaks it, the next fixes it), hands in before looking and is sent back, looks, and hands in.
-- Each tool call is a step of rows; the transcript is rows; the hand-in comes back once per version of the comp.
local spec = require("spec")
local json = require("ports.json")
local session = require("studio.session")

-- the engine: rows in a table; a node below y 1000 is off the frame (an error)
local function engine()
  local e = { node = {}, prop = {}, v = 0, expects = {} }
  local function findings()
    local out = {}
    for _, p in ipairs(e.prop) do
      if p.name == "y" and p.value > 1000 then
        out[#out + 1] = { tier = "lint", id = p.id, name = "y", code = "off_frame", severity = "error", detail = "below" }
      end
    end
    return out
  end
  function e.rows() return { schema = "msr/1", digest = "d" .. e.v, tables = { comp = { fps = 30 }, node = e.node,
    prop = e.prop, expect = e.expects } } end
  function e.brief() return ("comp 1280x720, %d nodes"):format(#e.node) end
  function e.lint() return findings() end
  function e.check() return {} end
  function e.sheet() return { picks = { 0, 6 }, seconds = 1.5 } end
  function e.expect(_, _, rows)
    for _, x in ipairs(rows) do e.expects[#e.expects + 1] = x end
    e.v = e.v + 1
    return { added = rows, rejected = {}, findings = findings() }
  end
  function e.patch(_, _, patches)
    local before, touched = "d" .. e.v, {}
    for _, p in ipairs(patches) do
      if p.move == "add_node" then
        e.node[#e.node + 1] = { id = p.node.id, kind = p.node.kind, order = #e.node + 1 }
        e.prop[#e.prop + 1] = { id = p.node.id, name = "y", value = p.node.y }
        touched[#touched + 1] = { id = p.node.id }
      elseif p.move == "set_prop" then
        for _, r in ipairs(e.prop) do if r.id == p.id and r.name == p.name then r.value = p.value end end
        touched[#touched + 1] = { id = p.id, name = p.name }
      end
    end
    e.v = e.v + 1
    return { applied = patches, rejected = {}, touched = touched, digest_before = before, digest_after = "d" .. e.v,
      findings = findings() }
  end
  return e
end

local function model(script)
  local m = { seen = {} }
  function m.chat(_, req)
    m.seen[#m.seen + 1] = req
    local r = table.remove(script, 1)
    assert(r, "the model was asked more than its script")
    local calls
    for i, c in ipairs(r.calls or {}) do
      calls = calls or {}
      calls[i] = { id = "c" .. #m.seen .. i, type = "function", ["function"] = { name = c[1], arguments = json.encode(c[2]) } }
    end
    return r.text or "", { tool_calls = calls or {}, finish = calls and "tool_calls" or "stop" }
  end
  return m
end

local judge = { decide = function(_, _, qs)
  local a = {}
  for id, q in pairs(qs) do
    if q.kind == "score" then a[id] = { score = q.levels[4], probabilities = { [q.levels[4]] = 1 } }
    elseif q.kind == "noul" then a[id] = { noul = 0.1 } end
  end
  return a
end }

local CARD = "# Card\n## The moves\nSummary: the typed patches.\nadd_node, set_prop\n## Pitfalls\nSummary: what fails.\nx\n"

spec.test("a run: treatment, brief, a patch that breaks, a fix, a hand-in sent back to look, a look, the hand-in", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local m = model({
    { text = "Treatment: a tide line; everything hangs from it.", calls = { { "brief", {} } } },
    { calls = { { "expect", { rows = { { id = "title-shown", says = "the title is on screen", node = "title" } } } } } },
    { calls = { { "patch", { moves = { { move = "add_node", node = { id = "title", kind = "text", y = 1200 } } } } } } },
    { calls = { { "patch", { moves = { move = "set_prop", id = "title", name = "y", value = 540 } } } } },
    { text = "Done." },
    { calls = { { "look", {} } } },
    { text = "A tide clock: the title hangs from the line." } })
  local s = session.new{ engine = engine(), model = m, judge = judge, tablua = t, comp = "/w/c.lua", sheet = "/w/s.png",
    ask = "a tide clock", reference = CARD, todo = "r", exec = function() return { code = 0, stdout = "UE5H" } end }
  local out = s:run()
  spec.same({ out.stop, out.steps, out.said, out.status }, { "stop", 5, "A tide clock: the title hangs from the line.",
    "complete" })
  spec.eq(out.pass, 1)
  local steps = t.db:exec("select n, verb, outcome from tablua_outcome where todo = 'r' order by n")
  local got = {}
  for _, r in ipairs(steps) do got[#got + 1] = r.verb .. ":" .. r.outcome end
  spec.same(got, { "brief:complete", "expect:complete", "add_node:broken", "set_prop:complete", "look:complete" })
  spec.same({ t.db:exec("select chosen from tablua_decision where n = 4")[1].chosen,
    t.db:exec("select count(*) as c from tablua_score where n = 5 and judge = 'critic'")[1].c >= 7,
    t.db:exec("select count(distinct n) as c from tablua_feature where form = 'studio'")[1].c },
    { "set_prop", true, 5 })
  -- the system prompt is pi's shape, and names the reference's sections; the patch result says what broke
  local sys = m.seen[1].system
  spec.ok(sys:find("<tools>", 1, true) and sys:find("- Pitfalls: what fails.", 1, true), sys)
  local results = t.db:exec("select content from tablua_message where role = 'tool' order by i")
  spec.ok(results[3].content:find("Outcome: broken", 1, true) and results[3].content:find("off_frame on title", 1, true),
    results[3].content)
  -- the early hand-in came back as a follow-up, once
  local follow = t.db:exec("select content from tablua_message where role = 'user' and content like 'Not handed in%'")
  spec.eq(#follow, 1)
  spec.ok(follow[1].content:find("not looked", 1, true))
  -- the look's image went to the model as a user turn after its result
  local sent = m.seen[7].messages
  local last = sent[#sent]
  spec.same({ last.role, last.content[2].image_url.url }, { "user", "data:image/png;base64,UE5H" })
  spec.eq(t.db:exec("select count(*) as c from tablua_message where todo = 'r'")[1].c, #s.loop.messages)
  -- every result ends with the engine's state, so the newest message carries the truth
  spec.ok(results[3].content:find("state: digest d2; errors 1 (off_frame title); warnings 0; expect 1/1; step 3", 1, true),
    results[3].content)
  local run = t.db:exec("select shipped, works, changed, steps from tablua_run where todo = 'r'")[1]
  spec.same({ run.shipped, run.works, run.changed, run.steps }, { 1, 1, 1, 5 })
end)

spec.test("a hand-in on a version already sent back ends the run, errors and all", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local m = model({
    { calls = { { "patch", { moves = { { move = "add_node", node = { id = "title", kind = "text", y = 1200 } } } } } } },
    { text = "Done." }, { text = "It cannot sit higher: the ask wants it below the frame." } })
  local s = session.new{ engine = engine(), model = m, tablua = t, comp = "/w/c.lua", sheet = "/w/s.png", ask = "x",
    todo = "r", exec = function() return { code = 0, stdout = "UE5H" } end }
  local out = s:run()
  spec.same({ out.stop, #m.seen, out.said, out.status }, { "stop", 3, "It cannot sit higher: the ask wants it below the frame.",
    "partial" })
  spec.eq(t.db:exec("select works from tablua_run where todo = 'r'")[1].works, 0)
end)

spec.test("TabICL ranks the moves before a patch and its line follows the result; it never blocks", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local asked
  local learn = { rank = function(_, checkpoint, ctx, moves)
    asked = { checkpoint = checkpoint, n = ctx.n, k = #moves }
    return { { name = "edit_system", p = 0.62 }, { name = "set_prop", p = 0.18 } }
  end }
  local m = model({ { calls = { { "patch", { moves = { { move = "add_node", node = { id = "a", kind = "rect", y = 5 } } } } } } },
    { calls = { { "look", {} } } }, { text = "ok" } })
  local s = session.new{ engine = engine(), model = m, tablua = t, comp = "/w/c.lua", sheet = "/w/s.png", ask = "x",
    todo = "r", learn = learn, exec = function() return { code = 0, stdout = "UE5H" } end }
  s:run()
  spec.same({ asked.checkpoint, asked.n, asked.k > 5 }, { "step", 1, true })
  local first = t.db:exec("select content from tablua_message where role = 'tool' order by i")[1].content
  spec.ok(first:find("learner: from states like this, edit_system 0.62 to close something; add_node not ranked", 1, true)
    or first:find("learner: from states like this, edit_system 0.62", 1, true), first)
end)

spec.test("near the window the turns before the cut become a checkpoint rendered from the tables", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local script = { { text = "Treatment: the line rules.", calls = { { "brief", {} } } } }
  for k = 1, 6 do
    script[#script + 1] = { calls = { { "patch", { moves = { { move = "add_node", node = { id = "n" .. k, kind = "rect",
      y = 10 * k, note = string.rep("z", 3000) } } } } } } }
  end
  script[#script + 1] = { calls = { { "look", {} } } }
  script[#script + 1] = { text = "done" }
  local m = model(script)
  local s = session.new{ engine = engine(), model = m, tablua = t, comp = "/w/c.lua", sheet = "/w/s.png", ask = "a tide clock",
    todo = "r", compact = { window = 3000, reserve = 0, keep = 1500 }, exec = function() return { code = 0, stdout = "UE5H" } end }
  s:run()
  local first = m.seen[#m.seen].messages[1].content
  spec.ok(first:find("## Goal\nThe ask: a tide clock", 1, true) and first:find("## Progress\nstep 1 brief -> complete", 1, true)
    and first:find("## State\ncomp 1280x720", 1, true) and first:find("## Last intent", 1, true), first)
end)

spec.test("a bad move is rejected with why and the others land; an unknown move name is an error result", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local m = model({
    { calls = { { "patch", { moves = { { move = "set_prop", id = "a" }, { move = "teleport" },
      { move = "add_node", node = { id = "b", kind = "rect", y = 10 } } } } } } },
    { calls = { { "reference", { section = "nope" } } } },
    { text = "ok" }, { text = "ok" } })
  local s = session.new{ engine = engine(), model = m, tablua = t, comp = "/w/c.lua", sheet = "/w/s.png", ask = "x",
    todo = "r", reference = CARD, exec = function() return { code = 0, stdout = "UE5H" } end }
  s:run()
  local results = t.db:exec("select content, is_error from tablua_message where role = 'tool' order by i")
  spec.ok(results[1].content:find("1 applied, 2 rejected", 1, true) and results[1].content:find("set_prop needs name", 1, true),
    results[1].content)
  spec.ok(results[2].is_error == 1 and results[2].content:find("there are: The moves, Pitfalls", 1, true))
end)


spec.test("the patch tool's schema declares every move's fields, so a provider that keeps to the schema keeps them", function()
  local tools = require("studio.tools")
  local patch
  for _, tl in ipairs(tools.list({ t = {} })) do if tl.name == "patch" then patch = tl end end
  -- one flat item, every move's fields in it: a constrained decoder cannot merge a union (anyOf), and keeps only
  -- what every branch shares
  local items = patch.parameters.properties.moves.items
  spec.same({ items.anyOf, items.additionalProperties, items.properties.id.type, items.properties.value.type[1],
    items.properties.to_t ~= nil, items.properties.node.type, items.properties.rows ~= nil, items.required[1] },
    { nil, nil, "string", "number", true, "object", false, "move" })
  local names = {}
  for _, n in ipairs(items.properties.move.enum) do names[n] = true end
  spec.ok(names.solid and names.set_prop and not names.treat)
  spec.ok(items.description:find("set_prop: id, name, value", 1, true), items.description)
end)

spec.test("a hand-in before the model wrote the ask as expectations, or on the comp as given, is not complete", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local m = model({ { calls = { { "look", {} } } }, { text = "It is already fine." }, { text = "Still fine." } })
  local s = session.new{ engine = engine(), model = m, tablua = t, comp = "/w/c.lua", sheet = "/w/s.png", ask = "x",
    todo = "r", exec = function() return { code = 0, stdout = "UE5H" } end }
  local out = s:run()
  local back = t.db:exec("select content from tablua_message where content like 'Not handed in%'")[1].content
  spec.ok(back:find("Write what the ask requires as expectations", 1, true) and back:find("nothing has changed", 1, true), back)
  local run = t.db:exec("select works, changed from tablua_run")[1]
  spec.same({ out.status, run.works, run.changed }, { "partial", 0, 0 })
end)

spec.test("the engine's warn findings are warnings", function()
  local tools = require("studio.tools")
  spec.eq(tools.found({ { code = "motion_density", severity = "warn" } }), "- warning motion_density")
end)
spec.run()
