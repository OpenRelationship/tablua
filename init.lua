-- Shroomi: how an agent publishes its work. A page is Lua that builds HTML: elements and components as tables,
-- rendered with every text escaped, styled by Basecoat's components and utility classes Shroomi writes as CSS,
-- moved by htmx. No script of the agent's own runs; the host cleans every page by Shroomi's policy.
--
--   local ui = require("shroomi")
--   ui.div{ class = "flex gap-2", ui.h1"Plants", "any text, escaped", ui.raw("<b>markup</b>") }
--     every HTML tag the policy allows is ui.<tag>; a table's string keys are attributes, its list its children;
--     true is a bare attribute, false or nil none; class may be a list
--     htmx in short: get, post, put, patch, delete, target, swap, trigger, confirm, vals become hx-*
--   ui.button{ "Add", variant = "outline", post = "plants" }, ui.card{ title = "Ferns", ... } and the rest of the
--     kit (ui.kit lists them); ui.component("name", function(props, children) return node end) adds one
--   ui.page{ title = "Plants", ...children } -> a whole document, its CSS and scripts included; light or dark as
--     the person's system is, or dark = true / false to fix it
--   ui.render(node) -> HTML;  ui.template(text, view) -> Mustache;  ui.escape(s)
--   ui.check(html) -> the classes Shroomi does not know, to fix before publishing
local css = require("shroomi.css")
local template = require("shroomi.template")
local policy = require("shroomi.policy")

local ui = { policy = policy, css = css }

local NODE, RAW = {}, {}

-- the largest index in a list with holes (a child left out as nil), as table.maxn once gave
local function maxn(t)
  local n = 0
  for k in pairs(t) do if type(k) == "number" and k > n and k % 1 == 0 then n = k end end
  return n
end
ui.maxn = maxn

local ENTITIES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }

function ui.escape(s)
  if s == nil then return "" end
  return (string.gsub(tostring(s), "[&<>\"']", ENTITIES))
end

function ui.raw(html) return setmetatable({ html = tostring(html or "") }, RAW) end

local HX = { get = true, post = true, put = true, patch = true, delete = true, target = true, swap = true,
  trigger = true, confirm = true, vals = true, select = true, include = true, indicator = true, ["push-url"] = true }

-- a node from props: string keys are attributes, the list its children
function ui.el(tag, props)
  if type(props) ~= "table" or getmetatable(props) then props = { props } end
  local attrs, children = {}, {}
  for k, v in pairs(props) do
    if type(k) == "string" then
      local name = HX[k] and "hx-" .. k or k
      if name == "class" and type(v) == "table" then v = table.concat(v, " ") end
      attrs[name] = v
    end
  end
  local n = maxn(props)
  for i = 1, n do children[i] = props[i] end
  return setmetatable({ tag = tag, attrs = attrs, children = children, n = n }, NODE)
end

local VOID = { area = true, br = true, col = true, hr = true, img = true, input = true, wbr = true, source = true }

local function render(node, out)
  local kind = type(node)
  if node == nil or node == false then return end
  if kind ~= "table" then
    out[#out + 1] = ui.escape(node)
    return
  end
  local mt = getmetatable(node)
  if mt == RAW then
    out[#out + 1] = node.html
  elseif mt == NODE then
    local names = {}
    for k in pairs(node.attrs) do names[#names + 1] = k end
    table.sort(names)
    out[#out + 1] = "<" .. node.tag
    for _, k in ipairs(names) do
      local v = node.attrs[k]
      if v == true then
        out[#out + 1] = " " .. k
      elseif v ~= false and v ~= nil then
        out[#out + 1] = " " .. k .. "=\"" .. ui.escape(v) .. "\""
      end
    end
    out[#out + 1] = ">"
    if not VOID[node.tag] then
      for i = 1, node.n do render(node.children[i], out) end
      out[#out + 1] = "</" .. node.tag .. ">"
    end
  else
    for i = 1, maxn(node) do render(node[i], out) end
  end
end

function ui.render(node)
  -- ui.page's answer is already the whole document; rendering it again would show its source as text
  if type(node) == "string" and string.sub(node, 1, 15) == "<!doctype html>" then return node end
  local out = {}
  render(node, out)
  return table.concat(out)
end

ui.template = template.render

-- components: the kit, and any the agent adds
local components = {}
ui.kit = {}

function ui.component(name, fn)
  assert(type(name) == "string" and string.match(name, "^[%a_][%w_]*$"), "a component needs a plain name")
  assert(type(fn) == "function", "a component is a function(props, children) -> node")
  if not components[name] then ui.kit[#ui.kit + 1] = name end
  components[name] = fn
end

-- props split into the component's own (string keys) and its children (the list)
local function call(name, props)
  if type(props) ~= "table" or getmetatable(props) then props = { props } end
  local own, children = {}, {}
  for k, v in pairs(props) do if type(k) == "string" then own[k] = v end end
  for i = 1, maxn(props) do children[i] = props[i] end
  return components[name](own, children)
end

setmetatable(ui, {
  __index = function(_, name)
    if components[name] then return function(props) return call(name, props) end end
    if policy.tags[name] then return function(props) return ui.el(name, props) end end
    return nil
  end,
})

require("shroomi.components")(ui)

function ui.check(html)
  local _, unknown = css.sheet(css.classes(html))
  return unknown
end

-- the whole document: Basecoat, the CSS for the classes it uses, htmx and Basecoat's scripts, from the host
function ui.page(props)
  if type(props) ~= "table" then props = { props } end
  local body = {}
  for i = 1, maxn(props) do body[i] = props[i] end
  local inner = ui.render(ui.el("body", { class = props.class or "min-h-screen bg-background text-foreground", body }))
  local sheet = css.sheet(css.classes(inner))
  local a = policy.assets
  local theme = props.dark == true and ' class="dark" data-theme="dark"' or
    props.dark == false and ' data-theme="light"' or ' data-theme="auto"'
  return "<!doctype html>\n<html lang=\"en\"" .. theme .. "><head>" ..
    "<meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" ..
    "<title>" .. ui.escape(props.title or "") .. "</title>" ..
    "<meta name=\"htmx-config\" content='{\"allowEval\":false,\"includeIndicatorStyles\":false}'>" ..
    "<link rel=\"stylesheet\" href=\"" .. a.css .. "\">" ..
    (sheet ~= "" and "<style>" .. sheet .. "</style>" or "") ..
    "<script src=\"" .. a.htmx .. "\"></script><script src=\"" .. a.basecoat .. "\" defer></script>" ..
    "<script src=\"" .. a.shroomi .. "\"></script>" ..
    "</head>" .. inner .. "</html>\n"
end

return ui
