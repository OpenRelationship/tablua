-- Unit cases for agent/learn.lua: TabPFN ranks options from past outcomes, Tablua's rows, once there are enough,
-- and says why not when there are not.
local spec = require("spec")
local learn = require("agent.learn")
local tablua = require("tablua")
local sqlite = require("ports.sqlite")

-- the host's ledger of the day's TabPFN tokens (env.memory: called, tokens_today)
local function ledger()
  return { tokens = 0, called = function(self, _, tokens) self.tokens = self.tokens + tokens end,
    tokens_today = function(self) return self.tokens end }
end

local function fresh() return tablua.open(sqlite.open(":memory:"), { clock = function() return "t" end }) end

-- past steps: "run" helped, "look" did not
local function past(t, k)
  for i = 1, k do
    local task, verb = "request-" .. i, i % 2 == 0 and "run" or "look"
    t:state{ task = task, n = 1, stage = "building" }
    t:decision{ task = task, n = 1, chosen = verb, by = "jev" }
    t:outcome{ task = task, n = 1, verb = verb, outcome = verb == "run" and "complete" or "broken" }
  end
end

local function fake()
  local tab = { fits = 0 }
  function tab.fit(_, set, y, opts) tab.fits, tab.set, tab.y, tab.opts = tab.fits + 1, set, y, opts; return "fit-" .. tab.fits end
  function tab.estimate() return 10000 end
  function tab.predict(_, _, test)
    tab.test = test
    local out = {}
    for i, row in ipairs(test.rows) do out[i] = row[1] == "run" and { 0.2, 0.8 } or { 0.7, 0.3 } end
    return out
  end
  return tab
end

spec.test("with no past outcomes there is no ranking, and it says why", function()
  local l = learn.new({ tablua = fresh(), tabpfn = fake() })
  local ranked, why = l:rank("step", { n = 1 }, { "run", "look" })
  spec.eq(ranked, nil)
  spec.eq(why, "no past outcomes to learn from yet")
end)

spec.test("without TabPFN, or with learning off, it says so", function()
  spec.eq(select(2, learn.new({ tablua = fresh() }):rank("step", {}, {})), "TabPFN is not set up (no Prior Labs key)")
  spec.eq(select(2, learn.new({ tablua = fresh(), tabpfn = fake(), on = function() return false end }):rank("step", {}, {})),
    "learning from past outcomes is turned off")
end)

spec.test("enough outcomes: fitted once on Tablua's rows, each option given its chance, best first, logged", function()
  local t, tab = fresh(), fake()
  past(t, 14)
  local m = ledger()
  local l = learn.new({ memory = m, tablua = t, tabpfn = tab })
  local ranked = l:rank("step", { stage = "building", stalls = 2, n = 2, task = "request-15", at = 2 }, { "look", "run" })
  spec.eq(ranked[1].name, "run")
  spec.eq(ranked[1].p, 0.8)
  spec.eq(tab.fits, 1)
  spec.eq(#tab.set.rows, 14)
  spec.eq(#tab.set.columns, tablua.before)
  spec.same(tab.opts.categorical, tablua.categorical)
  spec.same(tab.test.rows[2], { "run", "building", -1, 2, "", "", "", 0, 2 })
  spec.eq(m:tokens_today(), 10000)
  spec.eq(t:count("prediction"), 2)
  spec.same(t:fitted("progress", learn.schema.step), { id = "fit-1", rows = 14 })
  -- the same state at a later step is ranked again without a call; a run asks at most learn.per_run times
  local calls, predict = 0, tab.predict
  tab.predict = function(...) calls = calls + 1; return predict(...) end
  spec.eq(l:rank("step", { stage = "building", stalls = 2, n = 3, task = "request-15", at = 3 }, { "look", "run" })[1].name, "run")
  spec.eq(calls, 0)
  local was = learn.per_run
  learn.per_run = 2
  spec.ok(l:rank("step", { stage = "building", stalls = 3, n = 4 }, { "look", "run" }))
  spec.eq(calls, 1)
  local none, why = l:rank("step", { stage = "building", stalls = 4, n = 5 }, { "look", "run" })
  spec.eq(none, nil)
  spec.eq(why, "this run's TabPFN predictions are used up")
  learn.per_run = was
end)

spec.test("a learn made fresh for every step still holds the run to its budget and reuses its rankings", function()
  local t, tab = fresh(), fake()
  past(t, 14)
  local calls, predict = 0, tab.predict
  tab.predict = function(...) calls = calls + 1; return predict(...) end
  local function step(n, stalls)
    return learn.new({ tablua = t, tabpfn = tab, per_run = 2 }):rank("step",
      { stage = "building", stalls = stalls, n = n, task = "request-15", at = n }, { "look", "run" })
  end
  spec.ok(step(1, 0))
  spec.ok(step(2, 0))            -- the same state at a later step: no call
  spec.eq(calls, 1)
  spec.ok(step(3, 1))
  spec.eq(calls, 2)
  local none, why = step(4, 2)   -- a third paid ranking would pass the run's 2
  spec.eq(none, nil)
  spec.eq(why, "this run's TabPFN predictions are used up")
  spec.eq(t:count("ranking"), 2)
  -- another run has its own budget
  spec.ok(learn.new({ tablua = t, tabpfn = tab, per_run = 2 }):rank("step",
    { stage = "building", stalls = 2, n = 1, task = "request-16", at = 1 }, { "look", "run" }))
end)

spec.test("a logged prediction is scored once its step took that move", function()
  local t, tab = fresh(), fake()
  past(t, 14)
  local l = learn.new({ tablua = t, tabpfn = tab })
  spec.eq(l:record_line("step"), "its predictions here are not scored yet")
  l:rank("step", { stage = "building", n = 1, task = "request-15", at = 1 }, { "look", "run" })
  t:decision{ task = "request-15", n = 1, chosen = "run", by = "jev" }
  t:outcome{ task = "request-15", n = 1, verb = "run", outcome = "complete" }
  spec.eq(l:record_line("step"), "right on 1 of 1 scored predictions here, Brier 0.04")
end)

spec.test("the control checkpoint learns from the controls past steps chose among", function()
  local t, tab = fresh(), fake()
  for i = 1, 12 do
    local list = {}
    for j = 1, 3 do list[j] = { id = "c" .. j, role = "button", label = j == 2 and "Send" or ("Item " .. j), order = j } end
    t:controls("r" .. i, 1, "press", "Mail", list, "c2")
    t:outcome{ task = "r" .. i, n = 1, verb = "press", outcome = "complete" }
  end
  tab.predict = function(_, _, test)
    tab.test = test
    local out = {}
    for i, row in ipairs(test.rows) do out[i] = row[4] == "Send" and { 0.1, 0.9 } or { 0.8, 0.2 } end
    return out
  end
  local l = learn.new({ tablua = t, tabpfn = tab })
  local ranked = l:rank("control", { app = "Mail", verb = "press", task = "r13", at = 1 },
    { { id = "x1", role = "button", label = "Item 1", order = 1 }, { id = "x2", role = "button", label = "Send", order = 2 } })
  spec.eq(ranked[1].name, "x2")
  spec.same(tab.set.columns, { "app", "verb", "role", "label", "order", "seen_ok" })
  spec.same(tab.test.rows[2], { "Mail", "press", "button", "Send", 2, 12 })
end)

spec.run()
