-- The Arock service port: the one supplier the desktop app talks to (PROJECT.md §12, app/worker). The
-- service holds the provider keys and speaks Mercury's and Jev's own APIs at its /v1 paths, so this port is
-- theirs pointed at it, with the app's session in place of a provider key:
--
--   local p = require("ports.arock").new(host, { key = session, base?, person? })   person: on a node (below)
--   p:fill{...}  p:edit{...}  p:chat{...}  -> text, record      as ports.mercury
--   p:decide(state, questions)             -> answers, record   as ports.jev
--   p:account() -> { email, name, subscribed, subscribe_url, manage_url }
--   p:run(computer, line) -> { code, out, err, cwd }   a command on one of the person's computers (features/screen)
--   p:run_all(computer, lines) -> { { code, out, err, cwd }, ... }   several in one trip, in order
--   p:write(computer, path, text) -> true | false, why   the person writes there (a writ in writs/, or what one made)
--   p:grant(computer, tool, reach, value) -> true | false, why   the person's yes to one request (NET, MAIL, ACCOUNT)
--   p:revoke(computer, tool, reach, value) -> true | false, why  taking it back
--   p:agree(computer, feature) -> true | false, why      agreeing to a feature as it stands (features/x.feature)
--   p:voice() p:see() p:search() p:tabpfn()  ports.chat (the spoken voice), ports.see, ports.search and ports.tabpfn
--                                          pointed at the service's /v1/voice, /v1/see, /v1/search (and /v1/extract) and /v1/tabpfn,
--                                          their refusals in the service's words too
--
-- The service picks each model, so no provider key and no model choice is on the Mac. TabPFN's uploads go to the
-- signed URLs its prepare calls return, which carry no key.
--
-- A refusal raises { message, status, code } with the service's own plain words, meant to be said to the
-- person: 401 "Sign in to Arock first.", 402 "Arock needs a subscription, $20 a month. Subscribe at ...".
-- The session travels only in the request's header and never enters a record.
local mercury = require("ports.mercury")
local jev = require("ports.jev")
local chat = require("ports.chat")
local see = require("ports.see")
local search = require("ports.search")
local tabpfn = require("ports.tabpfn")
local json = require("ports.json")

local M = {}
local P = {}
P.__index = P

M.base = "https://arock.ai"

local refusal = { __tostring = function(e) return e.message end }

-- A call.post error in the service's words: its own message, without the port's "<service> answered N: ".
local function plain(err)
  if type(err) ~= "table" or not err.record then error(err, 0) end
  local text = tostring(err.message)
  local said = text:match("^%S+ answered %d+: (.*)$")
    or ("Arock's service could not be reached: " .. (text:match("^%S+ unreachable: (.*)$") or text))
  error(setmetatable({ message = said, status = err.record.status, record = err.record }, refusal), 0)
end

-- Every call returns two values, the answer and its record, which names this port.
local function guarded(fn)
  return function(...)
    local ok, answer, record = pcall(fn, ...)
    if not ok then plain(answer) end
    if type(record) == "table" then record.service = "arock" end
    return answer, record
  end
end

-- On a node the key is the node's own token and `person` the account a computer is theirs (PROJECT.md §19): every
-- request to the service names that person, so the service checks and bills them. Requests elsewhere (TabPFN's
-- signed upload URLs) carry no person.
local function speaking_for(host, base, person)
  if not person then return host end
  local fetch = host.fetch
  return setmetatable({ fetch = function(req)
    if string.sub(req.url or "", 1, #base) == base then
      local headers = {}
      for k, v in pairs(req.headers or {}) do headers[k] = v end
      headers["X-Arock-Person"] = person
      local copy = {}
      for k, v in pairs(req) do copy[k] = v end
      copy.headers = headers
      req = copy
    end
    return fetch(req)
  end }, { __index = host })
end

function M.new(host, opts)
  assert(host and host.fetch, "arock needs a host with fetch")
  assert(opts and opts.key, "arock needs the app's session")
  local base = opts.base or M.base
  host = speaking_for(host, base, opts.person)
  return setmetatable({
    host = host, key = opts.key, base = base,
    mercury = mercury.new(host, { key = opts.key, base = base .. "/v1" }),
    jev = jev.new(host, { key = opts.key, url = base .. "/v1/decisions" }),
  }, P)
end

P.fill = guarded(function(self, req) return self.mercury:fill(req) end)
P.edit = guarded(function(self, req) return self.mercury:edit(req) end)
P.chat = guarded(function(self, req) return self.mercury:chat(req) end)
P.decide = guarded(function(self, state, questions) return self.jev:decide(state, questions) end)

-- Another port, its every method guarded as the service's own.
local function veiled(port)
  return setmetatable({}, { __index = function(t, k)
    local v = port[k]
    if type(v) ~= "function" then return v end
    local f = guarded(function(_, ...) return v(port, ...) end)
    t[k] = f
    return f
  end })
end

M.voice_model = "deepseek/deepseek-v4.1-flash"   -- what the service speaks with; sent only because ports.chat needs one

function P:voice()
  return veiled(chat.new(self.host, { key = self.key, model = M.voice_model, url = self.base .. "/v1/voice/chat/completions",
    thinking = false, sort = "latency" }))
end
function P:see() return veiled(see.new(self.host, { key = self.key, url = self.base .. "/v1/see/chat/completions" })) end
function P:search()
  return veiled(search.new(self.host, { key = self.key, url = self.base .. "/v1/search",
    extract_url = self.base .. "/v1/extract", bearer = true }))
end
function P:tabpfn() return veiled(tabpfn.new(self.host, { key = self.key, url = self.base .. "/v1" })) end

-- One request with the session; its JSON answer, or a refusal in the service's (or the node's) own words.
local function asked(self, req)
  req.headers = { Authorization = "Bearer " .. self.key, ["Content-Type"] = req.body and "application/json" or nil }
  local ok, res = pcall(self.host.fetch, req)
  if not ok then plain({ message = "arock unreachable: " .. tostring(res), record = {} }) end
  local okj, body = pcall(json.decode, res.body or "")
  body = okj and type(body) == "table" and body or {}
  if res.status == 200 then return body end
  local e = type(body.error) == "table" and body.error or {}
  local said = e.message or (not okj and res.body ~= "" and tostring(res.body):sub(1, 300))
  error(setmetatable({ message = said or ("Arock's service answered " .. tostring(res.status)),
    status = res.status, code = e.code }, refusal), 0)
end

function P:account() return asked(self, { method = "GET", url = self.base .. "/v1/account", timeout = 15 }) end

-- One command on one of the person's computers (features/screen, PROJECT.md §14), through the front door
-- to their node, as the computer page's terminal runs one: -> { code, out, err, cwd }. The node says no to a
-- computer of someone else's.
function P:run(computer, line) return self:run_all(computer, { line })[1] end

local function named(computer)
  computer = tostring(computer)
  if #computer > 64 or not computer:match("^[a-z0-9][a-z0-9%-]*$") then
    error(setmetatable({ message = "not a computer's name: " .. computer }, refusal), 0)
  end
  return computer
end

-- Several command lines in one trip, run in order: -> { { code, out, err, cwd }, ... }, one for each.
function P:run_all(computer, lines)
  computer = named(computer)
  local list = {}
  for i, l in ipairs(lines) do list[i] = tostring(l) end
  local body = asked(self, { method = "POST", url = self.base .. "/computers/" .. computer .. "/run", timeout = 300,
    body = json.encode({ lines = list }) })
  return body.results or {}
end

-- What the person says on their computer (Arock feature notes: their yes to a writ's change): each its own route
-- on the node, as the person and never as an agent. -> true, or false and the node's why.
local function said(self, computer, verb, body)
  local r = asked(self, { method = "POST", url = self.base .. "/computers/" .. named(computer) .. "/" .. verb,
    timeout = 60, body = json.encode(body) })
  if r.ok == true then return true end
  return false, tostring(r.why or "the node said no")
end

function P:write(computer, path, text) return said(self, computer, "write", { path = path, text = text }) end
function P:grant(computer, tool, reach, value)
  return said(self, computer, "grant", { tool = tool, reach = reach, value = value })
end
function P:revoke(computer, tool, reach, value)
  return said(self, computer, "revoke", { tool = tool, reach = reach, value = value })
end
function P:agree(computer, feature) return said(self, computer, "agree", { feature = feature }) end

return M
