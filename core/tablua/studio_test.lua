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

spec.run()
