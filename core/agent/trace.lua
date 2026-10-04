-- Arock's trace (PROJECT.md §11): every turn of the conversation and, inside it, every call to a model or to the
-- Mac's hands, with what was asked in full, what came back, how long it took, what it cost and any failure, as Robot
-- rows in an Arock Core store (append-only), one file a day. It is for auditing: `just tool trace` reads it.
--
--   local t = trace.new{ open = fn(day) -> store, today = fn() -> "2026-09-29", now = fn() -> seconds }
--   t:turn(heard) -> task        a new turn, from what the person was heard saying
--   t:said(text)  t:row(keyword, args)
--   t:wrap(name, port, plain?) -> port   the same port, each call recorded ("Port Call", then "Port Answer" or
--                                "Port Failed"); plain for a table of functions called without self (the hands)
--   trace.file(day) -> "trace-<day>.sqlite"   trace.stale(today, keep, span) -> the day files to drop
--   trace.report(events, n?) -> text   the last n turns (all when n is nil), a few lines each
--
-- A call that gives nothing back is not recorded (the hands' take, polled while a batch runs).
-- Rows: Heard <text>; Said <text>; Port Call <port.method> <request as JSON>; Port Answer <port.method> <seconds>
-- <cost> <short answer> <answer as JSON>; Port Failed <port.method> <seconds> <error>; and any the voice loop adds.
local json = require("ports.json")

local M = {}
local T = {}
T.__index = T

M.MAX = 65536    -- bytes of one argument kept; past this it is cut, and says how much was left out
M.KEEP = 30      -- days of trace kept
M.SHORT = 100    -- characters of an answer in the report

local unpack = table.unpack or unpack

function M.new(opts)
  local t = setmetatable({ open = opts.open, today = opts.today or function() return os.date("%Y-%m-%d") end,
    now = opts.now or os.time, task = "between-turns", turns = 0 }, T)
  return t
end

-- The day's store, opened again when the day changes; the turn count read back from it.
function T:store()
  local day = self.today()
  if day ~= self.day then
    self.day, self.db, self.turns = day, self.open(day), 0
    for _, e in ipairs(self.db:events()) do if e.keyword == "Heard" then self.turns = self.turns + 1 end end
  end
  return self.db
end

local function clip(s)
  s = tostring(s)
  if #s <= M.MAX then return s end
  return s:sub(1, M.MAX) .. ("\n… [%d bytes left out]"):format(#s - M.MAX)
end

local function plain(v, depth)
  if type(v) ~= "table" or depth > 4 then return v end
  local out = {}
  for k, x in pairs(v) do if type(x) ~= "function" then out[k] = plain(x, depth + 1) end end
  return out
end
local function encode(v)
  if type(v) == "string" then return v end
  local ok, s = pcall(json.encode, plain(v, 0))
  return ok and s or tostring(v)
end

function T:row(keyword, args)
  local db = self:store()
  local out = {}
  for i, a in ipairs(args) do out[i] = clip(a) end
  pcall(db.append, db, self.task, keyword, out, "host")   -- a trace that cannot be written never stops the rock
end

function T:turn(heard)
  self:store()
  self.turns = self.turns + 1
  self.task = "turn-" .. self.turns
  self:row("Heard", { heard or "" })
  return self.task
end

function T:said(text) self:row("Said", { text or "" }) end

-- What an answer comes to in a line: Jev's choice, a text's start, or a table's JSON start.
local function short(v)
  if type(v) == "table" then
    local next_ = v.next
    if type(next_) == "table" and next_.choice then return tostring(next_.choice) end
    v = encode(v)
  end
  v = tostring(v):gsub("%s+", " ")
  return #v > M.SHORT and (v:sub(1, M.SHORT) .. "…") or v
end

function T:wrap(name, port, plain)
  if not port then return nil end
  local t = self
  return setmetatable({}, { __index = function(proxy, k)
    local v = port[k]
    if type(v) ~= "function" then return v end
    local label = name .. "." .. k
    local f = function(...)
      local args = { ... }
      local n = select("#", ...)
      local call = plain and { ... } or { select(2, ...) }
      local t0 = t.now()
      local res = { pcall(v, plain and args[1] or port, unpack(args, 2, n)) }
      local secs = ("%.3f"):format(t.now() - t0)
      -- a call that gives nothing back (a poll for a batch still running) is not worth a row
      if res[1] and res[2] == nil then return end
      t:row("Port Call", { label, encode(call) })
      if not res[1] then
        t:row("Port Failed", { label, secs, tostring(res[2]) })
        error(res[2], 0)
      end
      local rec = type(res[3]) == "table" and res[3] or {}
      t:row("Port Answer", { label, secs, rec.cost and tostring(rec.cost) or "", short(res[2]), encode(res[2]) })
      return unpack(res, 2, #res)
    end
    proxy[k] = f
    return f
  end })
end

function M.file(day) return "trace-" .. day .. ".sqlite" end

-- The day files from keep+1 to keep+span days before today, to drop (a missing one is no matter).
function M.stale(today, keep, span)
  local y, m, d = today:match("^(%d+)-(%d+)-(%d+)$")
  local base = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
  local out = {}
  for back = (keep or M.KEEP) + 1, (keep or M.KEEP) + (span or 400) do
    out[#out + 1] = M.file(os.date("%Y-%m-%d", base - back * 86400))
  end
  return out
end

-- The last n turns as text: what was heard, each call with its seconds and short answer or failure, what was said.
function M.report(events, n)
  local turns, order = {}, {}
  for _, e in ipairs(events) do
    if not turns[e.task] then turns[e.task] = {}; order[#order + 1] = e.task end
    local lines, a = turns[e.task], e.args
    if e.keyword == "Heard" then lines[#lines + 1] = "heard: " .. (a[1] or "")
    elseif e.keyword == "Said" then lines[#lines + 1] = "said: " .. (a[1] or "")
    elseif e.keyword == "Port Answer" then lines[#lines + 1] = ("  %s %ss -> %s"):format(a[1], a[2], a[4] or "")
    elseif e.keyword == "Port Failed" then lines[#lines + 1] = ("  %s FAILED %ss: %s"):format(a[1], a[2], a[3] or "")
    elseif e.keyword ~= "Port Call" then lines[#lines + 1] = ("  %s: %s"):format(e.keyword, table.concat(a, " | "))
    end
  end
  local first = n and math.max(1, #order - n + 1) or 1
  local out = {}
  for i = first, #order do
    out[#out + 1] = ("[%s]"):format(order[i])
    for _, l in ipairs(turns[order[i]]) do out[#out + 1] = l end
  end
  return table.concat(out, "\n")
end

return M
