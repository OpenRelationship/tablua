-- A page and its actions, wired in one place (a .lui page compiles to this; Arock's feature file-kinds). A page is
-- a render of its data and the actions that change that data. An element names an action (post = "water"); the
-- action changes data and returns nothing, and the page is rendered again and merged into the person's (shroomi.js,
-- with idiomorph: focus, scroll and what they typed are kept). Nothing to target, no fragment to keep in step.
--
--   page.answer(def, req) -> HTML, or { status, body } / { redirect }
--     def(req, post, get, meta) -> render(result) -> nodes; post.<name> and get.<name> are its actions,
--     meta.title its title
--   an action runs, then the page runs again from its top and renders; it returns:
--                       nothing      the whole page again
--                       "#id"        that element alone, when a page is costly (a document whose body is it)
--                       { redirect = "path" }   go there
--                       any other value         given to render as `result` (a form's errors, say; {} when none)
--   page.el(req, post, get, name) -> el(line, tag, attrs, children): an element or component, with an action's
--     name (post = "water") made its address and marked to be merged, and vals = {table} sent as JSON
local ui = require("shroomi")

local page = {}

local function encode(s)
  return (string.gsub(tostring(s), "[^%w%-_%.~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

-- the address an element posts to for an action of the page that `req` asked for, relative to the app: the page
-- as the person sees it (its path and its query), and the action's name
function page.href(req, name)
  local keys, parts = {}, {}
  for k in pairs(req.query or {}) do if k ~= "do" then keys[#keys + 1] = tostring(k) end end
  table.sort(keys)
  for _, k in ipairs(keys) do parts[#parts + 1] = encode(k) .. "=" .. encode(req.query[k]) end
  parts[#parts + 1] = "do=" .. encode(name)
  return string.sub(req.path or "/", 2) .. "?" .. table.concat(parts, "&")
end

-- the node with this id, looked for through elements and lists
local function find(node, id)
  if type(node) ~= "table" then return nil end
  if node.attrs and node.attrs.id == id then return node end
  local kids = node.children or node
  for i = 1, node.n or ui.maxn(kids) do
    local hit = find(kids[i], id)
    if hit then return hit end
  end
  return nil
end
page.find = find

-- hx-vals as JSON: a flat table of strings, numbers and booleans
local function json_string(s)
  return '"' .. string.gsub(s, '[%c"\\]', function(c)
    if c == '"' or c == "\\" then return "\\" .. c end
    return string.format("\\u%04x", string.byte(c))
  end) .. '"'
end

local function vals(t, where)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local out = {}
  for i, k in ipairs(keys) do
    local v = t[k]
    if type(v) == "string" then v = json_string(v)
    elseif type(v) == "number" or type(v) == "boolean" then v = tostring(v)
    else error(where .. "vals holds strings, numbers and booleans; " .. k .. " is a " .. type(v), 0) end
    out[i] = json_string(k) .. ":" .. v
  end
  return "{" .. table.concat(out, ",") .. "}"
end

local VERBS = { post = true, get = true }

function page.el(req, post, get, name, lines)
  local actions = { post = post, get = get }
  return function(line, tag, attrs, kids)
    local where = (name or "page") .. ":" .. line .. ": "
    -- the host's own look asked where each element is written (lui.load's lines); a person's page never has it
    if lines then attrs["data-line"] = tostring(line) end
    local make = ui[tag]
    if not make then error(where .. "<" .. tag .. "> is no element or component (ui.kit lists the kit)", 0) end
    for verb in pairs(VERBS) do
      local v = attrs[verb]
      if type(v) == "string" and string.match(v, "^[%a_][%w_]*$") then
        if type(actions[verb][v]) ~= "function" then
          error(where .. verb .. '="' .. v .. '" names no action: define function ' .. verb .. "." .. v .. "(req)", 0)
        end
        attrs[verb] = page.href(req, v)
        attrs["data-morph"] = true
      end
    end
    if type(attrs.vals) == "table" then attrs.vals = vals(attrs.vals, where) end
    attrs[""] = nil
    for i = 1, #kids do attrs[i] = kids[i] end
    return make(attrs)
  end
end

-- the document a part goes out as: its own styles in the head, the part alone in a body that names it
local function part(node, id, title)
  local doc = ui.page{ title = title, node }
  return (string.gsub(doc, "<body ", '<body data-part="' .. ui.escape(id) .. '" ', 1))
end

function page.answer(def, req)
  local post, get, meta = {}, {}, {}
  local render = def(req, post, get, meta)
  local name = req.query and req.query["do"]
  local result
  if name then
    local fn = (req.method == "POST" and post or get)[name]
    if type(fn) ~= "function" then
      return { status = 404, body = "this page has no " .. string.lower(req.method or "get") .. " action " .. name }
    end
    result = fn(req)
    if type(result) == "table" and result.redirect then return { redirect = result.redirect } end
    -- the page again from its top, so what it read before the action is read again after it
    meta = {}
    render = def(req, {}, {}, meta)
  end
  local only = type(result) == "string" and string.match(result, "^#([%w_%-:%.]+)$")
  local nodes = render(not only and result ~= nil and result or {})
  if only then
    local node = find(nodes, only)
    if not node then error("the action " .. name .. " returned #" .. only .. ", and the page has no element with that id", 0) end
    return part(node, only, meta.title)
  end
  return ui.page{ title = meta.title, dark = meta.dark, nodes }
end

return page
