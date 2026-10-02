-- Utility classes, written as CSS on the server: Tailwind's names and values for layout, spacing, sizing, type,
-- colour, borders and effects, over Basecoat's theme (--spacing, --color-*, --radius-*, --text-*). Only the
-- classes a page uses become CSS, so a page needs no compiler in the browser.
--
--   css.rule("md:hover:bg-primary/10")   -> the CSS for one class, or nil if Shroomi does not know it
--   css.sheet(classes)                    -> the CSS for a list of classes, in cascade order; and the unknown ones
--   css.known(name)                        -> whether a class is a utility, one of Basecoat's components, or prose
--
-- Variants: sm: md: lg: xl: 2xl: (min-width), hover: focus: focus-visible: active: disabled: first: last:
-- odd: even: group-hover:, dark:. Colours are the theme's (primary, secondary, muted, accent, destructive,
-- background, foreground, card, popover, border, input, ring, and their -foreground), white and black, with /N
-- for opacity.
local u = require("shroomi.utilities")

local css = {}

-- Basecoat's own component classes: known, styled by its stylesheet, so no CSS is written for them here
local COMPONENTS = {}
for name in string.gmatch([[btn card card-title card-description card-action alert alert-dialog badge field fieldset
  field-separator input input-group textarea select label kbd table table-container tabs dialog empty item
  item-group progress skeleton form toaster toast toast-content popover dropdown-menu sidebar group dark]],
  "%S+") do COMPONENTS[name] = true end

-- Markdown's typography: Tailwind's reset takes headings, lists and quotes back to plain text, so `prose` puts
-- them back, in the theme's sizes and colours
local PROSE = table.concat({
  ".prose{line-height: 1.7;}",
  ".prose > * + *{margin-top: 1em;}",
  ".prose h1{font-size: 1.875rem; line-height: 2.25rem; font-weight: 600; letter-spacing: -0.025em;}",
  ".prose h2{font-size: 1.5rem; line-height: 2rem; font-weight: 600; margin-top: 1.5em;}",
  ".prose h3{font-size: 1.25rem; line-height: 1.75rem; font-weight: 600; margin-top: 1.25em;}",
  ".prose ul{list-style-type: disc; padding-left: 1.5em;}",
  ".prose ol{list-style-type: decimal; padding-left: 1.5em;}",
  ".prose li + li{margin-top: 0.25em;}",
  ".prose a{color: var(--color-primary); text-decoration-line: underline; text-underline-offset: 2px;}",
  ".prose strong{font-weight: 600;}",
  ".prose blockquote{border-left: 3px solid var(--color-border); padding-left: 1em; color: var(--color-muted-foreground);}",
  ".prose code{font-family: var(--font-mono); font-size: 0.875em; background: var(--color-muted); " ..
    "border-radius: var(--radius-sm); padding: 0.125em 0.375em;}",
  ".prose pre{background: var(--color-muted); border-radius: var(--radius-md); padding: 1em; overflow-x: auto;}",
  ".prose pre code{background: none; padding: 0;}",
  ".prose hr{border-top: 1px solid var(--color-border);}",
}, "\n")

function css.known(name) return COMPONENTS[name] == true or name == "prose" or css.rule(name) ~= nil end

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
  local seen, rules, unknown, prose = {}, {}, {}, false
  for _, name in ipairs(classes) do
    if not seen[name] then
      seen[name] = true
      local r = css.rule(name)
      if r then
        rules[#rules + 1] = r
      elseif name == "prose" then
        prose = true
      elseif not COMPONENTS[name] then
        unknown[#unknown + 1] = name
      end
    end
  end
  table.sort(rules, before)
  local out = {}
  for i, r in ipairs(rules) do out[i] = r.css end
  local sheet = #out > 0 and "@layer utilities{" .. table.concat(out, "\n") .. "}" or ""
  if prose then sheet = "@layer components{" .. PROSE .. "}" .. (sheet ~= "" and "\n" .. sheet or "") end
  return sheet, unknown
end

-- every class named in an HTML text, in order of first use
function css.classes(html)
  -- in tags only: a page that shows code holds class="..." as text
  local list = {}
  for tag in string.gmatch(html, "<%a[^>]*>") do
    for value in string.gmatch(tag, "%sclass%s*=%s*\"([^\"]*)\"") do
      for name in string.gmatch(value, "%S+") do list[#list + 1] = name end
    end
  end
  return list
end

return css
