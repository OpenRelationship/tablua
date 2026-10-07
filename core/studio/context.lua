-- What a model reads of the run, rendered from the sheet's rows as prose (owner, 2026-10-06, through Moonsplice: the
-- tables are for TabICL; a model reads text made from them). In studio s2 the writer saw only the last step, and
-- seven remove steps in a row each read the same critique afresh.
--
--   context.history(t, todo, upto) -> text   a line per step, every step: the move and what it touched (tablua_action),
--                                             how it came out (tablua_outcome), and the errors and expectations it
--                                             opened or closed (the msr_finding snapshots before and after it)
--   context.card(card, move, kind, world) -> text   the engine's reference card (Moonsplice's agent/REFERENCE.md) cut
--                                             to its sections the move needs: always its head, the moves and the
--                                             pitfalls; world says the comp has a 3D world
--   context.shown(req) -> text   a request as kept in tablua_prompt: system, user or messages, the tools by name, and
--                                each image replaced by its size
local json = require("ports.json")

local M = {}

function M.shown(req)
  local function parts(c)
    if type(c) ~= "table" then return c end
    local out = {}
    for i, p in ipairs(c) do
      out[i] = p.type == "image_url" and { type = "image_url", bytes = #(p.image_url and p.image_url.url or "") } or p
    end
    return out
  end
  local msgs
  for i, m in ipairs(req.messages or {}) do
    msgs = msgs or {}
    msgs[i] = { role = m.role, content = parts(m.content), tool_calls = m.tool_calls }
  end
  local tools
  for i, tl in ipairs(req.tools or {}) do tools = tools or {} tools[i] = tl["function"] and tl["function"].name end
  return json.encode({ system = req.system, user = req.user, messages = msgs, tools = tools, state = parts(req.state),
    questions = req.questions })
end

local function clip(s, n) s = tostring(s or "") return #s > n and (s:sub(1, n) .. "...") or s end

local function names(list, max)
  max = max or 10
  if #list <= max then return table.concat(list, ", ") end
  local head = {}
  for i = 1, max do head[i] = list[i] end
  return table.concat(head, ", ") .. (" and %d more"):format(#list - max)
end

-- the errors of snapshot n by a key each (info and warnings judge nothing here), and its failing expectations' ids
local function errors_at(t, todo, n)
  local out, expects = {}, {}
  for _, f in ipairs(t:findings_of(todo, n)) do
    if (f.severity or "error") == "error" then
      local id = f.code == "expect_failed" and tostring(f.detail or ""):match("%(expect ([^)]+)%)%s*$")
      if id then expects[id] = true end
      out[(f.code or "") .. "\0" .. (f.id or "") .. "\0" .. (f.name or "") .. "\0" .. (id or "")] =
        { code = f.code, id = f.id, expect = id }
    end
  end
  return out, expects
end

local function count(set) local k = 0 for _ in pairs(set) do k = k + 1 end return k end

local function sorted(set, show)
  local out = {}
  for k, v in pairs(set) do out[#out + 1] = show and show(k, v) or k end
  table.sort(out)
  return out
end

-- what step n changed in the errors: "errors 1->3 (+2 expect_failed: almanac, tide-1; closed: contrast on date)"
local function delta(t, todo, n)
  local prev = t.db:exec("select max(n) as m from (select n from tablua_msr_comp where todo = ?1 and n < ?2 union all "
    .. "select n from tablua_msr_node where todo = ?1 and n < ?2)", { todo, n })[1].m or 0   -- 0: taken before any step
  local before, after = errors_at(t, todo, prev), errors_at(t, todo, n)
  local opened_x, opened, closed = {}, {}, {}
  for k, f in pairs(after) do
    if not before[k] then
      if f.expect then opened_x[f.expect] = true else opened[f.code .. (f.id ~= "" and (" on " .. f.id) or "")] = true end
    end
  end
  for k, f in pairs(before) do
    if not after[k] then closed[f.expect and ("expect " .. f.expect) or (f.code .. (f.id ~= "" and (" on " .. f.id) or ""))] = true end
  end
  if count(before) == count(after) and next(opened_x) == nil and next(opened) == nil then return nil end
  local parts = {}
  if next(opened_x) then parts[#parts + 1] = ("+%d expect_failed: %s"):format(count(opened_x), names(sorted(opened_x))) end
  if next(opened) then parts[#parts + 1] = ("+%d: %s"):format(count(opened), names(sorted(opened))) end
  if next(closed) then parts[#parts + 1] = "closed: " .. names(sorted(closed)) end
  return ("errors %d->%d%s"):format(count(before), count(after), #parts > 0 and (" (" .. table.concat(parts, "; ") .. ")") or "")
end

function M.history(t, todo, upto)
  local lines = {}
  for _, o in ipairs(t.db:exec("select n, verb, outcome, note from tablua_outcome where todo = ? and n <= ? order by n",
    { todo, upto })) do
    local targets, seen = {}, {}
    for _, a in ipairs(t.db:exec("select target from tablua_action where todo = ? and n = ? order by i", { todo, o.n })) do
      if a.target ~= "" and not seen[a.target] then seen[a.target] = true targets[#targets + 1] = a.target end
    end
    local line = ("step %d %s%s -> %s"):format(o.n, o.verb, #targets > 0 and (" " .. names(targets)) or "", o.outcome)
    local note, more = o.note or "", {}
    if o.verb == "treat" then
      -- the treatment is given whole beside the history; its line says only that it was written, and what came of
      -- the expectations
      more[1] = o.outcome == "complete" and "the treatment (given above)" or clip(note, 200)
      local x = note:match("; (%d+ expectations written.*)$") or note:match("; (no expectations.*)$")
        or note:match("; (expectations failed.*)$")
      if x then more[2] = clip(x, 200) end
    elseif o.verb == "look" then
      more[1] = clip(note, 200)
    else
      local snapped = #t.db:exec("select 1 from tablua_msr_comp where todo = ?1 and n = ?2 union all select 1 from "
        .. "tablua_msr_node where todo = ?1 and n = ?2 limit 1", { todo, o.n }) > 0
      local d = snapped and delta(t, todo, o.n)
      if d then more[#more + 1] = d end
      local why = note:match("rejected: (.-); %d+ findings")
      if why then more[#more + 1] = "rejected: " .. clip(why, 200)
      elseif not snapped and note ~= "" then more[#more + 1] = clip(note, 200) end
    end
    lines[#lines + 1] = line .. (#more > 0 and ("; " .. table.concat(more, "; ")) or "")
  end
  return table.concat(lines, "\n")
end

-- the card's sections by name, the text up to ":" or " (" of each "## " heading, in order
local function sections(card)
  local head, out, order, cur = {}, {}, {}, nil
  for line in (card .. "\n"):gmatch("(.-)\n") do
    local title = line:match("^## (.+)$")
    if title then
      cur = (title:match("^(.-):") or title:match("^(.-) %(") or title):gsub("%s+$", "")
      order[#order + 1], out[cur] = cur, { line }
    elseif cur then out[cur][#out[cur] + 1] = line
    else head[#head + 1] = line end
  end
  return table.concat(head, "\n"), out, order
end

M.needs = {
  add_node = { "Node kinds", "Keys and motion" }, set_prop = { "Node kinds" },
  add_key = { "Keys and motion" }, move_key = { "Keys and motion" }, drop_key = { "Keys and motion" },
  bind = { "Keys and motion", "Derive and facts" }, add_system = { "Systems and code" },
  edit_system = { "Systems and code" }, derive = { "Derive and facts", "Local media" }, solid = { "Solids", "3D" },
  remove = {}, expect = { "Node kinds", "Derive and facts" },
}
M.always = { "The moves", "Pitfalls" }
M.worldly = { add_node = true, set_prop = true, add_system = true, edit_system = true }   -- 3D when the comp has a world

function M.card(card, move, kind, world)
  local head, by, order = sections(card or "")
  if #order == 0 then return card end
  local want = {}
  for _, s in ipairs(M.always) do want[s] = true end
  for _, s in ipairs(M.needs[move] or {}) do want[s] = true end
  if world and M.worldly[move] then want["3D"] = true end
  if kind == "game" then want.Games = true end
  local out = { head }
  for _, s in ipairs(order) do if want[s] then out[#out + 1] = table.concat(by[s], "\n") end end
  return table.concat(out, "\n")
end

return M
