-- The Jev port: typed decisions over OpenRouter's Decisions API.
--
--   local jev = require("ports.jev").new(host, { key = k })
--   local answers, record = jev:decide(state, questions)
--
-- questions maps an id of our choosing to one of
--   { kind = "choice", text = "...", options = { name = "description", ... } }
--   { kind = "noul",   text = "...", yes = "...", no = "..." }
--   { kind = "score",  text = "...", levels = { "...", "..." } }
-- and answers maps the same ids to { choice, probabilities, confidence },
-- { noul } or { score, probabilities, confidence }. A question with optional = true
-- (a feature asked beside the decision) may go unanswered: its answer is then left out. Jev has no prompt cache,
-- so every question about one state belongs in one call.
local call = require("ports.call")
local json = require("ports.json")

local M = {}
local Jev = {}
Jev.__index = Jev

M.url = "https://openrouter.ai/api/alpha/decisions"
M.model = "typesafe/jev-1.13"

function M.new(host, opts)
  assert(host and host.fetch, "jev needs a host with fetch")
  assert(opts and opts.key, "jev needs a key")
  return setmetatable({ host = host, key = opts.key, url = opts.url or M.url, model = opts.model or M.model }, Jev)
end

local function question(q)
  if q.kind == "choice" then
    return { type = "choice", instructions = q.text, criteria = q.options }
  elseif q.kind == "noul" then
    return { type = "noul", instructions = q.text, criteria = { ["true"] = q.yes, ["false"] = q.no } }
  elseif q.kind == "score" then
    return { type = "score", instructions = q.text, criteria = json.array(q.levels) }
  end
  error("jev: unknown question kind " .. tostring(q.kind))
end

-- Jev's own statistic: how concentrated the distribution is, 0 to 1.
local function confidence(probabilities, n)
  local peak = 0
  for _, p in pairs(probabilities or {}) do
    if p > peak then peak = p end
  end
  if n < 2 then return 1 end
  return math.max(0, math.min(1, (n * peak - 1) / (n - 1)))
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function answer(id, q, a)
  assert(type(a) == "table", "jev gave no answer for " .. id)
  if q.kind == "choice" then
    assert(q.options[a.choice] ~= nil, ("jev chose %s, which was not offered"):format(tostring(a.choice)))
    return { choice = a.choice, probabilities = a.probabilities,
      confidence = a.confidence or confidence(a.probabilities, count(q.options)) }
  elseif q.kind == "noul" then
    return { noul = assert(tonumber(a.noul), "jev gave no noul for " .. id) }
  end
  return { score = a.score, probabilities = a.probabilities,
    confidence = a.confidence or confidence(a.probabilities, #q.levels) }
end

function Jev:decide(state, questions)
  local asked = {}
  for id, q in pairs(questions) do asked[id] = question(q) end
  local body, record = call.post(self.host, "jev", self.url, self.key,
    { model = self.model, state = state, questions = asked }, 10)
  record.model = body.model
  record.usage = body.usage
  record.cost = body.usage and body.usage.cost
  local answers = {}
  for id, q in pairs(questions) do
    local a = (body.answers or {})[id]
    if a ~= nil or not q.optional then answers[id] = answer(id, q, a) end
  end
  return answers, record
end

return M
