-- Unit cases for agent/logistic.lua: TabPFN's port shape with no key, a categorical column read as its values, the
-- same fit for the same rows, and learn.lua ranking with it.
local spec = require("spec")
local logistic = require("agent.logistic")

local function rows(n)
  local train, labels = { columns = { "move", "stalls" }, rows = {} }, {}
  for i = 1, n do
    local good = i % 2 == 0
    train.rows[i] = { good and "fix" or "look", i % 3 }
    labels[i] = good and 1 or 0
  end
  return train, labels
end

spec.test("a categorical column is read as its values: the move that worked ranks above the one that did not", function()
  local l = logistic.new()
  local train, labels = rows(20)
  local id = l:fit(train, labels, { categorical = { 0 } })
  local p = l:predict(id, { columns = train.columns, rows = { { "fix", 1 }, { "look", 1 }, { "unseen", 1 } } })
  spec.ok(p[1][2] > 0.8 and p[2][2] < 0.2, ("fix %.2f, look %.2f"):format(p[1][2], p[2][2]))
  spec.ok(math.abs(p[1][1] + p[1][2] - 1) < 1e-9)
  spec.ok(p[3][2] > p[2][2] and p[3][2] < p[1][2], "a value never seen sits between")
end)

spec.test("the same rows give the same fit, to the last digit", function()
  local train, labels = rows(30)
  local a, b = logistic.new(), logistic.new()
  local pa = a:predict(a:fit(train, labels, { categorical = { 0 } }), train)
  local pb = b:predict(b:fit(train, labels, { categorical = { 0 } }), train)
  spec.same(pa, pb)
end)

spec.test("it costs nothing, and a fit it does not have is an error", function()
  local l = logistic.new()
  spec.eq(l:estimate{ operation = "cache_predict", train_rows = 10 }, 0)
  spec.err(function() l:predict("nope", { columns = {}, rows = {} }) end)
end)

spec.test("learn ranks a run's moves with it in TabPFN's place", function()
  local tablua = require("tablua")
  local t = tablua.open(require("ports.sqlite").open(":memory:"), { clock = function() return "2026-10-06T00:00:00Z" end })
  for n = 1, 16 do
    local move = n % 2 == 0 and "fix" or "look"
    t:state{ todo = "r", n = n, stage = "building" }
    t:candidates("r", n, { { move = move } })
    t:decision{ todo = "r", n = n, chosen = move, by = "jev" }
    t:outcome{ todo = "r", n = n, verb = move, outcome = move == "fix" and "complete" or "no_effect" }
  end
  local l = require("agent.learn").new{ tabpfn = logistic.new(), tablua = t }
  local ranked = assert(l:rank("step", { stage = "building", n = 17 }, { "look", "fix" }))
  spec.eq(ranked[1].name, "fix")
end)

spec.run()
