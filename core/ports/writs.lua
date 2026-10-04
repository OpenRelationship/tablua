-- The person's writs kept on arock.ai as well as on the Mac (Arock feature notes; owner, 2026-10-03: "writs can
-- leave the mac, they are stored for the user on the server too"). The service keeps every version, never changed
-- (app/worker/src/writs.ts); this port speaks its /v1/writs with the app's session, as ports.arock does.
--
--   local p = require("ports.writs").new(host, { key = session, base? })
--   p:keep(note, version, text, folder?) -> true     one version kept (the same version again with the same words
--                                                    is fine; with other words the service refuses, 409)
--   p:newest() -> { { note, version, folder, text, at } }   the newest version of each writ
--   p:versions(note) -> { { version, folder, text, at } }   every version of one, oldest first
--   writs.sync(p, list, sent) -> n, err?             list = { { id, folder, versions = { text, ... } } } (oldest
--                                                    first); sent = { [id] = the highest version kept there }, moved
--                                                    on as each is kept, so the caller keeps it and the next sync
--                                                    sends only what is new; n: how many were kept now
--
-- A refusal raises { message, status, code } in the service's own words; the session is only ever in a header.
local json = require("ports.json")

local M = {}
local P = {}
P.__index = P

M.base = "https://arock.ai"

local refusal = { __tostring = function(e) return e.message end }

function M.new(host, opts)
  assert(host and host.fetch, "writs needs a host with fetch")
  assert(opts and opts.key, "writs needs the app's session")
  return setmetatable({ host = host, key = opts.key, base = opts.base or M.base }, P)
end

local function asked(self, req)
  req.headers = { Authorization = "Bearer " .. self.key, ["Content-Type"] = req.body and "application/json" or nil }
  req.timeout = req.timeout or 20
  local ok, res = pcall(self.host.fetch, req)
  if not ok then
    error(setmetatable({ message = "Arock's service could not be reached: " .. tostring(res) }, refusal), 0)
  end
  local okj, body = pcall(json.decode, res.body or "")
  body = okj and type(body) == "table" and body or {}
  if res.status == 200 then return body end
  local e = type(body.error) == "table" and body.error or {}
  error(setmetatable({ message = e.message or ("Arock's service answered " .. tostring(res.status)),
    status = res.status, code = e.code }, refusal), 0)
end

local function note_name(note)
  note = tostring(note)
  if not note:match("^[a-z][a-z0-9%-]*$") or #note > 64 then
    error(setmetatable({ message = "not a writ's name: " .. note }, refusal), 0)
  end
  return note
end

function P:keep(note, version, text, folder)
  asked(self, { method = "PUT", url = self.base .. "/v1/writs/" .. note_name(note),
    body = json.encode({ version = version, text = tostring(text), folder = tostring(folder or "") }) })
  return true
end

function P:newest() return asked(self, { method = "GET", url = self.base .. "/v1/writs" }).writs or {} end

function P:versions(note)
  return asked(self, { method = "GET", url = self.base .. "/v1/writs/" .. note_name(note) .. "/versions" }).versions or {}
end

function M.sync(p, list, sent)
  local n = 0
  for _, w in ipairs(list) do
    for v = (sent[w.id] or 0) + 1, #w.versions do
      local ok, err = pcall(p.keep, p, w.id, v, w.versions[v], w.folder)
      if not ok then return n, err end
      sent[w.id] = v
      n = n + 1
    end
  end
  return n
end

return M
