-- One HTTP call through the host's fetch, shared by the Jev, Mercury and search ports.
--
-- The host supplies { fetch = fn(req) -> res, now = fn() -> seconds, sleep = fn(seconds) };
-- only fetch is required. req = { method, url, headers, body, timeout };
-- res = { status, body }. fetch may raise for a network failure or timeout.
--
-- A transient failure (network, 429, 5xx) is retried; any other status is
-- final, and so is a 429 that says a daily or plan limit is spent (retrying it
-- only waits: a protocol's steps took 20 s each against TabPFN's spent daily
-- limit, 2026-10-05). Its error carries spent = true. The record returned is what the log may keep: service, url,
-- status, tries and seconds, never the headers, so never the key.
local json = require("ports.json")

local M = {}

local function transient(status)
  return status == nil or status == 429 or status >= 500
end

-- The error message a service put in its body, if it put one there.
local function reason(body)
  local ok, v = pcall(json.decode, body or "")
  if ok and type(v) == "table" then
    local e = type(v.error) == "table" and (v.error.message or v.error.code) or v.error or v.detail
    if type(e) == "table" then
      -- a validation list echoes the whole request back; keep only its messages
      local msgs = {}
      for _, d in ipairs(e) do msgs[#msgs + 1] = type(d) == "table" and tostring(d.msg) or tostring(d) end
      e = #msgs > 0 and table.concat(msgs, "; ") or json.encode(e)
    end
    if e ~= nil then return tostring(e):sub(1, 300) end
  end
  return (body or ""):sub(1, 200)
end

-- whether a 429's body says a limit is spent until later (a daily or plan limit, a quota), not a moment's load
function M.spent(body)
  local r = reason(body):lower()
  return (r:find("limit reached", 1, true) or r:find("quota", 1, true) or r:find("usage limit", 1, true)
    or r:find("resets at", 1, true)) ~= nil
end

-- key is sent as a Bearer token, or in its own header when given as
-- { header = name, value = key }. With on_data, the body is heard a chunk at a time as it comes (the host's fetch
-- passes it on) and returned as it came, not decoded: a streamed reply.
function M.post(host, service, url, key, payload, timeout, on_data)
  local headers = { ["Content-Type"] = "application/json" }
  if type(key) == "table" then
    headers[key.header] = key.value
  else
    headers["Authorization"] = "Bearer " .. key
  end
  local req = { method = "POST", url = url, timeout = timeout or 30, headers = headers, body = json.encode(payload),
    on_data = on_data }
  local record = { service = service, url = url, tries = 0 }
  local t0 = host.now and host.now()
  local last
  -- a busy or briefly failing service (429, 5xx, no answer) is tried three times, a second and then three apart: a
  -- provider's run of 504s left Mercury unfilled twice and a build run stopped blocked on its own tool
  local waits = { 1, 3 }
  for try = 1, #waits + 1 do
    record.tries = try
    local ok, res = pcall(host.fetch, req)
    local status = ok and res.status or nil
    record.status = status
    if status == 200 then
      if t0 then record.seconds = host.now() - t0 end
      if on_data then return res.body, record end
      return json.decode(res.body), record
    end
    last = ok and (service .. " answered " .. status .. ": " .. reason(res.body))
      or (service .. " unreachable: " .. tostring(res))
    if status == 429 and M.spent(res.body) then record.spent = true break end
    if not transient(status) then break end
    if waits[try] and host.sleep then host.sleep(waits[try]) end
  end
  if t0 then record.seconds = host.now() - t0 end
  error(setmetatable({ message = last, record = record, spent = record.spent },
    { __tostring = function(e) return e.message end }), 0)
end

return M
