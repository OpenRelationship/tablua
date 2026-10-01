-- Mustache templates: HTML with holes, for pages written as text rather than built from elements.
--
--   template.render(text, view [, partials])
--     {{name}}  the value, escaped        {{{name}}} or {{&name}}  the value as is (the host still cleans it)
--     {{a.b}}   a field of a field        {{.}}  the current item
--     {{#list}}...{{/list}}  once per item of a list, or once if the value is true or a table
--     {{^list}}...{{/list}}  once if the value is missing, false or an empty list
--     {{>name}} a partial                 {{! a comment }}
local html = {}

local ENTITIES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }

function html.escape(s)
  if s == nil then return "" end
  return (string.gsub(tostring(s), "[&<>\"']", ENTITIES))
end

local function lookup(stack, name)
  if name == "." then return stack[#stack] end
  local first, rest = string.match(name, "^([^%.]+)%.?(.*)$")
  for i = #stack, 1, -1 do
    local ctx = stack[i]
    if type(ctx) == "table" and ctx[first] ~= nil then
      local v = ctx[first]
      for part in string.gmatch(rest, "[^%.]+") do
        if type(v) ~= "table" then return nil end
        v = v[part]
      end
      return v
    end
  end
  return nil
end

local function is_list(v) return type(v) == "table" and (v[1] ~= nil or next(v) == nil) end

local function falsy(v) return v == nil or v == false or (is_list(v) and v[1] == nil) end

-- the template as a tree: strings, and { kind, name, children }
local function parse(tpl)
  local root, stack, at = {}, {}, 1
  local node = root
  while true do
    local s, e, triple = string.find(tpl, "{{({?)", at)
    if not s then node[#node + 1] = string.sub(tpl, at) break end
    node[#node + 1] = string.sub(tpl, at, s - 1)
    local close = triple == "{" and "}}}" or "}}"
    local cs, ce = string.find(tpl, close, e + 1, true)
    if not cs then error("html: a tag at " .. s .. " is not closed", 0) end
    local tag = string.match(string.sub(tpl, e + 1, cs - 1), "^%s*(.-)%s*$")
    local sigil, name = string.match(tag, "^([#%^/>!&]?)%s*(.-)$")
    if triple == "{" then
      node[#node + 1] = { kind = "raw", name = tag }
    elseif sigil == "#" or sigil == "^" then
      local child = { kind = sigil, name = name, parent = node }
      node[#node + 1] = child
      stack[#stack + 1] = child
      node = child
    elseif sigil == "/" then
      local open = table.remove(stack)
      if not open or open.name ~= name then error("html: {{/" .. name .. "}} closes nothing", 0) end
      node = open.parent
    elseif sigil == ">" then
      node[#node + 1] = { kind = ">", name = name }
    elseif sigil == "&" then
      node[#node + 1] = { kind = "raw", name = name }
    elseif sigil ~= "!" then
      node[#node + 1] = { kind = "var", name = name }
    end
    at = ce + 1
  end
  if #stack > 0 then error("html: {{#" .. stack[#stack].name .. "}} is not closed", 0) end
  return root
end

local walk
walk = function(nodes, stack, partials, out)
  for _, n in ipairs(nodes) do
    if type(n) == "string" then
      out[#out + 1] = n
    elseif n.kind == "var" then
      out[#out + 1] = html.escape(lookup(stack, n.name))
    elseif n.kind == "raw" then
      local v = lookup(stack, n.name)
      out[#out + 1] = v == nil and "" or tostring(v)
    elseif n.kind == ">" then
      local p = partials and partials[n.name]
      if p then walk(parse(p), stack, partials, out) end
    elseif n.kind == "^" then
      if falsy(lookup(stack, n.name)) then walk(n, stack, partials, out) end
    else
      local v = lookup(stack, n.name)
      if is_list(v) then
        for _, item in ipairs(v) do
          stack[#stack + 1] = item
          walk(n, stack, partials, out)
          stack[#stack] = nil
        end
      elseif not falsy(v) then
        stack[#stack + 1] = v
        walk(n, stack, partials, out)
        stack[#stack] = nil
      end
    end
  end
end

function html.render(tpl, view, partials)
  local out = {}
  walk(parse(tpl), { view or {} }, partials, out)
  return table.concat(out)
end


return html
