-- The utility classes Shroomi knows, as Tailwind v4 names them: utilities.declarations("px-4") gives the
-- declarations, the family's place in the cascade (later families win, so px- beats p-), and a child selector
-- for the few that style children (space-x-, space-y-, divide-).
local M = {}

local fixed = {
  -- display and position (family 10)
  block = { 10, "display: block" }, ["inline-block"] = { 10, "display: inline-block" },
  inline = { 10, "display: inline" }, flex = { 10, "display: flex" },
  ["inline-flex"] = { 10, "display: inline-flex" }, grid = { 10, "display: grid" },
  hidden = { 10, "display: none" }, contents = { 10, "display: contents" },
  relative = { 11, "position: relative" }, absolute = { 11, "position: absolute" },
  fixed = { 11, "position: fixed" }, sticky = { 11, "position: sticky" }, static = { 11, "position: static" },
  ["sr-only"] = { 11, "position: absolute", "width: 1px", "height: 1px", "padding: 0", "margin: -1px",
    "overflow: hidden", "clip: rect(0, 0, 0, 0)", "white-space: nowrap", "border-width: 0" },
  -- flex and grid (20)
  ["flex-row"] = { 20, "flex-direction: row" }, ["flex-col"] = { 20, "flex-direction: column" },
  ["flex-row-reverse"] = { 20, "flex-direction: row-reverse" },
  ["flex-col-reverse"] = { 20, "flex-direction: column-reverse" },
  ["flex-wrap"] = { 20, "flex-wrap: wrap" }, ["flex-nowrap"] = { 20, "flex-wrap: nowrap" },
  ["flex-1"] = { 21, "flex: 1 1 0%" }, ["flex-auto"] = { 21, "flex: 1 1 auto" }, ["flex-none"] = { 21, "flex: none" },
  grow = { 21, "flex-grow: 1" }, ["grow-0"] = { 21, "flex-grow: 0" },
  shrink = { 21, "flex-shrink: 1" }, ["shrink-0"] = { 21, "flex-shrink: 0" },
  ["items-start"] = { 22, "align-items: flex-start" }, ["items-center"] = { 22, "align-items: center" },
  ["items-end"] = { 22, "align-items: flex-end" }, ["items-stretch"] = { 22, "align-items: stretch" },
  ["items-baseline"] = { 22, "align-items: baseline" },
  ["justify-start"] = { 22, "justify-content: flex-start" }, ["justify-center"] = { 22, "justify-content: center" },
  ["justify-end"] = { 22, "justify-content: flex-end" }, ["justify-between"] = { 22, "justify-content: space-between" },
  ["justify-around"] = { 22, "justify-content: space-around" },
  ["justify-evenly"] = { 22, "justify-content: space-evenly" },
  ["self-start"] = { 22, "align-self: flex-start" }, ["self-center"] = { 22, "align-self: center" },
  ["self-end"] = { 22, "align-self: flex-end" }, ["self-stretch"] = { 22, "align-self: stretch" },
  ["place-items-center"] = { 22, "place-items: center" },
  ["col-span-full"] = { 23, "grid-column: 1 / -1" },
  -- sizing words (40)
  ["w-full"] = { 40, "width: 100%" }, ["w-screen"] = { 40, "width: 100vw" }, ["w-auto"] = { 40, "width: auto" },
  ["w-fit"] = { 40, "width: fit-content" }, ["w-min"] = { 40, "width: min-content" },
  ["w-max"] = { 40, "width: max-content" },
  ["h-full"] = { 41, "height: 100%" }, ["h-screen"] = { 41, "height: 100vh" }, ["h-auto"] = { 41, "height: auto" },
  ["h-fit"] = { 41, "height: fit-content" }, ["h-dvh"] = { 41, "height: 100dvh" },
  ["min-w-0"] = { 42, "min-width: 0" }, ["min-w-full"] = { 42, "min-width: 100%" },
  ["min-h-0"] = { 42, "min-height: 0" }, ["min-h-full"] = { 42, "min-height: 100%" },
  ["min-h-screen"] = { 42, "min-height: 100vh" }, ["min-h-dvh"] = { 42, "min-height: 100dvh" },
  ["max-w-none"] = { 43, "max-width: none" }, ["max-w-full"] = { 43, "max-width: 100%" },
  ["max-w-prose"] = { 43, "max-width: 65ch" }, ["max-w-screen"] = { 43, "max-width: 100vw" },
  ["mx-auto"] = { 32, "margin-inline: auto" }, ["my-auto"] = { 32, "margin-block: auto" },
  ["ml-auto"] = { 33, "margin-left: auto" }, ["mr-auto"] = { 33, "margin-right: auto" },
  ["mt-auto"] = { 33, "margin-top: auto" }, ["m-auto"] = { 31, "margin: auto" },
  ["aspect-square"] = { 44, "aspect-ratio: 1 / 1" }, ["aspect-video"] = { 44, "aspect-ratio: 16 / 9" },
  -- type (50)
  ["text-left"] = { 52, "text-align: left" }, ["text-center"] = { 52, "text-align: center" },
  ["text-right"] = { 52, "text-align: right" }, ["text-justify"] = { 52, "text-align: justify" },
  ["font-normal"] = { 51, "font-weight: 400" }, ["font-medium"] = { 51, "font-weight: 500" },
  ["font-semibold"] = { 51, "font-weight: 600" }, ["font-bold"] = { 51, "font-weight: 700" },
  ["font-mono"] = { 51, "font-family: var(--font-mono)" }, ["font-sans"] = { 51, "font-family: var(--font-sans)" },
  italic = { 53, "font-style: italic" }, ["not-italic"] = { 53, "font-style: normal" },
  uppercase = { 53, "text-transform: uppercase" }, lowercase = { 53, "text-transform: lowercase" },
  capitalize = { 53, "text-transform: capitalize" }, ["normal-case"] = { 53, "text-transform: none" },
  underline = { 53, "text-decoration-line: underline" }, ["no-underline"] = { 53, "text-decoration-line: none" },
  ["line-through"] = { 53, "text-decoration-line: line-through" },
  truncate = { 53, "overflow: hidden", "text-overflow: ellipsis", "white-space: nowrap" },
  ["whitespace-nowrap"] = { 53, "white-space: nowrap" }, ["whitespace-pre"] = { 53, "white-space: pre" },
  ["whitespace-pre-wrap"] = { 53, "white-space: pre-wrap" }, ["break-words"] = { 53, "overflow-wrap: break-word" },
  ["break-all"] = { 53, "word-break: break-all" }, ["tabular-nums"] = { 53, "font-variant-numeric: tabular-nums" },
  ["leading-none"] = { 54, "line-height: 1" }, ["leading-tight"] = { 54, "line-height: 1.25" },
  ["leading-snug"] = { 54, "line-height: 1.375" }, ["leading-normal"] = { 54, "line-height: 1.5" },
  ["leading-relaxed"] = { 54, "line-height: 1.625" }, ["leading-loose"] = { 54, "line-height: 2" },
  ["tracking-tight"] = { 54, "letter-spacing: -0.025em" }, ["tracking-normal"] = { 54, "letter-spacing: 0" },
  ["tracking-wide"] = { 54, "letter-spacing: 0.025em" },
  ["list-none"] = { 55, "list-style-type: none" }, ["list-disc"] = { 55, "list-style-type: disc" },
  ["list-decimal"] = { 55, "list-style-type: decimal" }, ["list-inside"] = { 55, "list-style-position: inside" },
  -- borders and effects (70)
  border = { 70, "border-style: solid", "border-width: 1px" },
  ["border-t"] = { 71, "border-top-style: solid", "border-top-width: 1px" },
  ["border-b"] = { 71, "border-bottom-style: solid", "border-bottom-width: 1px" },
  ["border-l"] = { 71, "border-left-style: solid", "border-left-width: 1px" },
  ["border-r"] = { 71, "border-right-style: solid", "border-right-width: 1px" },
  ["border-dashed"] = { 72, "border-style: dashed" }, ["border-none"] = { 72, "border-style: none" },
  rounded = { 74, "border-radius: var(--radius-sm)" }, ["rounded-none"] = { 74, "border-radius: 0" },
  ["rounded-full"] = { 74, "border-radius: 9999px" },
  shadow = { 76, "box-shadow: 0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)" },
  ["shadow-none"] = { 76, "box-shadow: 0 0 #0000" },
  ["overflow-hidden"] = { 80, "overflow: hidden" }, ["overflow-auto"] = { 80, "overflow: auto" },
  ["overflow-scroll"] = { 80, "overflow: scroll" }, ["overflow-x-auto"] = { 80, "overflow-x: auto" },
  ["overflow-y-auto"] = { 80, "overflow-y: auto" }, ["overflow-visible"] = { 80, "overflow: visible" },
  ["object-cover"] = { 81, "object-fit: cover" }, ["object-contain"] = { 81, "object-fit: contain" },
  ["cursor-pointer"] = { 82, "cursor: pointer" }, ["cursor-default"] = { 82, "cursor: default" },
  ["select-none"] = { 82, "user-select: none" }, ["pointer-events-none"] = { 82, "pointer-events: none" },
  transition = { 83, "transition-property: color, background-color, border-color, opacity, box-shadow, transform",
    "transition-duration: 150ms", "transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1)" },
  ["inset-0"] = { 12, "inset: 0" },
  group = { 1 },
}

local SHADOWS = {
  sm = "0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)",
  md = "0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1)",
  lg = "0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)",
  xl = "0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1)",
}
local RADII = { sm = "var(--radius-sm)", md = "var(--radius-md)", lg = "var(--radius-lg)",
  xl = "var(--radius-xl)", ["2xl"] = "calc(var(--radius) + 8px)", ["3xl"] = "calc(var(--radius) + 12px)" }
local CORNERS = {
  ["rounded-t"] = { "border-top-left-radius", "border-top-right-radius" },
  ["rounded-b"] = { "border-bottom-left-radius", "border-bottom-right-radius" },
  ["rounded-l"] = { "border-top-left-radius", "border-bottom-left-radius" },
  ["rounded-r"] = { "border-top-right-radius", "border-bottom-right-radius" },
}
local TEXT = {
  xs = { "0.75rem", "1rem" }, sm = { "0.875rem", "1.25rem" }, base = { "1rem", "1.5rem" },
  lg = { "1.125rem", "1.75rem" }, xl = { "1.25rem", "1.75rem" }, ["2xl"] = { "1.5rem", "2rem" },
  ["3xl"] = { "1.875rem", "2.25rem" }, ["4xl"] = { "2.25rem", "2.5rem" }, ["5xl"] = { "3rem", "1" },
  ["6xl"] = { "3.75rem", "1" },
}
local MAX_W = { xs = "20rem", sm = "24rem", md = "28rem", lg = "32rem", xl = "36rem", ["2xl"] = "42rem",
  ["3xl"] = "48rem", ["4xl"] = "56rem", ["5xl"] = "64rem", ["6xl"] = "72rem", ["7xl"] = "80rem" }
local COLORS = {}
for _, c in ipairs({ "primary", "secondary", "muted", "accent", "destructive", "popover", "card", "sidebar" }) do
  COLORS[c] = "var(--color-" .. c .. ")"
  COLORS[c .. "-foreground"] = "var(--color-" .. c .. "-foreground)"
end
for _, c in ipairs({ "background", "foreground", "border", "input", "ring" }) do COLORS[c] = "var(--color-" .. c .. ")" end
COLORS.white, COLORS.black, COLORS.transparent, COLORS.current = "#fff", "#000", "transparent", "currentColor"

-- spacing steps: 0, 0.5, 1 ... 96 and px
local function space(v)
  if v == "px" then return "1px" end
  local n = tonumber(v)
  if not (string.match(v, "^%d+$") or string.match(v, "^%d+%.5$")) or n > 96 then return nil end
  if n == 0 then return "0" end
  return "calc(var(--spacing) * " .. v .. ")"
end

local function fraction(v)
  local a, b = string.match(v, "^(%d+)/(%d+)$")
  if not a or tonumber(b) == 0 or tonumber(b) > 12 then return nil end
  return string.format("%.6g%%", tonumber(a) / tonumber(b) * 100)
end

local function color(v)
  local name, alpha = string.match(v, "^([%w%-]+)/(%d+)$")
  if not name then return COLORS[v] end
  local base, a = COLORS[name], tonumber(alpha)
  if not base or a > 100 then return nil end
  return "color-mix(in oklab, " .. base .. " " .. a .. "%, transparent)"
end

local SIDES = {
  p = { 34, { "padding" } }, px = { 35, { "padding-inline" } }, py = { 35, { "padding-block" } },
  pt = { 36, { "padding-top" } }, pr = { 36, { "padding-right" } }, pb = { 36, { "padding-bottom" } },
  pl = { 36, { "padding-left" } },
  m = { 31, { "margin" } }, mx = { 32, { "margin-inline" } }, my = { 32, { "margin-block" } },
  mt = { 33, { "margin-top" } }, mr = { 33, { "margin-right" } }, mb = { 33, { "margin-bottom" } },
  ml = { 33, { "margin-left" } },
  gap = { 24, { "gap" } }, ["gap-x"] = { 25, { "column-gap" } }, ["gap-y"] = { 25, { "row-gap" } },
  w = { 40, { "width" } }, h = { 41, { "height" } }, size = { 40, { "width", "height" } },
  ["min-w"] = { 42, { "min-width" } }, ["min-h"] = { 42, { "min-height" } }, ["max-h"] = { 43, { "max-height" } },
  top = { 12, { "top" } }, right = { 12, { "right" } }, bottom = { 12, { "bottom" } }, left = { 12, { "left" } },
  inset = { 12, { "inset" } },
}

local function each(props, value)
  local out = {}
  for i, p in ipairs(props) do out[i] = p .. ": " .. value end
  return out
end

local KEYS = { ["space-y"] = true, ["space-x"] = true, ["grid-cols"] = true, ["grid-rows"] = true,
  ["col-span"] = true, ["row-span"] = true, ["max-w"] = true, text = true, bg = true, border = true, ring = true,
  rounded = true, ["rounded-t"] = true, ["rounded-b"] = true, ["rounded-l"] = true, ["rounded-r"] = true,
  shadow = true, opacity = true, z = true }
for k in pairs(SIDES) do KEYS[k] = true end

-- "gap-x-4" -> "gap-x", "4": the longest known key before a dash
function M.split(name)
  local best
  local at = 1
  while true do
    local dash = string.find(name, "-", at, true)
    if not dash then break end
    if KEYS[string.sub(name, 1, dash - 1)] then best = dash end
    at = dash + 1
  end
  if not best or best == #name then return nil end
  return string.sub(name, 1, best - 1), string.sub(name, best + 1)
end

-- the declarations, family and child selector for a utility (no variants), or nil
function M.declarations(name)
  local f = fixed[name]
  if f then
    local decls = {}
    for i = 2, #f do decls[#decls + 1] = f[i] end
    return decls, f[1]
  end
  local neg, rest = string.match(name, "^(%-?)(.+)$")
  local key, value = M.split(rest)
  if not key then return nil end
  local side = SIDES[key]
  if side then
    local v = space(value) or (side[1] >= 40 and side[1] <= 43 or side[1] == 12) and fraction(value)
    if not v then return nil end
    if neg == "-" then
      if not string.match(key, "^m") and side[1] ~= 12 then return nil end
      v = "calc(" .. v .. " * -1)"
    end
    return each(side[2], v), side[1]
  end
  if neg == "-" then return nil end
  if key == "space-y" or key == "space-x" then
    local v = space(value)
    if not v then return nil end
    local prop = key == "space-y" and "margin-block-end" or "margin-inline-end"
    return { prop .. ": " .. v }, 26, " > :not(:last-child)"
  elseif key == "grid-cols" or key == "grid-rows" then
    local n = tonumber(value)
    if not n or n < 1 or n > 12 or n % 1 ~= 0 then return nil end
    local prop = key == "grid-cols" and "grid-template-columns" or "grid-template-rows"
    return { prop .. ": repeat(" .. n .. ", minmax(0, 1fr))" }, 23
  elseif key == "col-span" or key == "row-span" then
    local n = tonumber(value)
    if not n or n < 1 or n > 12 or n % 1 ~= 0 then return nil end
    return { (key == "col-span" and "grid-column" or "grid-row") .. ": span " .. n .. " / span " .. n }, 23
  elseif key == "max-w" and MAX_W[value] then
    return { "max-width: " .. MAX_W[value] }, 43
  elseif key == "text" then
    if TEXT[value] then return { "font-size: " .. TEXT[value][1], "line-height: " .. TEXT[value][2] }, 50 end
    local c = color(value)
    return c and { "color: " .. c }, 56
  elseif key == "bg" then
    local c = color(value)
    return c and { "background-color: " .. c }, 60
  elseif key == "border" then
    local n = tonumber(value)
    if n and (n == 0 or n == 2 or n == 4 or n == 8) then return { "border-style: solid", "border-width: " .. n .. "px" }, 70 end
    local c = color(value)
    return c and { "border-color: " .. c }, 73
  elseif key == "ring" then
    local n = tonumber(value)
    if n and n <= 8 and n % 1 == 0 then return { "box-shadow: 0 0 0 " .. n .. "px var(--color-ring)" }, 77 end
    return nil
  elseif key == "rounded" then
    return RADII[value] and { "border-radius: " .. RADII[value] }, 74
  elseif CORNERS[key] then
    local r = RADII[value] or (value == "none" and "0") or (value == "full" and "9999px")
    if not r then return nil end
    return { CORNERS[key][1] .. ": " .. r, CORNERS[key][2] .. ": " .. r }, 75
  elseif key == "shadow" then
    return SHADOWS[value] and { "box-shadow: " .. SHADOWS[value] }, 76
  elseif key == "opacity" then
    local n = tonumber(value)
    if not n or n < 0 or n > 100 or n % 5 ~= 0 then return nil end
    return { "opacity: " .. (n / 100) }, 78
  elseif key == "z" then
    local n = tonumber(value)
    if not n or n < 0 or n > 50 or n % 10 ~= 0 then return nil end
    return { "z-index: " .. n }, 13
  end
  return nil
end

return M
