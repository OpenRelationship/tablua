-- Other people's apps for the studio's model (owner, 2026-10-07): one tool, connect, over connectory's port
-- (connectory/lua/connect.lua, its card lua/library.md). The model finds a service, lists its calls and makes one;
-- it never sees a credential and never asks for one. Like Grok Bot's connectors, a secret goes from the person to
-- the host's store through a field of its own, and a call that changes something waits for the person to approve it.
--
--   local tool = require("studio.connect").tool(s)      s: the session; s.o.connect = { port, ask, approval? }
--     port: connectory's connect.new(host, { read, secret }); secret is the host's, never the session's
--     ask(a) -> { how = text }: the host shows the person a = { kind = "connect" | "approve", service, name, op?,
--       method?, fields? = { { name, label, secret } }, docs?, why }, in a masked field (a GUI) or as a command for
--       the person to run (a terminal, or the agent driving this one); how is what the model and the driver are told
--     approval(service, op) -> "once" | "always" | "deny" | nil (not answered yet)
--   M.open(s) -> { a, ... }: what is still waiting on the person, for the hand-in and the run's result
--
-- Rows: each call to a service is tablua_connect (no address, header or value); each ask is tablua_ask.
local json = require("ports.json")

local M = {}

local function clip(s, n)
  s = tostring(s or "")
  return #s > n and (s:sub(1, n) .. "...") or s
end

local function record(s, service, op, rec, outcome)
  s.connect_i = (s.connect_i or 0) + 1
  rec = rec or {}
  s.t.db:exec("insert or replace into tablua_connect (todo, n, i, service, op, method, status, seconds, outcome) "
    .. "values (?, ?, ?, ?, ?, ?, ?, ?, ?)", { s.todo, s.n, s.connect_i, service, op or "", rec.method, rec.status,
      rec.seconds, outcome })
end

-- ask the person once per service (and op): the host shows it, the model and the driver are told how it is answered
local function ask(s, a)
  s.asks = s.asks or {}
  local key = a.kind .. "\0" .. a.service .. "\0" .. (a.op or "")
  local open = s.asks[key]
  if open then return open.how end
  local c = s.o.connect
  local ok, r = pcall(c.ask, a)
  local how = ok and type(r) == "table" and r.how or "the person has been asked"
  a.how = how
  s.asks[key] = a
  local fields = {}
  for _, f in ipairs(a.fields or {}) do fields[#fields + 1] = { name = f.name, label = f.label, secret = f.secret } end
  s.t.db:exec("insert or replace into tablua_ask (todo, n, kind, service, op, fields, docs, how) values "
    .. "(?, ?, ?, ?, ?, ?, ?, ?)", { s.todo, s.n, a.kind, a.service, a.op or "", json.encode(fields), a.docs, how })
  if s.o.log then s.o.log(("[ask] %s %s%s: %s"):format(a.kind, a.service, a.op and (" " .. a.op) or "", how)) end
  return how
end

local function settle(s, kind, service, op)
  if s.asks then s.asks[kind .. "\0" .. service .. "\0" .. (op or "")] = nil end
end

function M.open(s)
  local out = {}
  for _, a in pairs(s.asks or {}) do out[#out + 1] = a end
  table.sort(out, function(x, y) return (x.service .. (x.op or "")) < (y.service .. (y.op or "")) end)
  return out
end

local function found(list)
  local lines = {}
  for _, e in ipairs(list) do
    lines[#lines + 1] = ("%s (%s): %s; %d calls described%s"):format(e.service, e.name,
      table.concat(e.categories or {}, ", "), e.operations or 0, e.docs and (", docs " .. e.docs) or "")
  end
  return #lines > 0 and table.concat(lines, "\n") or "No service in the directory matches."
end

local function calls(list)
  local lines = {}
  for _, o in ipairs(list) do
    lines[#lines + 1] = ("%s: %s (%s)%s"):format(o.op, o.name, table.concat(o.args, ", "),
      o.about ~= "" and (" - " .. o.about) or "")
  end
  return table.concat(lines, "\n") .. "\nArguments marked * are needed."
end

local function result(text, verb, outcome) return { content = text, details = { verb = verb, outcome = outcome } } end

local function call(s, args)
  local c = s.o.connect
  local port, op = c.port, args.op
  if type(op) ~= "string" or op == "" then error("call needs op, as calls gives it (service.operation)", 0) end
  local service = op:match("^([^.]+)%.")
  local method = port:method(op)
  if not method then error(("no call is named %s; list them with action calls"):format(op), 0) end
  local _, by = port:directory()
  local name = by[service] and by[service].name or service
  -- a call that changes something waits for the person, the first time and every time they said "once"
  if not port:reads(op) then
    local answer = c.approval and c.approval(service, op) or nil
    if answer == "deny" then
      record(s, service, op, { method = method }, "denied")
      settle(s, "approve", service, op)
      return result(("The person declined %s. Do not try it again; find another way, or hand in and say so.")
        :format(op), "connect", "broken")
    elseif answer ~= "once" and answer ~= "always" then
      local how = ask(s, { kind = "approve", service = service, name = name, op = op, method = method,
        why = clip(args.why, 300) })
      record(s, service, op, { method = method }, "waiting")
      return result(("%s %s changes something in %s, so it waits for the person to approve it: %s. Carry on with "
        .. "other work and try it again later; if the piece cannot be finished without it, hand in and say what "
        .. "waits on them."):format(method, op, name, how), "connect", "neutral")
    end
    settle(s, "approve", service, op)
  end
  -- connectory answers value, record or nil, err, record
  local value, err, rec = port:call(op, args.args or {})
  if value ~= nil then rec = err end
  if value == nil then
    if err.needs then
      local fields = {}
      for _, f in ipairs(err.needs.fields or {}) do fields[#fields + 1] = f.label end
      local how = ask(s, { kind = "connect", service = service, name = name, fields = err.needs.fields,
        docs = err.needs.docs, why = clip(args.why, 300) })
      record(s, service, op, rec, "needs")
      return result(("%s is not connected (%s). The person has been asked to connect it: %s. You never see the "
        .. "credential, and you must not ask for it in the conversation. Carry on with other work and call again "
        .. "once they have; if the piece cannot be finished without it, hand in and say what waits on them.")
        :format(name, table.concat(fields, ", "), how), "connect", "neutral")
    end
    record(s, service, op, rec, "broken")
    error(("%s: %s"):format(err.code or "error", err.message or "the call failed"), 0)
  end
  settle(s, "connect", service)
  record(s, service, op, rec, "complete")
  return result(("%s answered %s:\n%s"):format(name, tostring(rec and rec.status or "ok"),
    clip(type(value) == "table" and json.encode(value) or tostring(value), 4000)), "connect", "complete")
end

function M.tool(s)
  return { name = "connect", description = "Reach another app or service through connectory's directory: find "
      .. "a service (action find, words), list its calls (action calls, service, words), or make one (action "
      .. "call, op, args, why). The person connects their own account; you never see or ask for a credential. "
      .. "A call that changes something waits for the person's approval.",
    parameters = { type = "object", required = { "action" }, properties = {
      action = { type = "string", enum = { "find", "calls", "call" } },
      words = { type = "string", description = "what you are looking for, in a few words" },
      service = { type = "string", description = "the service, as find gives it" },
      op = { type = "string", description = "the call, as calls gives it (service.operation)" },
      args = { type = "object", description = "the call's arguments, by the names calls gives" },
      why = { type = "string", description = "for the person: why the piece needs this call" } } },
    execute = function(args)
      local port = s.o.connect.port
      if args.action == "find" then
        return result(found(port:find(args.words or "", 8)), "connect", "complete")
      elseif args.action == "calls" then
        local list, why = port:operations(args.service, args.words, 10)
        if not list then error(why, 0) end
        return result(calls(list), "connect", "complete")
      elseif args.action == "call" then
        return call(s, args)
      end
      error("action is find, calls or call", 0)
    end }
end

return M
