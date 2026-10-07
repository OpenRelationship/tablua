-- Unit cases for tablua.studio: a comp's msr/1 rows kept per step and read back the same, what a step touched as
-- the difference of two snapshots, findings and scores as rows, and a step's outcome from the findings.
local spec = require("spec")
local tablua = require("tablua")
local studio = require("tablua.studio")
local json = require("ports.json")

local function open() return tablua.open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end }) end

local function comp(y, extra)
  local rows = { schema = "msr/1", tables = {
    comp = { width = 1920, fps = 30 },
    node = { { id = "line", kind = "rect", order = 2 }, { id = "buoy", kind = "mesh", parent = "w", order = 1 },
      { id = "w", kind = "world", order = 0 } },
    prop = { { id = "line", name = "y", value = y }, { id = "buoy", name = "pos", value = { 0, 0, -6 } },
      { id = "buoy", name = "material", value = { color = "#c0392b" } } },
    key = { { id = "line", name = "y", t = 0, value = 540 }, { id = "tide", name = "opacity", t = "beat:1",
      value = 1, ease = "expoOut" } },
    system = { { name = "tide-follows-line", order = 1, source = "return function(t, s, q) return {} end" } },
  } }
  for k, v in pairs(extra or {}) do rows.tables[k] = v end
  return rows
end

spec.test("a comp's rows go in per step and come back as they went, positions and materials included", function()
  local t = open()
  t:comp("r", 0, comp(540))
  local back = t:comp_rows("r", 0)
  spec.same({ back.tables.node[2].id, back.tables.prop[2].value, back.tables.prop[1].value, back.tables.key[2].t,
    back.tables.system[1].order, back.tables.comp.width }, { "buoy", { 0, 0, -6 }, { color = "#c0392b" }, "beat:1", 1,
    1920 })
  t:comp("r", 9, back)
  spec.eq(json.encode(t:comp_rows("r", 9)), json.encode(back))
  spec.eq(t.db:exec("select value from tablua_msr_prop where id = 'buoy' and name = 'pos'")[1].value, "[0,0,-6]")
end)

spec.test("what a step touched is where its snapshot differs from the one before", function()
  local t = open()
  t:comp("r", 0, comp(540))
  local after = comp(220)
  table.remove(after.tables.node, 2)          -- buoy removed
  table.remove(after.tables.prop, 3); table.remove(after.tables.prop, 2)
  after.tables.system[1].source = "return function(t, s, q) return { { id = 'tide' } } end"
  t:comp("r", 1, after)
  spec.same(t:touched("r", 1), { { id = "buoy", name = "" }, { id = "buoy", name = "material" },
    { id = "buoy", name = "pos" }, { id = "line", name = "y" }, { id = "system:tide-follows-line", name = "source" } })
  t:comp("r", 2, after)
  spec.same(t:touched("r", 2), {})
end)

local E = function(id, name, code, sev) return { tier = "lint", id = id, name = name, code = code, severity = sev or "error" } end

spec.test("findings and scores are rows of the step", function()
  local t = open()
  t:findings("r", 1, { E("line", "y", "off_frame"), E("", "", "contrast", "warning") })
  t:scores("r", 1, "critic", { rule = 4, craft = 2 })
  spec.same({ #t:findings_of("r", 1), t.db:exec("select min(value) as low from tablua_score")[1].low }, { 2, 2 })
end)

spec.test("the outcome: nothing changed is no_effect, a new error is broken, the target's findings gone is complete", function()
  local before = { E("line", "y", "off_frame"), E("tide", "opacity", "parked_visible", "warning") }
  local touched = { { id = "line", name = "y" } }
  spec.eq(studio.outcome(before, before, {}), "no_effect")
  spec.eq(studio.outcome(before, { E("tide", "opacity", "parked_visible", "warning") }, touched), "complete")
  -- changed, but no finding opened or closed: the findings cannot judge it (ROWS.md: neutral)
  spec.eq(studio.outcome(before, { before[1], before[2] }, touched), "neutral")
  spec.eq(studio.outcome({}, {}, { { id = "title", name = "opacity" } }), "neutral")
  -- one closed elsewhere while the target's own stays open helped nothing on the target
  spec.eq(studio.outcome(before, { before[1] }, touched), "no_effect")
  spec.eq(studio.outcome(before, { before[2], E("sea", "", "missing_src") }, touched), "broken")
  spec.eq(studio.outcome(before, { before[2], E("line", "y", "too_fast", "warning") }, touched), "no_effect")
  -- a finding about a node the step removed (its props with it) is gone with it
  spec.eq(studio.outcome({ E("buoy", "pos", "off_frame") }, {}, { { id = "buoy", name = "" } }), "complete")
  -- an info finding is advice, not a problem: opening or closing one judges nothing (studio s1: subpixel_drift and
  -- ease_monoculture, info, made two add_keys no_effect)
  local info = { tier = "lint", id = "buoy", code = "subpixel_drift", severity = "info" }
  spec.eq(studio.outcome({}, { info }, { { id = "buoy", name = "y" } }), "neutral")
  spec.eq(studio.outcome({ info, E("sea", "", "x") }, { E("sea", "", "x") }, { { id = "buoy", name = "y" } }), "neutral")
  -- the engine leaves name out when a step touched a whole node or system
  spec.eq(studio.outcome({ E("buoy", "pos", "off_frame"), E("sea", "", "x") }, { E("buoy", "pos", "off_frame") },
    { { id = "buoy" } }), "no_effect")
end)

spec.test("derived facts are kept beside the authored ones and come back apart, outside the tables", function()
  local t = open()
  local rows = comp(540)
  rows.tables.fact = { { pred = "holds", args = "tide", t0 = 0, src = "" } }
  rows.derived = { { pred = "beat", args = "1", t0 = 0.255, src = "beats", asset = "bed" },
    { pred = "word", args = "tide#2", t0 = 1.5, t1 = 1.9, src = "words", asset = "vo" } }
  t:comp("r", 0, rows)
  local back = t:comp_rows("r", 0)
  spec.same({ #back.tables.fact, back.tables.fact[1].args, #back.derived, back.derived[1].asset, back.derived[2].t1 },
    { 1, "tide", 2, "bed", 1.9 })
end)

spec.test("numbers in canonical JSON: integers as integers, others the shortest of 15 to 17 digits that reads back", function()
  spec.same({ studio.canon(540), studio.canon(-6), studio.canon(0.1), studio.canon(1 / 3), studio.canon(2 ^ 60),
    studio.canon({ 0, 1.2, -6 }), studio.canon({ b = 0.25, a = true }) },
    { "540", "-6", "0.1", "0.3333333333333333", "1.152921504606847e+18", "[0,1.2,-6]", '{"a":true,"b":0.25}' })
end)


spec.test("a solid's tree is kept with its asset and its measures beside it, outside the tables", function()
  local t = open()
  local rows = comp(540, { asset = { { id = "buoy", solid = { op = "revolve", profile = { { 0, 0 }, { 0.42, 0 } },
    segments = 64 } }, { id = "bed", src = "bed.wav" } } })
  rows.solids = { buoy = { parts = 1, genus = 1, watertight = true, empty = false, volume = 0.797, area = 4.82,
    triangles = 6776, size = { 1.01, 1.405, 1.01 } } }
  t:comp("r", 0, rows)
  local back = t:comp_rows("r", 0)
  spec.same({ back.tables.asset[2].solid.segments, back.tables.asset[1].solid, back.solids.buoy.parts,
    back.solids.buoy.watertight, back.solids.buoy.size }, { 64, nil, 1, true, { 1.01, 1.405, 1.01 } })
  t:comp("r", 1, back)
  spec.eq(json.encode(t:comp_rows("r", 1)), json.encode(back))
end)

spec.test("expectations are rows of the comp, their times seconds or facts, and come back as they went", function()
  local t = open()
  t:comp("r", 0, comp(540, { expect = { { id = "high", says = "the HIGH row lands", node = "t4", prop = "opacity",
    op = ">=", value = 0.9, at = "beat:14" }, { id = "lamp", says = "the lamp burns", node = "lamp", prop = "intensity",
    op = ">", value = 0, t0 = 4.5, t1 = 6, holds = "ever" } } }))
  local back = t:comp_rows("r", 0)
  spec.same({ back.tables.expect[1].id, back.tables.expect[1].at, back.tables.expect[1].value, back.tables.expect[2].t0,
    back.tables.expect[2].holds }, { "high", "beat:14", 0.9, 4.5, "ever" })
  spec.eq(back.tables.expect[1].t0, nil)
  t:comp("r", 1, back)
  spec.eq(json.encode(t:comp_rows("r", 1)), json.encode(back))
end)

spec.test("each model call of a step is a row: who was asked, each part's bytes, the text sent and the reply", function()
  local t = open()
  t:prompt{ todo = "r", n = 3, role = "writer", parts = { card = 4200, brief = 4736, history = 610 },
    text = "the whole request", reply = "the tool calls" }
  t:prompt{ todo = "r", n = 3, role = "writer", parts = { card = 4200 }, text = "again", reply = "" }
  local rows = t.db:exec("select i, role, bytes, parts, text from tablua_prompt where todo = 'r' and n = 3 order by i")
  spec.same({ #rows, rows[1].i, rows[2].i, rows[1].bytes, json.decode(rows[1].parts).brief, rows[2].text },
    { 2, 1, 2, #"the whole request", 4736, "again" })
end)

spec.test("the transcript is a row per message, in order, with its calls, the call it answers and its usage", function()
  local t = open()
  t:message("r", 0, { role = "user", content = "Make it feel like the turn of the tide." })
  t:message("r", 0, { role = "assistant", content = "Treatment: ...", reasoning_content = "first the almanac",
    tool_calls = { { id = "c1", type = "function", ["function"] = { name = "brief", arguments = "{}" } } },
    usage = { prompt = 3000, completion = 200 }, provider = "Fireworks" })
  t:message("r", 1, { role = "tool", name = "look", tool_call_id = "c1", content = "the sheet", image = "UE5HUE5H" })
  local rows = t.db:exec("select i, n, role, tool_call_id, image, provider, reasoning from tablua_message order by i")
  spec.same({ #rows, rows[2].provider, rows[2].reasoning, rows[3].tool_call_id, rows[3].image, rows[3].n },
    { 3, "Fireworks", "first the almanac", "c1", 8, 1 })
  spec.eq(json.decode(t.db:exec("select tool_calls from tablua_message where i = 2")[1].tool_calls)[1].id, "c1")
end)
spec.run()
