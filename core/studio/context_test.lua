-- Unit cases for studio.context: the run's history rendered from the sheet's rows, a line a step, and the engine's
-- reference card cut to the sections a move needs.
local spec = require("spec")
local context = require("studio.context")

local function sheet()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local function snap(n, findings)
    t:comp("r", n, { tables = { comp = { fps = 30 }, node = { { id = "t1", kind = "text" } } } })
    t:findings("r", n, findings)
  end
  local function failed(id, node)
    return { tier = "lint", id = node, code = "expect_failed", severity = "error", detail = "x: gone (expect " .. id .. ")" }
  end
  local contrast = { tier = "check", id = "date", code = "contrast", severity = "error" }
  local drift = { tier = "lint", id = "buoy", code = "subpixel_drift", severity = "info" }
  snap(0, { contrast, drift })
  t:outcome{ todo = "r", n = 1, verb = "treat", outcome = "complete", note = "treatment: ...; 2 expectations written" }
  t:outcome{ todo = "r", n = 2, verb = "look", outcome = "complete", note = "judge: Next: The table is dim." }
  t:outcome{ todo = "r", n = 3, verb = "add_key", outcome = "no_effect",
    note = "0 applied, 1 rejected: no node buoy; 2 findings open (1 errors)" }
  snap(4, { contrast, failed("tide-1", "t1"), failed("almanac", "field") })
  for i, id in ipairs({ "field", "t1" }) do t:action{ todo = "r", n = 4, i = i, cmd = "{}", op = "remove", target = id } end
  t:outcome{ todo = "r", n = 4, verb = "remove", outcome = "broken", note = "2 applied, 0 rejected; 3 findings open" }
  snap(5, { failed("tide-1", "t1"), failed("almanac", "field") })
  t:action{ todo = "r", n = 5, i = 1, cmd = "{}", op = "set_prop", target = "date" }
  t:outcome{ todo = "r", n = 5, verb = "set_prop", outcome = "complete", note = "1 applied, 0 rejected; 2 open" }
  return t
end

spec.test("the history is a line a step, every step: what it did, how it came out, and what it changed", function()
  local lines = {}
  for l in context.history(sheet(), "r", 5):gmatch("[^\n]+") do lines[#lines + 1] = l end
  spec.eq(#lines, 5)
  spec.eq(lines[1], "step 1 treat -> complete; the treatment (given above); 2 expectations written")
  spec.eq(lines[3], "step 3 add_key -> no_effect; rejected: no node buoy")
  spec.eq(lines[4], "step 4 remove field, t1 -> broken; errors 1->3 (+2 expect_failed: almanac, tide-1)")
  spec.eq(lines[5], "step 5 set_prop date -> complete; errors 3->2 (closed: contrast on date)")
  spec.eq(context.history(sheet(), "r", 2):match("[^\n]+$"), "step 2 look -> complete; judge: Next: The table is dim.")
end)

local CARD = "# Card\nintro\n## Comp skeleton (passes)\nskel\n## Keys and motion\nkeys\n## Systems and code\nsys\n"
  .. "## The moves (./moonsplice patch)\nmoves\n## Node kinds: { id= }\nkinds\n## 3D: a world node\nworld\n"
  .. "## Solids: Manifold\nsolids\n## Games: the game table\ngames\n## Pitfalls (each fails)\npits\n"

spec.test("the card goes by section: always the moves and the pitfalls, then what the move touches", function()
  local key = context.card(CARD, "add_key", "video", false)
  spec.ok(key:find("intro", 1, true) and key:find("keys", 1, true) and key:find("moves", 1, true)
    and key:find("pits", 1, true))
  spec.ok(not key:find("sys", 1, true) and not key:find("world", 1, true) and not key:find("games", 1, true))
  local system = context.card(CARD, "edit_system", "game", true)
  spec.ok(system:find("sys", 1, true) and system:find("world", 1, true) and system:find("games", 1, true))
  spec.ok(context.card(CARD, "solid", "video", false):find("solids", 1, true))
  spec.eq(context.card("THE CARD", "add_key", "video", false), "THE CARD")
  spec.ok(#context.card(CARD, "remove", "video", true) < #CARD)
end)


-- the card as Moonsplice keeps it now (.robot/docs/reference.robot): the suite's documentation is the head, each test
-- case a section whose [Documentation] is its text
local ROBOT = table.concat({ "*** Settings ***", "Documentation    Moonsplice API card.", "...    Exact.", "",
  "*** Test Cases ***", "Keys and motion", "    [Documentation]    Summary: how keys ease.", "    ...    ```lua",
  "    ...    \\ \\ keys = {}", "    ...    ```", "The moves (moonsplice patch)", "    [Documentation]    moves",
  "Pitfalls (each fails)", "    [Documentation]    pits" }, "\n")

spec.test("the card may be the Robot doc: its tests are the sections, their documentation the text", function()
  spec.eq(context.index(ROBOT), "- Keys and motion: how keys ease.\n- The moves\n- Pitfalls")
  spec.eq(context.section(ROBOT, "keys and motion"), "## Keys and motion\nSummary: how keys ease.\n```lua\n  keys = {}\n```")
  local key = context.card(ROBOT, "add_key", "video", false)
  spec.ok(key:find("Moonsplice API card.\nExact.", 1, true) and key:find("  keys = {}", 1, true) and key:find("pits", 1, true),
    key)
end)

spec.test("a step that sets a prop back to a value it had within three steps is marked as undoing the one that changed it", function()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  local function snap(n, color, w)
    t:comp("r", n, { tables = { node = { { id = "field", kind = "rect" } }, prop = { { id = "field", name = "color",
      value = color }, { id = "field", name = "w", value = w } } } })
    t:findings("r", n, {})
  end
  snap(0, "#081218", 560)
  for n, v in ipairs({ { "#1a1418", 560 }, { "#1a1418", 600 }, { "#081218", 600 }, { "#081218", 640 } }) do
    snap(n, v[1], v[2])
    t:action{ todo = "r", n = n, i = 1, cmd = "{}", op = "set_prop", target = "field" }
    t:outcome{ todo = "r", n = n, verb = "set_prop", outcome = "neutral", note = "1 applied, 0 rejected; 0 open" }
  end
  local lines = {}
  for l in context.history(t, "r", 4):gmatch("[^\n]+") do lines[#lines + 1] = l end
  spec.eq(lines[3], "step 3 set_prop field -> neutral; undoes step 1 (field.color back to \"#081218\")")
  spec.eq(lines[4], "step 4 set_prop field -> neutral")
  spec.eq(context.since(t, "r", 4), 4)
end)

spec.test("since: the patch steps after the last one that completed", function()
  spec.eq(context.since(sheet(), "r", 4), 2)
  spec.eq(context.since(sheet(), "r", 5), 0)
end)

spec.test("the card's index names each section with its summary, and one section is read by name", function()
  local card = "# Card\n## Keys and motion\nSummary: keyframes and eases.\nkeys\n## 3D: a world node\nSummary: Bevy PBR.\nworld\n"
  spec.eq(context.index(card), "- Keys and motion: keyframes and eases.\n- 3D: Bevy PBR.")
  spec.ok(context.section(card, "3d"):find("world", 1, true))
  local none, why = context.section(card, "Solids")
  spec.same({ none, why }, { nil, "no section Solids; there are: Keys and motion, 3D" })
  spec.eq(context.changes(sheet(), "r", 4), "errors 1->3 (+2 expect_failed: almanac, tide-1)")
  spec.eq(context.changes(sheet(), "r", 3), nil)
end)
spec.run()
