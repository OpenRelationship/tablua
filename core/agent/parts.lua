-- A long request in parts: Jev may plan it (Mercury writes two to eight goals, in order), and
-- from then on every prompt shows each part as done, now or to do. Jev moves on with next_part when the part's
-- goal is met; after the last it reads that every part is done. Nothing caps the parts or their steps.
--
--   parts.options(a, options)     adds plan (no parts yet) or next_part (a part under way) to Jev's options; once
--                                 every part is done, neither (an eval's Jev took next_part 84 times with none left)
--   parts.plan(a, req, step)      parts.next(a, req, step)      parts.render(req) -> line | nil
local json = require("ports.json")

local M = {}
M.MAX = 8

M.verbs = {
  plan = "Split this request into parts, each with its own goal, done in order: for a request that will take more"
    .. " than a few steps or has several things to get done.",
  next_part = "The current part's goal is met: mark it done and go on to the next part.",
}

function M.options(a, options)
  local req = a.req
  if not (req and req.parts) then options.plan = M.verbs.plan
  elseif req.part <= #req.parts then options.next_part = M.verbs.next_part end
end

function M.render(req)
  if not req.parts then return nil end
  if req.part > #req.parts then return "Every part of this request is done; answer the person." end
  local out = {}
  for i, g in ipairs(req.parts) do
    out[i] = ("%d. %s: %s"):format(i, i < req.part and "done" or i == req.part and "now" or "to do", g)
  end
  return ("Parts of this request (now: %d): %s"):format(req.part, table.concat(out, "; "))
end

function M.plan(a, req, step)
  local ok, text = pcall(a.env.mercury.chat, a.env.mercury, { kind = "parts", json = true,
    system = "You split the person's request to " .. a.name .. " into parts, done in order, each with one goal that"
      .. " can be seen to be met (as: Notes is open; a note titled Groceries exists). Two to eight parts. Reply with"
      .. " JSON only: {\"parts\": [{\"goal\": \"...\"}, ...]}.",
    user = a.world.state(a, req, false) .. "\n\nThe parts:" })
  local okj, v = pcall(json.decode, ok and tostring(text):gsub("^%s*```%w*%s*", ""):gsub("%s*```%s*$", "") or "")
  local goals = {}
  for _, p in ipairs(okj and type(v) == "table" and type(v.parts) == "table" and v.parts or {}) do
    local g = type(p) == "table" and p.goal or p
    if type(g) == "string" and g:match("%S") and #goals < M.MAX then goals[#goals + 1] = g:gsub("%s+", " ") end
  end
  if #goals < 2 then
    step.note = "Planning the parts failed: " .. (ok and "Mercury did not give two or more goals" or tostring(text))
    return
  end
  req.parts, req.part = goals, 1
  step.note = ("Planned in %d parts."):format(#goals)
  a:rows("Parts Planned", { table.concat(goals, " | ") })
end

function M.next(a, req, step)
  if not req.parts or req.part > #req.parts then step.note = "There is no part under way." return end
  a:rows("Part Done", { tostring(req.part), req.parts[req.part] })
  step.note = ("Part %d is done: %s."):format(req.part, req.parts[req.part])
  req.part = req.part + 1
end

return M
