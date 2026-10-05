-- Unit cases for tablua.control: the controls a step chose among, learned from as TabPFN's "control" head, and
-- how logged predictions have done.
local spec = require("mono.spec")
local tablua = require("tablua")
local sqlite = require("ports.sqlite")

local function fresh() return tablua.open(sqlite.open(":memory:"), { clock = function() return "t" end }) end

local function reading(n, send_at)
  local out = {}
  for i = 1, n do out[i] = { id = "c" .. i, role = "button", label = i == send_at and "Send" or ("Item " .. i), order = i } end
  return out
end

local function choice(t, task, chosen, outcome)
  t:controls(task, 1, "press", "Mail", reading(30, 17), chosen)
  t:outcome{ task = task, n = 1, verb = "press", outcome = outcome }
end

spec.test("a choice that worked: the chosen control was the one, a sample of the others were not", function()
  local t = fresh()
  choice(t, "r1", "c17", "complete")
  choice(t, "r2", "c3", "broken")
  local train, labels = t:control_training()
  spec.same(train.columns, { "app", "verb", "role", "label", "order", "seen_ok" })
  spec.same(train.rows[1], { "Mail", "press", "button", "Send", 17, 0 })
  spec.eq(labels[1], 1)
  -- of the 29 others, the sample of 20, each not the one
  spec.eq(#labels, 1 + 20 + 1)
  -- the failed choice says only that its control was not the one, the Send button seen working once before it
  spec.same(train.rows[#train.rows], { "Mail", "press", "button", "Item 3", 3, 0 })
  spec.eq(labels[#labels], 0)
  spec.eq(t:count("control"), 60)
end)

spec.test("a candidate's row counts how often its label was the one that worked", function()
  local t = fresh()
  choice(t, "r1", "c17", "complete")
  choice(t, "r2", "c17", "complete")
  local rows = t:control_rows({ app = "Mail", verb = "press" }, { { id = "x", role = "button", label = "Send", order = 4 },
    { id = "y", role = "button", label = "Item 2", order = 2 } })
  spec.same(rows, { { "Mail", "press", "button", "Send", 4, 2 }, { "Mail", "press", "button", "Item 2", 2, 0 } })
end)

spec.test("a prediction is scored once its step took that move or chose that control", function()
  local t = fresh()
  t:state{ task = "r1", n = 1 }
  t:decision{ task = "r1", n = 1, chosen = "menu", by = "jev" }
  t:prediction("r1", 1, "progress", "menu", 0.8)
  t:prediction("r1", 1, "progress", "press", 0.3)
  spec.eq(t:scored("progress").n, 0)
  t:outcome{ task = "r1", n = 1, verb = "menu", outcome = "complete" }
  spec.same(t:scored("progress"), { n = 1, right = 1, brier = (0.8 - 1) ^ 2 })
  choice(t, "r2", "c17", "broken")
  t:prediction("r2", 1, "control", "c17", 0.9)
  local r = t:scored("control")
  spec.eq(r.n, 1)
  spec.eq(r.right, 0)
end)

spec.run()
