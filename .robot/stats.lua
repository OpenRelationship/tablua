-- The numbers our claims are judged by, in portable Lua: how well a score ranks a label (AUROC), how far two groups'
-- means part, and how often chance does as well (the same measure with the label shuffled, many times). Shuffles
-- are seeded, so a claim measured twice on the same rows gives the same answer.
--
--   local stats = require("stats")
--   stats.auroc(scores, labels) -> auc | nil   labels 1 or 0; nil without both kinds
--   stats.gap(values, groups) -> mean of group 1 less mean of group 0 | nil
--   stats.shuffled(measure, xs, labels, k?, seed?) -> { observed, null, p }
--       measure: stats.auroc or stats.gap; null: its mean over k shuffles of the labels; p: (1 + shuffles at or
--       above the observed) / (k + 1), how often chance did as well
local M = {}

M.k = 1000

function M.auroc(scores, labels)
  local idx = {}
  for i = 1, #scores do idx[i] = i end
  table.sort(idx, function(a, b) return scores[a] < scores[b] end)
  -- each score's rank, ties given the mean of the ranks they share
  local rank, i = {}, 1
  while i <= #idx do
    local j = i
    while j < #idx and scores[idx[j + 1]] == scores[idx[i]] do j = j + 1 end
    for k = i, j do rank[idx[k]] = (i + j) / 2 end
    i = j + 1
  end
  local pos, neg, sum = 0, 0, 0
  for k = 1, #labels do
    if labels[k] == 1 then pos, sum = pos + 1, sum + rank[k] else neg = neg + 1 end
  end
  if pos == 0 or neg == 0 then return nil end
  return (sum - pos * (pos + 1) / 2) / (pos * neg)
end

function M.gap(values, groups)
  local s, n = { [0] = 0, [1] = 0 }, { [0] = 0, [1] = 0 }
  for k = 1, #values do
    local g = groups[k] == 1 and 1 or 0
    s[g], n[g] = s[g] + values[k], n[g] + 1
  end
  if n[0] == 0 or n[1] == 0 then return nil end
  return s[1] / n[1] - s[0] / n[0]
end

-- a linear congruential generator: the same shuffles on every Lua VM
local function rng(seed)
  local state = seed % 2147483647
  if state <= 0 then state = state + 2147483646 end
  return function(n)
    state = (state * 16807) % 2147483647
    return state % n + 1
  end
end

function M.shuffled(measure, xs, labels, k, seed)
  k = k or M.k
  local observed = measure(xs, labels)
  if observed == nil then return nil end
  local rand = rng(seed or 20261006)
  local copy, sum, above = {}, 0, 0
  for i = 1, #labels do copy[i] = labels[i] end
  for _ = 1, k do
    for i = #copy, 2, -1 do
      local j = rand(i)
      copy[i], copy[j] = copy[j], copy[i]
    end
    local v = measure(xs, copy)
    sum = sum + v
    if v >= observed - 1e-12 then above = above + 1 end
  end
  return { observed = observed, null = sum / k, p = (1 + above) / (k + 1) }
end

return M
