-- The person's rocks and their conversations kept on arock.ai, the same on every device (owner, 2026-10-04: the same
-- rocks on the Mac and the iPhone, synced). This port speaks the service's /v1/rocks (app/worker/src/rocks.ts) with
-- the app's session, as ports.writs does; what to send and what to keep is the caller's (desktop.ui.rocksync).
--
--   local p = require("ports.rocks").new(host, { key = session, base? })
--   p:list() -> { { id, name, pinned, look, computer, updated_at } }
--   p:keep(rock) -> true                  rock = { id, name, pinned?, look?, computer? }, kept whole
--   p:send(id, messages) -> n             messages = { { uid, who, text, kind?, detail? } } (up to 200): appended in
--                                         order, a uid kept already passed over; n: how many were new
--   p:read(id, after) -> messages, next   what came after `after` (0: from the start), oldest first, a page at a time
--
-- A refusal raises { message, status, code } in the service's own words; the session is only ever in a header.
local json = require("ports.json")

local M = {}
local P = {}
P.__index = P

M.base = "https://arock.ai"
M.BATCH = 200

local refusal = { __tostring = function(e) return e.message end }
local function refuse(message, status, code) error(setmetatable({ message = message, status = status, code = code }, refusal), 0) end

function M.new(host, opts)
  assert(host and host.fetch, "rocks needs a host with fetch")
  assert(opts and opts.key, "rocks needs the app's session")
  return setmetatable({ host = host, key = opts.key, base = opts.base or M.base }, P)
end

local function asked(self, req)
  req.headers = { Authorization = "Bearer " .. self.key, ["Content-Type"] = req.body and "application/json" or nil }
  req.timeout = req.timeout or 20
  local ok, res = pcall(self.host.fetch, req)
  if not ok then refuse("Arock's service could not be reached: " .. tostring(res)) end
  local okj, body = pcall(json.decode, res.body or "")
  body = okj and type(body) == "table" and body or {}
  if res.status == 200 then return body end
  local e = type(body.error) == "table" and body.error or {}
  refuse(e.message or ("Arock's service answered " .. tostring(res.status)), res.status, e.code)
end

local function rock_id(id)
  id = tostring(id)
  if #id > 64 or not id:match("^[a-z0-9][a-z0-9%-]*$") then refuse("not a rock's name: " .. id) end
  return id
end

function P:list() return asked(self, { method = "GET", url = self.base .. "/v1/rocks" }).rocks or {} end

function P:keep(rock)
  local b = { name = tostring(rock.name), pinned = rock.pinned == true, look = tostring(rock.look or "") }
  if rock.computer then b.computer = rock.computer end
  asked(self, { method = "PUT", url = self.base .. "/v1/rocks/" .. rock_id(rock.id), body = json.encode(b) })
  return true
end

function P:send(id, messages)
  assert(#messages <= M.BATCH, "send up to " .. M.BATCH .. " messages at a time")
  local out = {}
  for i, m in ipairs(messages) do
    out[i] = { uid = m.uid, who = m.who, text = m.text, kind = m.kind or "text", detail = m.detail or "" }
  end
  local url = self.base .. "/v1/rocks/" .. rock_id(id) .. "/messages"
  return asked(self, { method = "POST", url = url, body = json.encode({ messages = out }) }).kept or 0
end

function P:read(id, after)
  after = tonumber(after) or 0
  local got = asked(self, { method = "GET", url = self.base .. "/v1/rocks/" .. rock_id(id) .. "/messages?after=" .. after })
  return got.messages or {}, tonumber(got.next) or after
end

return M
