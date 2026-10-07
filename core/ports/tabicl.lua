-- TabICL behind TabPFN's port shape, so learn.lua ranks moves with it as it would with TabPFN. Where it runs is the
-- host's: its own TabICL in its binary (host.tabicl, Moonsplice's Candle build reached through mlua: the owner's
-- choice, 2026-10-06, TabICL runs locally), or a TabICL server (POST <url>/predict, as tablua-local's
-- modal/tabular.py serves it). Either takes the same body and gives { probas }. TabICL learns in context, so a fit is
-- kept here, costs no call, and goes with every prediction; the server keeps nothing between calls. It costs no
-- TabPFN tokens (estimate is 0).
--
--   local tab = require("ports.tabicl").new(host)        host.tabicl(body) -> { probas, ms? }, the host's own model
--   local tab = require("ports.tabicl").new(host, { url = "https://...", key = k, timeout? })   a server
--   body = { train = { columns, rows }, labels, categorical = { 0-based }, test = { columns, rows } }
--   learn.new{ tabpfn = tab, tablua = t }
--   tab:fit(train, labels, { categorical = { 0-based indices } }) -> id
--   tab:predict(id, test) -> { { p0, p1 }, ... }, record
--
-- key is sent as a Bearer token (a Modal proxy token as "<key>.<secret>"); the record never holds it.
local call = require("ports.call")

local M = {}
local T = {}
T.__index = T

function M.new(host, opts)
  assert(host, "tabicl needs a host")
  if not (opts and opts.url) then
    assert(type(host.tabicl) == "function", "tabicl needs the host's own TabICL (host.tabicl) or a server's url")
    return setmetatable({ host = host, fits = {}, n = 0 }, T)
  end
  assert(host.fetch, "tabicl needs a host with fetch for a server")
  assert(opts.key, "tabicl needs a key")
  return setmetatable({ host = host, url = opts.url:gsub("/+$", "") .. "/predict", key = opts.key,
    timeout = opts.timeout or 120, fits = {}, n = 0 }, T)
end

function T:estimate(_) return 0 end

function T:fit(train, labels, opts)
  assert(#labels == #train.rows, ("tabicl fit: %d labels for %d rows"):format(#labels, #train.rows))
  self.n = self.n + 1
  local id = "tabicl:" .. self.n
  self.fits[id] = { train = { columns = train.columns, rows = train.rows }, labels = labels,
    categorical = opts and opts.categorical or {} }
  return id
end

function T:predict(id, test)
  local f = assert(self.fits[id], "tabicl: no fit " .. tostring(id))
  local req = { train = f.train, labels = f.labels, categorical = f.categorical,
    test = { columns = test.columns, rows = test.rows } }
  local body, record
  if self.url then
    body, record = call.post(self.host, "tabicl", self.url, self.key, req, self.timeout)
  else
    local t0 = self.host.now and self.host.now()
    body = self.host.tabicl(req)
    record = { service = "tabicl-local", seconds = t0 and self.host.now() - t0 }
  end
  local probas = body and body.probas
  assert(type(probas) == "table" and #probas == #test.rows,
    ("tabicl gave %s answers for %d rows"):format(type(probas) == "table" and #probas or "no", #test.rows))
  record.ms = body and body.ms
  return probas, record
end

return M
