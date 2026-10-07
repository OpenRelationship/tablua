-- TabICL behind TabPFN's port shape, so learn.lua ranks moves with it as it would with TabPFN: a host's TabICL
-- server (POST <url>/predict, as tablua-local's modal/tabular.py serves it). TabICL learns in context, so a fit is
-- kept here, costs no call, and goes with every prediction; the server keeps nothing between calls. It costs no
-- TabPFN tokens (estimate is 0).
--
--   local tab = require("ports.tabicl").new(host, { url = "https://...", key = k, timeout? })
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
  assert(host and host.fetch, "tabicl needs a host with fetch")
  assert(opts and opts.url, "tabicl needs the server's url")
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
  local body, record = call.post(self.host, "tabicl", self.url, self.key, { train = f.train, labels = f.labels,
    categorical = f.categorical, test = { columns = test.columns, rows = test.rows } }, self.timeout)
  local probas = body and body.probas
  assert(type(probas) == "table" and #probas == #test.rows,
    ("tabicl gave %s answers for %d rows"):format(type(probas) == "table" and #probas or "no", #test.rows))
  record.ms = body and body.ms
  return probas, record
end

return M
