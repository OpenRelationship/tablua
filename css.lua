-- Utility classes, written as CSS on the server: Tailwind's names and values for layout, spacing, sizing, type,
-- colour, borders and effects, over Basecoat's theme (--spacing, --color-*, --radius-*, --text-*). Only the
-- classes a page uses become CSS, so a page needs no compiler in the browser.
--
--   css.rule("md:hover:bg-primary/10")   -> the CSS for one class, or nil if Shroomi does not know it
--   css.sheet(classes)                    -> the CSS for a list of classes, in cascade order; and the unknown ones
--
-- Variants: sm: md: lg: xl: 2xl: (min-width), hover: focus: focus-visible: active: disabled: first: last:
-- odd: even: group-hover:, dark:. Colours are the theme's (primary, secondary, muted, accent, destructive,
-- background, foreground, card, popover, border, input, ring, and their -foreground), white and black, with /N
-- for opacity.
local u = require("shroomi.utilities")

local css = {}

local SCREENS = { sm = "40rem", md = "48rem", lg = "64rem", xl = "80rem", ["2xl"] = "96rem" }
local SCREEN_RANK = { sm = 1, md = 2, lg = 3, xl = 4, ["2xl"] = 5 }
local STATES = {
  hover = ":hover", focus = ":focus", ["focus-visible"] = ":focus-visible", active = ":active",
  disabled = ":disabled", first = ":first-child", last = ":last-child", odd = ":nth-child(odd)",
  even = ":nth-child(even)",
}

-- a class as a CSS selector: every character outside [A-Za-z0-9_-] escaped
local function escape(name)
  local s = string.gsub(name, "[^%w_%-]", function(c) return "\\" .. c end)
  if string.match(s, "^%d") then s = "\\3" .. string.sub(s, 1, 1) .. " " .. string.sub(s, 2) end
  return s
end

local function split(name)
  local parts = {}
  for p in string.gmatch(name, "[^:]+") do parts[#parts + 1] = p end
  local utility = table.remove(parts)
  return parts, utility
end

-- one class: { css = text, order = {screen, state, family, name} } or nil
function css.rule(name)
  if type(name) ~= "string" or name == "" or #name > 80 then return nil end
  local variants, utility = split(name)
  if not utility then return nil end
  local important = false
  if string.sub(utility, 1, 1) == "!" then important, utility = true, string.sub(utility, 2) end
  local decls, family, child = u.declarations(utility)
  if not decls then return nil end
  local selector, screen, wrap_dark, group, state_rank = "." .. escape(name), nil, false, false, 0
  local pseudo = ""
  for _, v in ipairs(variants) do
    if SCREENS[v] then
      if screen then return nil end
      screen = v
    elseif STATES[v] then
      pseudo = pseudo .. STATES[v]
      state_rank = state_rank + 1
    elseif v == "group-hover" then
      group = true
      state_rank = state_rank + 1
    elseif v == "dark" then
      wrap_dark = true
    else
      return nil
    end
  end
  selector = selector .. pseudo
  if group then selector = ".group:hover " .. selector end
  if wrap_dark then selector = selector .. ":where(.dark, .dark *)" end
  if child then selector = selector .. child end
  local body = {}
  for _, d in ipairs(decls) do body[#body + 1] = d .. (important and " !important" or "") .. ";" end
  local text = selector .. "{" .. table.concat(body) .. "}"
  if screen then text = "@media (min-width: " .. SCREENS[screen] .. "){" .. text .. "}" end
  return { css = text, order = { screen and SCREEN_RANK[screen] or 0, state_rank, family, name } }
end

local function before(a, b)
  for i = 1, 4 do
    if a.order[i] ~= b.order[i] then return a.order[i] < b.order[i] end
  end
  return false
end

function css.sheet(classes)
  local seen, rules, unknown = {}, {}, {}
  for _, name in ipairs(classes) do
    if not seen[name] then
      seen[name] = true
      local r = css.rule(name)
      if r then rules[#rules + 1] = r else unknown[#unknown + 1] = name end
    end
  end
  table.sort(rules, before)
  local out = {}
  for i, r in ipairs(rules) do out[i] = r.css end
  if #out == 0 then return "", unknown end
  return "@layer utilities{" .. table.concat(out, "\n") .. "}", unknown
end

-- every class named in an HTML text, in order of first use
function css.classes(html)
  local list = {}
  for value in string.gmatch(html, "class%s*=%s*\"([^\"]*)\"") do
    for name in string.gmatch(value, "%S+") do list[#list + 1] = name end
  end
  return list
end

return css
