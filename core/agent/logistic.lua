-- A stand-in for TabPFN with no key and no server: logistic regression over the same rows, in TabPFN's port shape
-- (ports.tabpfn), so learn.lua ranks moves with it as it would with TabPFN. A categorical column is read as its
-- values (one column each, from the training rows; a value never seen reads as none of them); a number is scaled by
-- the training rows' mean and spread. The fit is batch gradient descent from zero, a fixed number of rounds with an
-- L2 penalty: the same rows give the same fit on every Lua. Weaker than TabPFN: it sees each column alone, no
-- interactions, so a move that works only in some stage is averaged across stages.
--
--   local l = require("agent.logistic").new{ rounds?, rate?, penalty? }
--   learn.new{ tabpfn = l, tablua = t }
--   l:fit(train, labels, { categorical = { 0-based indices } }) -> id
--   l:predict(id, test) -> { { p0, p1 }, ... }      l:estimate(q) -> 0
local M = {}
local L = {}
L.__index = L

M.rounds, M.rate, M.penalty = 400, 0.5, 0.01

function M.new(opts)
  opts = opts or {}
  return setmetatable({ rounds = opts.rounds or M.rounds, rate = opts.rate or M.rate,
    penalty = opts.penalty or M.penalty, fits = {}, n = 0 }, L)
end

function L:estimate(_) return 0 end

-- How each column becomes inputs: a categorical one's values, sorted; a number's mean and spread.
local function encoder(train, categorical)
  local cat = {}
  for _, j in ipairs(categorical or {}) do cat[j + 1] = true end
  local cols = {}
  for j = 1, #train.columns do
    if cat[j] then
      local seen, values = {}, {}
      for _, r in ipairs(train.rows) do
        local v = tostring(r[j])
        if not seen[v] then seen[v], values[#values + 1] = true, v end
      end
      table.sort(values)
      cols[j] = { values = values }
    else
      local sum, sq, n = 0, 0, #train.rows
      for _, r in ipairs(train.rows) do
        local v = tonumber(r[j]) or 0
        sum, sq = sum + v, sq + v * v
      end
      local mean = n > 0 and sum / n or 0
      local spread = n > 0 and math.sqrt(math.max(sq / n - mean * mean, 0)) or 0
      cols[j] = { mean = mean, spread = spread > 0 and spread or 1 }
    end
  end
  return cols
end

-- A row as inputs: 1 (the intercept), then each column's.
local function inputs(cols, row)
  local x = { 1 }
  for j, c in ipairs(cols) do
    if c.values then
      local v = tostring(row[j])
      for _, value in ipairs(c.values) do x[#x + 1] = v == value and 1 or 0 end
    else
      x[#x + 1] = ((tonumber(row[j]) or 0) - c.mean) / c.spread
    end
  end
  return x
end

local function sigmoid(z)
  if z >= 0 then return 1 / (1 + math.exp(-z)) end
  local e = math.exp(z)
  return e / (1 + e)
end

local function dot(w, x)
  local z = 0
  for i = 1, #x do z = z + w[i] * x[i] end
  return z
end

function L:fit(train, labels, opts)
  assert(#labels == #train.rows, ("logistic fit: %d labels for %d rows"):format(#labels, #train.rows))
  local cols = encoder(train, opts and opts.categorical)
  local xs = {}
  for i, r in ipairs(train.rows) do xs[i] = inputs(cols, r) end
  local k, n = #(xs[1] or { 1 }), #xs
  local w = {}
  for i = 1, k do w[i] = 0 end
  for _ = 1, self.rounds do
    local grad = {}
    for i = 1, k do grad[i] = 0 end
    for r = 1, n do
      local err = sigmoid(dot(w, xs[r])) - labels[r]
      for i = 1, k do grad[i] = grad[i] + err * xs[r][i] end
    end
    for i = 1, k do
      -- the intercept is not penalised
      local pen = i > 1 and self.penalty * w[i] or 0
      w[i] = w[i] - self.rate * (grad[i] / math.max(n, 1) + pen)
    end
  end
  self.n = self.n + 1
  local id = "logistic:" .. self.n
  self.fits[id] = { cols = cols, w = w }
  return id
end

function L:predict(id, test)
  local f = assert(self.fits[id], "logistic: no fit " .. tostring(id))
  local out = {}
  for i, r in ipairs(test.rows) do
    local p = sigmoid(dot(f.w, inputs(f.cols, r)))
    out[i] = { 1 - p, p }
  end
  return out
end

return M
