-- The agent's moves on a comp (cadence/docs/ROWS.md, level 6): each a typed patch, its payload a JSON schema the
-- writer fills as a tool call, checked here for shape before the engine checks it for meaning
-- (lib/moonsplice/rows.lua's MOVES, whose fields these are). treat is the director's treatment, not a comp edit.
--
--   moves.order                     the moves in the order they are offered
--   moves.what[move]                one line on what the move does, for the decider and the writer
--   moves.tool(move) -> { type = "function", ["function"] = { name, description, parameters } }
--   moves.check(move, patch) -> true | nil, why     a patch's fields, by type
--   moves.patch(move, args) -> patch   a tool call's arguments as the engine's patch ({ move = ..., ... })
local M = {}

M.order = { "treat", "add_node", "set_prop", "add_key", "move_key", "drop_key", "bind", "add_system", "edit_system",
  "derive", "solid", "remove" }

M.what = {
  treat = "Write the treatment: the premise, the governing rule, the grammar and the structure. Not a comp edit.",
  add_node = "Add a node (a thing on screen, or in a world) with its props at rest.",
  set_prop = "Set one prop of a node at rest (its value, or null to clear it).",
  add_key = "Add a keyframe: from the previous key of that prop to this value at t, eased.",
  move_key = "Move a keyframe to another time (to_t), or change its value or ease.",
  drop_key = "Remove a keyframe.",
  bind = "Tie a keyframe's time to a fact (\"beat:12\", \"word:tide\"), so the comp says what it follows.",
  add_system = "Add a system: one small pure function (t, state, q) -> rows, run every frame after the keys.",
  edit_system = "Change a system's source or its order.",
  derive = "Declare a media asset and the derive ops it is made with.",
  solid = "Build a solid with Manifold from a tree of ops (the reference's Solids section); a mesh node shows it with "
    .. "src = \"asset:<id>\", a system's entity with solid = \"asset:<id>\".",
  remove = "Remove a node with its props, keys and children, or a system.",
}

-- a value names its types: left open, M3 sent every value as a string ("48", "null"; studio trial 1, 2026-10-06)
local VALUE = { type = { "number", "string", "boolean", "array", "object", "null" },
  description = "a number as a JSON number (48, not \"48\"), a string, a boolean, or an array or object of those; "
    .. "null clears the prop" }
local T = { description = "seconds, or a fact reference such as \"beat:12\"", type = { "number", "string" } }
local S = { type = "string" }

local function obj(props, required)
  return { type = "object", properties = props, required = required, additionalProperties = false }
end

M.schema = {
  treat = obj({ text = S }, { "text" }),
  add_node = obj({ node = { type = "object", description = "id and kind, parent (a group or world id) and order (draw order) if any, "
    .. "and its props at rest by name", properties = { id = S, kind = S, parent = S, order = { type = "number" } },
    required = { "id", "kind" }, additionalProperties = true } }, { "node" }),
  set_prop = obj({ id = S, name = S, value = VALUE }, { "id", "name" }),   -- no value: the prop is cleared
  add_key = obj({ id = S, name = S, t = T, value = VALUE, ease = S }, { "id", "name", "t", "value" }),
  move_key = obj({ id = S, name = S, t = T, to_t = T, value = VALUE, ease = S }, { "id", "name", "t" }),
  drop_key = obj({ id = S, name = S, t = T }, { "id", "name", "t" }),
  bind = obj({ id = S, name = S, t = T, fact = { type = "string", description = "pred:args, such as beat:12" } },
    { "id", "name", "t", "fact" }),
  add_system = obj({ name = S, source = { type = "string", description = "Lua returning function(t, state, q) -> rows" },
    order = { type = "number" } }, { "name", "source" }),
  edit_system = obj({ name = S, source = S, order = { type = "number" } }, { "name" }),
  derive = obj({ asset = { type = "object", properties = { id = S, src = S, derive = { type = "object" } },
    required = { "id", "src" } } }, { "asset" }),
  solid = obj({ asset = { type = "object", properties = { id = S, solid = { type = "object",
    description = "the tree: an op and its fields, children nested (the reference's Solids section)" } },
    required = { "id", "solid" } } }, { "asset" }),
  remove = obj({ id = S, system = S }, {}),
}

function M.tool(move)
  assert(M.schema[move], "studio: no move " .. tostring(move))
  return { type = "function", ["function"] = { name = move, description = M.what[move], parameters = M.schema[move] } }
end

local function typed(v, want)
  if want == nil then return true end
  if type(want) == "table" then
    for _, w in ipairs(want) do if typed(v, w) then return true end end
    return false
  end
  if want == "object" or want == "array" then return type(v) == "table" end
  if want == "null" then return v == nil end
  return type(v) == want
end

function M.check(move, patch)
  local s = M.schema[move]
  if not s then return nil, "no move " .. tostring(move) end
  if type(patch) ~= "table" then return nil, move .. " needs an object" end
  for _, k in ipairs(s.required or {}) do
    if patch[k] == nil then return nil, ("%s needs %s"):format(move, k) end
  end
  for k, p in pairs(s.properties) do
    if patch[k] ~= nil and not typed(patch[k], p.type) then
      return nil, ("%s.%s is not %s"):format(move, k, type(p.type) == "table" and table.concat(p.type, " or ") or p.type)
    end
  end
  if move == "add_node" then
    local n = patch.node
    if type(n.id) ~= "string" or n.id == "" or type(n.kind) ~= "string" then return nil, "add_node needs node.id and node.kind" end
  elseif move == "solid" and (type(patch.asset.id) ~= "string" or type(patch.asset.solid) ~= "table") then
    return nil, "solid needs asset.id and asset.solid"
  elseif move == "remove" and patch.id == nil and patch.system == nil then
    return nil, "remove needs id or system"
  end
  return true
end

function M.patch(move, args)
  local p = { move = move }
  for k, v in pairs(args or {}) do p[k] = v end
  return p
end

return M
