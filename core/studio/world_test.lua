-- A whole run of the studio world over fakes of the engine, the writer, the critic and Jev: treat, a broken patch, a
-- fix, a look, then answer; every step's comp, findings, scores, outcome and decision kept as rows.
local spec = require("spec")
local json = require("ports.json")
local agent = require("agent")
local world = require("studio.world")

-- the engine: rows in a table; a title below y 1000 is off the frame (an error)
local function engine()
  local e = { node = {}, prop = {}, v = 0 }
  local function findings()
    local out = {}
    for _, p in ipairs(e.prop) do
      if p.name == "y" and p.value > 1000 then
        out[#out + 1] = { tier = "lint", id = p.id, name = "y", code = "off_frame", severity = "error" }
      end
    end
    return out
  end
  function e.rows() return { schema = "msr/1", digest = "d" .. e.v, tables = { node = e.node, prop = e.prop } } end
  function e.lint() return findings() end
  function e.check() return {} end
  function e.sheet() return { picks = { 0, 6 }, seconds = 1.5 } end
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

local function writer(calls)
  return { chat = function(_, req)
    if req.tools then assert(req.system:find("THE CARD", 1, true), "the writer has the reference") end
    if not req.tools then return "Premise: a tide line. Rule: everything hangs from the line." end
    local args = table.remove(calls, 1)
    return "", { tool_calls = { { id = "c", type = "function", ["function"] = { name = req.tools[1]["function"].name,
      arguments = json.encode(args) } } } }
  end }
end

local critic = { chat = function(_, req)
  assert(req.messages[1].content[2].image_url.url == "data:image/png;base64,UE5H")
  return '{"scores": {"rule": 4, "relationship": 3, "defaults": 4, "rhythm": 3, "memory": 2, "craft": 4}, "notes": "more"}'
end }

local function jev(picks, states)
  return { decide = function(_, state, questions)
    states[#states + 1] = state
    local pick = table.remove(picks, 1)
    assert(questions.next.options[pick], pick .. " is not offered")
    return { next = { choice = pick, probabilities = { [pick] = 0.9 }, confidence = 0.8 } }
  end }
end

spec.test("treat, a patch that breaks, a fix, a look, then answer: each step's rows and outcome", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local w = world.new{ engine = engine(), tablua = t, comp = "/w/c.lua", sheet = "/w/s.png", ask = "a tide clock",
    reference = "THE CARD",
    writer = writer({ { node = { id = "title", kind = "text", y = 1200 } }, { id = "title", name = "y", value = 540 } }),
    critic = critic, exec = function() return { code = 0, stdout = "UE5H" } end }
  local memory = { begin = function() return "r" end, step = function() end, log = function() end }
  local states = {}
  local a = agent.new({ jev = jev({ "add_node", "set_prop", "look", "answer" }, states), tablua = t,
    memory = memory }, w)
  local req = a:begin("a tide clock")
  while true do
    local r = a:step(req)
    if r[1] == "done" then break end
    a:perform(req, r[2])
    a:close(req, r[2])
  end
  local got = {}
  for _, s in ipairs(req.steps) do got[#got + 1] = s.verb .. ":" .. s.outcome end
  spec.same(got, { "treat:complete", "add_node:broken", "set_prop:complete", "look:complete" })
  spec.same({ #t:findings_of("r", 2), #t:findings_of("r", 3), t:comp_rows("r", 3).tables.prop[1].value,
    t.db:exec("select count(*) as c from tablua_score where n = 4")[1].c,
    t.db:exec("select group_concat(progress) as p from tablua_outcome")[1].p,
    t.db:exec("select count(distinct n) as c from tablua_feature where form = 'studio'")[1].c },
    { 1, 0, 540, 6, "1,0,1,1", 5 })
  spec.eq(t.db:exec("select stage from tablua_state where n = 4")[1].stage, "polishing")
  spec.ok(math.abs(req.pass - 6 / 7) < 1e-9, req.pass)
  -- before any look Jev reads text; after one, the text and the newest contact sheet as content parts
  spec.eq(type(states[1]), "string")
  spec.same({ states[4][1].type, states[4][2].image_url.url }, { "text", "data:image/png;base64,UE5H" })
  -- treat was the only move offered, so it was taken without asking Jev
  spec.same({ #states, t.db:exec("select by from tablua_decision where n = 1")[1].by }, { 4, "only" })   -- the gate and five of six scores at 3 or more: 6 of 7
end)

spec.test("look and answer are offered with errors open: the decider reads them and decides", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local e = engine()
  e.node[1] = { id = "title", kind = "text", order = 1 }
  e.prop[1] = { id = "title", name = "y", value = 1200 }
  local w = world.new{ engine = e, tablua = t, comp = "/w/c.lua", sheet = "/w/s.png", ask = "x", writer = writer({}),
    critic = critic, exec = function() return { code = 0, stdout = "UE5H" } end }
  local a = agent.new({ jev = jev({}, {}), tablua = t, memory = { begin = function() return "r" end } }, w)
  local req = a:begin("x")
  req.treatment = "a rule"
  local function offered() local q = w.question(a) return q.options.look ~= nil, q.options.answer ~= nil end
  spec.same({ offered() }, { true, false })
  w.act(a, req, "look", { lines = {} })
  spec.same({ offered() }, { false, true })
end)

spec.test("a writer that reasons to its limit and says nothing is asked once more, afresh", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local tries = 0
  local runaway = { chat = function()
    tries = tries + 1
    if tries == 1 then error("minimax/minimax-m3 spent its limit, 129142 tokens reasoning, and said nothing", 0) end
    return "Premise: the tide."
  end }
  local w = world.new{ engine = engine(), tablua = t, comp = "/w/c.lua", sheet = "/w/s.png", ask = "x",
    writer = runaway, critic = critic, exec = function() return { code = 0, stdout = "" } end }
  local req, step = { todo = "r", steps = {} }, { lines = {} }
  w.act(nil, req, "treat", step)
  spec.same({ tries, step.outcome }, { 2, "complete" })
end)

spec.test("one step lands the chosen move with the patches it needs from others, the writer reasoning briefly", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local seen
  local call = function(name, args) return { id = name, type = "function", ["function"] = { name = name,
    arguments = json.encode(args) } } end
  local both = { chat = function(_, req)
    seen = req
    return "", { tool_calls = { call("add_node", { node = { id = "buoy", kind = "rect", y = 1200 } }),
      call("set_prop", { id = "buoy", name = "y", value = 540 }) } }
  end }
  local w = world.new{ engine = engine(), tablua = t, comp = "/w/c.lua", sheet = "/w/s.png", ask = "x",
    writer = both, critic = critic, exec = function() return { code = 0, stdout = "" } end }
  local req, step = { todo = "r", steps = {}, treatment = "Rule: the line." }, { lines = {} }
  w.act(nil, req, "add_node", step)
  -- the node lands at 540 by the set_prop of the same reply: no error opened, none closed, so neutral, not broken
  spec.same({ step.outcome, seen.tools[1]["function"].name, seen.reasoning_effort }, { "neutral", "add_node", "low" })
  spec.ok(#seen.tools > 1 and seen.messages[1].content:find("in the same reply", 1, true))
  spec.ok(step.note:find("2 applied", 1, true), step.note)
  -- a reply without the chosen move is not that move
  local only = { chat = function() return "", { tool_calls = { call("set_prop", { id = "buoy", name = "y", value = 9 }) } } end }
  w = world.new{ engine = engine(), tablua = t, comp = "/w/c.lua", sheet = "/w/s.png", ask = "x",
    writer = only, critic = critic, exec = function() return { code = 0, stdout = "" } end }
  step = { lines = {} }
  w.act(nil, { todo = "r2", steps = {}, treatment = "x" }, "add_node", step)
  spec.eq(step.outcome, "no_effect")
end)

spec.test("a patch after a treat and a look sees the comp as it stands, and the critic's listed notes as text", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local e = engine()
  e.node[1], e.prop[1] = { id = "body", kind = "mesh", order = 1 }, { id = "body", name = "y", value = 300 }
  local seen
  local w = world.new{ engine = e, tablua = t, comp = "/w/c.lua", sheet = "/w/s.png", ask = "x", reference = "THE CARD",
    writer = { chat = function(_, req)
      if not req.tools then return "Rule: the line." end
      seen = req.messages[1].content
      return "", { tool_calls = { { id = "c", type = "function", ["function"] = { name = "set_prop",
        arguments = json.encode({ id = "body", name = "y", value = 320 }) } } } }
    end },
    critic = { chat = function() return '{"scores": {"rule": 4, "relationship": 3, "defaults": 4, "rhythm": 3, '
      .. '"memory": 2, "craft": 4}, "notes": ["Recast the type in red", "Light the buoy"]}' end },
    exec = function() return { code = 0, stdout = "UE5H" } end }
  local memory = { begin = function() return "r" end, step = function() end, log = function() end }
  local a = agent.new({ jev = jev({ "look", "set_prop" }, {}), tablua = t, memory = memory }, w)
  local req = a:begin("x")
  for _ = 1, 3 do local r = a:step(req) a:perform(req, r[2]) a:close(req, r[2]) end
  spec.same({ req.steps[2].verb, req.steps[3].verb }, { "look", "set_prop" })
  spec.ok(req.steps[2].note:find("Recast the type in red; Light the buoy", 1, true), req.steps[2].note)
  spec.ok(seen:find('"id":"body"', 1, true), "the writer saw no node body")
  spec.ok(seen:find("Light the buoy", 1, true), "the writer saw no critique")
end)

spec.run()
