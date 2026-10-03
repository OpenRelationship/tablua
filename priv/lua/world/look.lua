-- How the world judges a look at the app (look_at_app): looking is using. Each command of the move's calls is read
-- (a line may hold several: open app; type 1 Fern; submit 1), then the look is judged against what the computer
-- printed and, once more, against the page opened again.
--
--   local seen = look.new()
--   look.read(seen, call, result)   for each call the move ran
--   look.judge(host, step, seen)    the step's outcome: no_effect when it only opened, broken when what it typed
--                                   never showed, or showed and was gone once the page was opened again
local M = {}

function M.new() return { used = false, typed = {}, shown = "", opened = nil } end

-- a submit or click is using the app; what was typed is its last word (type "Plant name" "Pothos": Pothos); the
-- first open is the page to come back to; once used, what the page said
function M.read(seen, c, r)
  for part in (c.cmd or ""):gmatch("[^;&|]+") do
    local word = part:match("^%s*(%a+)")
    if word == "open" and not seen.opened then seen.opened = part:match("^%s*(.-)%s*$") end
    if r.code == 0 and (word == "submit" or word == "click") then seen.used = true end
    if word == "type" then seen.typed[#seen.typed + 1] = part:match("([%w%-]+)[\"']?%s*$") end
  end
  if seen.used then seen.shown = seen.shown .. (r.stdout or "") end
end

local function holds(text, typed)
  for _, t in ipairs(typed) do
    if text:find(t, 1, true) then return true end
  end
  return false
end

function M.judge(host, step, seen)
  if step.outcome ~= "complete" then return end
  -- a look that only opened the page saw nothing of its form (a habits page whose form went nowhere shipped on a
  -- look that never submitted it)
  if not seen.used then
    step.outcome = "no_effect"
    step.lines[#step.lines + 1] = "Only opened: using the app is typing in its form and submitting it (or clicking"
      .. " its button), then reading the page for what was added."
    return
  end
  if #seen.typed == 0 then return end
  -- what was typed shows on the page after: a page whose form went to an empty get.add showed nothing it was given
  if not holds(seen.shown, seen.typed) then
    step.outcome = "broken"
    step.lines[#step.lines + 1] = ("Typed %s and sent it, but the page after shows none of it: the form keeps"
      .. " nothing. Read the page's form and the action it names."):format(table.concat(seen.typed, ", "))
    return
  end
  -- and is still there when the page is opened again, as the person comes back to it: a pantry kept its items in
  -- a Lua table, shown in the answer to the form and gone from the next request
  if seen.opened and not holds(host.exec({ cmd = seen.opened }).stdout or "", seen.typed) then
    step.outcome = "broken"
    step.lines[#step.lines + 1] = ("%s showed after the submit but is gone once the page is opened again: the app"
      .. " keeps it in memory, and each request starts afresh. Keep it with db.open."):format(seen.typed[1])
  end
end

return M
