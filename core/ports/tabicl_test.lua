-- Unit cases for the TabICL port with a fake fetch: a fit is kept here and sent with each prediction, the key goes as a
-- Bearer token and never into the record, and learn.lua ranks a run's moves with it in TabPFN's place.
local spec = require("spec")
local tabicl = require("ports.tabicl")
local json = require("ports.json")

local function host(seen)
  return { fetch = function(req)
    seen.req, seen.url, seen.auth = json.decode(req.body), req.url, req.headers.Authorization
    local probas = {}
    for i, r in ipairs(seen.req.test.rows) do probas[i] = r[1] == "fix" and { 0.2, 0.8 } or { 0.7, 0.3 } end
    return { status = 200, body = json.encode({ probas = probas, ms = 5 }) }
  end }
end

spec.test("a fit costs no call; a prediction sends the fit's rows with the rows to score", function()
  local seen = {}
  local t = tabicl.new(host(seen), { url = "https://tab.test/", key = "k.s" })
  local id = t:fit({ columns = { "move", "n" }, rows = { { "fix", 1 }, { "look", 2 } } }, { 1, 0 }, { categorical = { 0 } })
  spec.eq(seen.req, nil)
  local probas, record = t:predict(id, { columns = { "move", "n" }, rows = { { "fix", 3 }, { "look", 3 } } })
  spec.same({ seen.url, seen.auth, seen.req.labels, seen.req.categorical, seen.req.train.rows[1], probas },
    { "https://tab.test/predict", "Bearer k.s", { 1, 0 }, { 0 }, { "fix", 1 }, { { 0.2, 0.8 }, { 0.7, 0.3 } } })
  spec.ok(not json.encode(record):find("k.s", 1, true), "the record holds the key")
  spec.eq(t:estimate{ operation = "cache_predict" }, 0)
end)

spec.test("a fit it does not have, and a reply without an answer for every row, are errors", function()
  local t = tabicl.new({ fetch = function() return { status = 200, body = '{"probas": []}' } end }, { url = "u", key = "k" })
  spec.err(function() t:predict("nope", { columns = {}, rows = {} }) end)
  local id = t:fit({ columns = { "a" }, rows = { { 1 } } }, { 1 }, {})
  spec.err(function() t:predict(id, { columns = { "a" }, rows = { { 1 } } }) end)
end)

spec.test("learn ranks a run's moves with it in TabPFN's place", function()
  local tablua = require("tablua")
  local t = tablua.open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  for n = 1, 16 do
    local move = n % 2 == 0 and "fix" or "look"
    t:state{ todo = "r", n = n, stage = "building" }
    t:candidates("r", n, { { move = move } })
    t:decision{ todo = "r", n = n, chosen = move, by = "jev" }
    t:outcome{ todo = "r", n = n, verb = move, outcome = move == "fix" and "complete" or "no_effect" }
  end
  local seen = {}
  local l = require("agent.learn").new{ tabpfn = tabicl.new(host(seen), { url = "u", key = "k" }), tablua = t }
  local ranked = assert(l:rank("step", { stage = "building", n = 17 }, { "look", "fix" }))
  spec.same({ ranked[1].name, #seen.req.train.rows, seen.req.categorical }, { "fix", 16, require("tablua").categorical })
end)

spec.test("with the host's own TabICL (host.tabicl, a model in its binary), the port calls it and no fetch", function()
  local got
  local h = { tabicl = function(body)
    got = body
    return { probas = { { 0.1, 0.9 } } }
  end }
  local t = tabicl.new(h)
  local id = t:fit({ columns = { "move" }, rows = { { "fix" }, { "look" } } }, { 1, 0 }, { categorical = { 0 } })
  local probas, record = t:predict(id, { columns = { "move" }, rows = { { "fix" } } })
  spec.same({ probas, got.labels, got.categorical, got.test.rows, record.service }, { { { 0.1, 0.9 } }, { 1, 0 }, { 0 },
    { { "fix" } }, "tabicl-local" })
  spec.err(function() tabicl.new({}) end)
end)

spec.run()
