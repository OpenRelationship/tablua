-- Unit cases for studio.moves: every move has a tool the writer can call, a patch's shape is checked before the
-- engine sees it, and a tool call's arguments become the engine's patch.
local spec = require("spec")
local moves = require("studio.moves")
local json = require("ports.json")

spec.test("every move is offered once and has a tool with its schema", function()
  local seen = {}
  for _, m in ipairs(moves.order) do
    spec.ok(not seen[m], m) ; seen[m] = true
    local t = moves.tool(m)
    spec.same({ t.type, t["function"].name, t["function"].parameters.type }, { "function", m, "object" })
    spec.ok(moves.what[m], m)
  end
  spec.ok(json.encode(moves.tool("add_key")):find('"number","string"', 1, true))
end)

spec.test("a patch missing a field, or with one of the wrong type, is refused with why", function()
  spec.ok(moves.check("set_prop", { id = "line", name = "y", value = 220 }))
  spec.ok(moves.check("set_prop", { id = "buoy", name = "pos", value = { 0, 0, -6 } }))
  spec.ok(moves.check("add_key", { id = "tide", name = "opacity", t = "beat:1", value = 1 }))
  local _, why = moves.check("set_prop", { id = "line", value = 1 })
  spec.eq(why, "set_prop needs name")
  _, why = moves.check("add_key", { id = "a", name = "y", t = true, value = 1 })
  spec.eq(why, "add_key.t is not number or string")
  spec.ok(not moves.check("add_node", { node = { kind = "rect" } }))
  spec.ok(not moves.check("remove", {}))
  spec.ok(moves.check("remove", { system = "tide-follows-line" }))
  spec.ok(not moves.check("teleport", {}))
end)

spec.test("a value says its types, so a number goes as a number and null clears", function()
  local v = moves.schema.set_prop.properties.value
  spec.same(v.type, { "number", "string", "boolean", "array", "object", "null" })
  spec.ok(v.description:find("48, not", 1, true))
end)

spec.test("a tool call's arguments become the engine's patch", function()
  spec.same(moves.patch("move_key", { id = "line", name = "y", t = 6, to_t = "beat:4" }),
    { move = "move_key", id = "line", name = "y", t = 6, to_t = "beat:4" })
end)


spec.test("a solid is a move: an asset with its tree", function()
  spec.ok(moves.check("solid", { asset = { id = "bollard", solid = { op = "cylinder", r = 0.3, h = 0.8 } } }))
  spec.ok(not moves.check("solid", { asset = { id = "bollard" } }))
  spec.ok(moves.what.solid:find("asset:", 1, true))
end)
spec.run()
