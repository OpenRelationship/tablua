-- Unit cases for studio.features: a decision reads the comp before it (sizes, bound keys, open findings, the critic's
-- newest scores), the training table has a row per decided step in the studio columns, and learn ranks with it.
local spec = require("spec")
local features = require("studio.features")

local function sheet()
  local t = require("tablua").open(require("ports.sqlite").open(":memory:"), { clock = function() return "T" end })
  t:comp("r", 0, { tables = { node = { { id = "a", kind = "rect" } } } })
  t:comp("r", 1, { tables = { node = { { id = "a", kind = "rect" }, { id = "b", kind = "text" } },
    key = { { id = "b", name = "opacity", t = "beat:1", value = 1 }, { id = "a", name = "y", t = 0, value = 5 } } } })
  t:findings("r", 1, { { tier = "lint", id = "a", name = "y", code = "off_frame", severity = "error" },
    { tier = "check", id = "b", code = "contrast", severity = "warning" } })
  t:scores("r", 1, "critic", { rule = 4, relationship = 3, defaults = 2, rhythm = 4, memory = 3, craft = 5 })
  return t
end

spec.test("a decision reads the comp the step before it left, its findings and the critic's newest scores", function()
  local f = features.read(sheet(), "r", 2, { render_s = 3.5 })
  spec.same({ f.nodes, f.keys, f.bound, f.errors, f.warnings, f.check_errors, f.critic_low, f.critic_mean, f.defaults,
    f.since_look, f.render_s }, { 2, 2, 1, 1, 1, 0, 2, 3.5, 2, 1, 3.5 })
  local before = features.read(sheet(), "r", 1)
  spec.same({ before.nodes, before.errors, before.critic_low }, { 1, 0, -1 })
end)

local function decided(t, n, move, outcome)
  t:state{ todo = "r", n = n, stage = "building", pass = 0.5 }
  t:decision{ todo = "r", n = n, chosen = move, by = "jev" }
  t:outcome{ todo = "r", n = n, verb = move, outcome = outcome }
  features.record(t, "r", n, features.read(t, "r", n))
end

spec.test("the training table: one row per decided step with features, in the studio columns, labelled", function()
  local t = sheet()
  decided(t, 2, "set_prop", "complete")
  decided(t, 3, "add_key", "no_effect")
  t:decision{ todo = "r", n = 4, chosen = "remove", by = "jev" }   -- no features, no outcome: left out
  local train, labels = features.learner(t).training()
  spec.same({ #train.rows, labels, train.rows[1][1], train.rows[1][2], #train.rows[1], train.columns[9] },
    { 2, { 1, 0 }, "set_prop", "building", #features.columns, "nodes" })
  local test = features.learner(t).rows({ todo = "r", n = 3, stage = "building" }, { "set_prop", "look" })
  spec.same({ test.rows[2][1], test.rows[2][9] }, { "look", 2 })
end)

spec.test("learn ranks moves in the studio columns with the host's TabICL", function()
  local t = sheet()
  for n = 2, 15 do decided(t, n, n % 2 == 0 and "set_prop" or "add_key", n % 2 == 0 and "complete" or "no_effect") end
  local sent
  local host = { tabicl = function(body)
    sent = body
    local probas = {}
    for i, r in ipairs(body.test.rows) do probas[i] = r[1] == "set_prop" and { 0.1, 0.9 } or { 0.8, 0.2 } end
    return { probas = probas }
  end }
  local l = require("agent.learn").new{ tabpfn = require("ports.tabicl").new(host), tablua = t,
    step = features.learner(t) }
  local ranked = assert(l:rank("step", { todo = "r", n = 16, stage = "building", at = 16 }, { "add_key", "set_prop" }))
  spec.same({ ranked[1].name, sent.train.columns[1], #sent.train.rows, sent.categorical, #sent.test.columns,
    #sent.test.rows[1] }, { "set_prop", "move", 14, features.categorical, #features.columns, #features.columns })
end)

spec.run()
