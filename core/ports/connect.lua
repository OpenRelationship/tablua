-- Other people's apps, through connectory (submodules/connectory, PROJECT.md §17): a directory of 853 services
-- and, for the ones whose makers describe their API, every call it accepts as data. This port finds a service,
-- shows the calls it has, and makes one, signed with the person's own credential for that service. It never
-- holds a credential: the host's `secret(name)` reads it when a call is signed (the desktop keeps them in the
-- keychain), and a call that has none, or one the service refuses, comes back saying what the person must give
-- and where they get it, so the agent can ask them then and there.
--
--   local c = connect.new(host, { read = fn(path) -> text | nil, secret = fn(name) -> text | nil })
--     host = { fetch, now? } as for every port; read(path) reads a file of connectory's, relative to its root
--   c:find(words, n?)               -> { { service, name, categories, operations, docs } }, best first
--   c:operations(service, words?, n?) -> { { op, name, about, args = { "owner*", "repo*", "title*", "body" } } }
--                                      (* needed), best first; or nil, why
--   c:method(op)                    -> "GET", "POST" ... or nil (no such call)
--   c:needs(service)                -> { service, name, docs, fields = { { name, label, secret } }, missing = { name } }
--   c:call(op, args)                -> value, record   or nil, err
--                                      err = { code, message, needs? }: needs when the credential is missing or
--                                      refused (code "denied"); record = { service, op, method, status, seconds }
--   c:check(service)                -> true, record    or nil, err      (the directory's own test call, if any)
--
-- The record is what the log may keep: never the address (a query credential rides in it) nor any header.
local json = require("ports.json")
local port_http = require("connectory.lua.port_http")

local M = {}
local C = {}
C.__index = C

-- a pack is data: `return { ... }`, loaded with no globals so it can do nothing else
local function load_data(text, name)
  local f, why
  if setfenv then
    f, why = loadstring(text, name)
    if f then setfenv(f, {}) end
  else
    f, why = load(text, name, "t", {})
  end
  if not f then return nil, why end
  local ok, v = pcall(f)
  if not ok or type(v) ~= "table" then return nil, "not a pack" end
  return v
end

local function words(s)
  local out = {}
  for w in tostring(s or ""):lower():gmatch("[%w]+") do out[#out + 1] = w end
  return out
end

-- how many of the asked words a text holds, each counted once, a whole word (one or many) worth more than part of one
local function score(asked, text)
  local t, n = " " .. table.concat(words(text), " ") .. " ", 0
  for _, w in ipairs(asked) do
    local one = w:match("^(.-)s$") or w   -- "issues" and "issue" are the same word
    if t:find(" " .. one .. " ", 1, true) or t:find(" " .. one .. "s ", 1, true) then n = n + 2
    elseif #one > 2 and t:find(one, 1, true) then n = n + 1 end
  end
  return n
end

-- the asked words worth matching: "an" and "to" match too much
local function asked_words(s)
  local out = {}
  for _, w in ipairs(words(s)) do if #w > 2 then out[#out + 1] = w end end
  return out
end

-- texts_of(x) gives the texts to match from the most telling (a name) to the least (a description), each worth
-- less than the one before
local function best(list, asked, texts_of, n)
  local scored = {}
  for i, x in ipairs(list) do
    local s, texts = 0, texts_of(x)
    if #asked == 0 then s = 1 else
      for k, t in ipairs(texts) do s = s + score(asked, t) * (#texts - k + 1) end
    end
    -- of two that fit as well, the one with fewer other words in its name
    if s > 0 then scored[#scored + 1] = { x = x, s = s, i = i, len = #texts[1] } end
  end
  table.sort(scored, function(a, b)
    if a.s ~= b.s then return a.s > b.s end
    if a.len ~= b.len then return a.len < b.len end
    return a.i < b.i
  end)
  local out = {}
  for i = 1, math.min(n, #scored) do out[i] = scored[i].x end
  return out
end

function M.new(host, opts)
  assert(type(host) == "table" and type(host.fetch) == "function", "connect.new(host): host.fetch is required")
  assert(type(opts) == "table" and type(opts.read) == "function", "connect.new(host, { read }): read is required")
  return setmetatable({ host = host, read = opts.read, secret = opts.secret or function() return nil end,
    packs = {}, menus = {} }, C)
end

function C:directory()
  if not self.index then
    local text = self.read("index.json")
    if not text then error("connectory's index.json could not be read", 0) end
    self.index = json.decode(text).index
    self.by = {}
    for _, e in ipairs(self.index) do self.by[e.slug] = e end
  end
  return self.index, self.by
end

local function entry(self, service)
  local _, by = self:directory()
  return by[service]
end

local function service_of(op) return tostring(op or ""):match("^([^.]+)%.") end

function C:pack(service)
  if self.packs[service] == nil then
    local text = entry(self, service) and self.read("providers/" .. service .. "/" .. service .. ".lua")
    self.packs[service] = text and load_data(text, "=" .. service) or false
  end
  return self.packs[service] or nil
end

function C:find(asked, n)
  local list = self:directory()
  local found = best(list, asked_words(asked), function(e)
    return { e.name .. " " .. e.slug:gsub("-", " "), table.concat(e.categories or {}, " ") }
  end, n or 8)
  local out = {}
  for i, e in ipairs(found) do
    out[i] = { service = e.slug, name = e.name, categories = e.categories, operations = e.operations, docs = e.docs }
  end
  return out
end

function C:operations(service, asked, n)
  local e = entry(self, service)
  if not e then return nil, "no service called " .. tostring(service) .. " is in the directory" end
  if (e.operations or 0) == 0 then
    return nil, e.name .. " publishes no description of its API, so no call to it is known; its documentation: "
      .. tostring(e.docs)
  end
  if not self.menus[service] then
    local text = self.read("providers/" .. service .. "/index.json")
    if not text then return nil, e.name .. "'s calls could not be read" end
    self.menus[service] = json.decode(text).operations
  end
  local found = best(self.menus[service], asked_words(asked), function(o)
    return { o.name, (o.slug:gsub("[._]", " ")), o.description or "" }
  end, n or 10)
  local out = {}
  for i, o in ipairs(found) do
    local input, need, args = o.input or {}, {}, {}
    for _, r in ipairs(input.required or {}) do need[r] = true end
    for name in pairs(input.properties or {}) do args[#args + 1] = name .. (need[name] and "*" or "") end
    table.sort(args, function(a, b)
      local na, nb = a:sub(-1) == "*", b:sub(-1) == "*"
      if na ~= nb then return na end
      return a < b
    end)
    out[i] = { op = o.slug, name = o.name, about = (o.description or ""):sub(1, 240), args = args }
  end
  return out
end

function C:method(op)
  local pack = self:pack(service_of(op))
  local o = pack and pack.operations[op]
  return o and o.method or nil
end

-- "GITHUB_TOKEN" is GitHub's "token": the words of the service's own name are left off
local function label(name, service)
  local skip = {}
  for _, w in ipairs(words(service)) do skip[w] = true end
  local left = {}
  for _, w in ipairs(words(name:gsub("_", " "))) do if not skip[w] then left[#left + 1] = w end end
  return #left > 0 and table.concat(left, " ") or name:lower()
end

function C:needs(service)
  local e = entry(self, service)
  if not e then return nil end
  local fields, seen = {}, {}
  local function add(name, secret)
    if name and not seen[name] then
      seen[name] = true
      fields[#fields + 1] = { name = name, label = label(name, service), secret = secret }
    end
  end
  local pack = self:pack(service)
  if pack then
    local auth = pack.auth or {}
    add(auth.user_env, false)
    add(auth.pass_env, true)
    add(auth.env, true)
    local config = {}
    for _, env in pairs(pack.config or {}) do config[#config + 1] = env end
    table.sort(config)
    for _, env in ipairs(config) do add(env, false) end
  else
    -- described only by the directory: an address part by its name, anything else a credential
    for _, env in ipairs(e.env or {}) do
      add(env, not env:find("_DOMAIN$") and not env:find("_SUBDOMAIN$") and not env:find("_HOST$")
        and not env:find("_URL$") and not env:find("_REGION$") and not env:find("_INSTANCE$"))
    end
  end
  local missing = {}
  for _, f in ipairs(fields) do
    local v = self.secret(f.name)
    if v == nil or v == "" then missing[#missing + 1] = f.name end
  end
  return { service = service, name = e.name, docs = e.docs, fields = fields, missing = missing }
end

local function form_encode(t)
  local parts = {}
  for k, v in pairs(t) do
    local value = type(v) == "table" and json.encode(v) or tostring(v)
    parts[#parts + 1] = tostring(k) .. "=" .. value:gsub("[^%w%-%._~]", function(c)
      return ("%%%02X"):format(c:byte())
    end)
  end
  table.sort(parts)
  return table.concat(parts, "&")
end

-- connectory's request shape onto the host's fetch
local function request(self, status_out)
  return function(r)
    local headers, body = {}, nil
    for k, v in pairs(r.headers or {}) do headers[k] = v end
    if r.body then
      if r.body_format == "form" then
        headers["content-type"], body = "application/x-www-form-urlencoded", form_encode(r.body)
      else
        headers["content-type"], body = "application/json", json.encode(r.body)
      end
    end
    local ok, res = pcall(self.host.fetch, { method = r.method, url = r.url, headers = headers, body = body,
      timeout = 30 })
    if not ok then return nil, tostring(res) end
    status_out.status = res.status
    local decoded = res.body ~= nil and res.body ~= "" and select(2, pcall(json.decode, res.body)) or nil
    return res.status, type(decoded) == "table" and decoded or { text = res.body }
  end
end

function C:call(op, args)
  local service = service_of(op)
  local pack = service and self:pack(service)
  if not pack then return nil, { code = "not_found", message = "no service is known for " .. tostring(op) } end
  if not pack.operations[op] then
    return nil, { code = "not_found", message = pack.name .. " has no call named " .. tostring(op) }
  end
  local now = self.host.now or os.time
  local seen, t0 = {}, now()
  local p = port_http { catalog = pack, request = request(self, seen), getenv = self.secret }
  local value, err = p.execute(op, args or {})
  local record = { service = service, op = op, method = pack.operations[op].method, status = seen.status,
    seconds = now() - t0 }
  if value == nil then
    local out = { code = err.code, message = err.message }
    if err.code == "denied" then out.needs = self:needs(service) end
    return nil, out, record
  end
  return value, record
end

function C:check(service)
  local e = entry(self, service)
  local pack = e and self:pack(service)
  if not (e and e.verify and pack) then return nil, { code = "not_found", message = "no test call is known" } end
  local op = { method = e.verify.method, url = pack.base .. e.verify.path }
  local probe = { provider = pack.provider, name = pack.name, auth = pack.auth, config = pack.config,
    headers = pack.headers, operations = { [service .. ".verify"] = op } }
  local seen = {}
  local value, err = port_http { catalog = probe, request = request(self, seen), getenv = self.secret }
    .execute(service .. ".verify", {})
  local record = { service = service, op = "verify", method = op.method, status = seen.status }
  if value == nil then
    local out = { code = err.code, message = err.message }
    if err.code == "denied" then out.needs = self:needs(service) end
    return nil, out, record
  end
  return true, record
end

return M
