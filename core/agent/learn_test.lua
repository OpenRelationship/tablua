-- Unit cases for agent/learn.lua: TabPFN ranks options from past outcomes once there are enough, and says why not
-- when there are not.
local spec = require("mono.spec")
local learn = require("agent.learn")
local memory = require("agent.memory")

local function store()
  return { rows = {}, events = function(self) return self.rows end,
    append = function(self, task, keyword, args) self.rows[#self.rows + 1] = { task = task, keyword = keyword, args = args } end }
end

spec.test("with no past outcomes there is no ranking, and it says why", function()
  local l = learn.new({ memory = memory.new(store()), tabpfn = {} })
  local ranked, why = l:rank("step", { request = "x", n = 1, fails = 0 }, { "run", "look" })
  spec.eq(ranked, nil)
  spec.eq(why, "no past outcomes to learn from yet")
end)

spec.test("without TabPFN, or with learning off, it says so", function()
  local m = memory.new(store())
  spec.eq(select(2, learn.new({ memory = m }):rank("step", {}, {})), "TabPFN is not set up (the keychain has no arock-priorlabs)")
  spec.eq(select(2, learn.new({ memory = m, tabpfn = {}, on = function() return false end }):rank("step", {}, {})),
    "learning from past outcomes is turned off")
end)

spec.test("with Tablua's rows the step checkpoint learns from them, in the columns known before Jev answers", function()
  local tablua = require("tablua")
  local train = { columns = {}, rows = {} }
  for j = 1, tablua.before do train.columns[j] = "c" .. j end
  local labels = {}
  for i = 1, 14 do
    train.rows[i] = tablua.row({ stage = "building", n = i }, i % 2 == 0 and "rewrite" or "think")
    labels[i] = i % 2 == 0 and 1 or 0
  end
  local asked = {}
  local t = { training = function(_, head, opts) asked[#asked + 1] = { head, opts and opts.before }
    local rows = {}
    for i, r in ipairs(train.rows) do local c = {} for j, v in ipairs(r) do c[j] = v end rows[i] = c end
    return { columns = train.columns, rows = rows }, labels end }
  local fitted, scored
  local tabpfn = { fit = function(_, set, y, opts) fitted = { set = set, y = y, opts = opts }; return "fit-t" end,
    estimate = function() return 10000 end,
    predict = function(_, _, test)
      scored = test
      local out = {}
      for i, row in ipairs(test.rows) do out[i] = row[1] == "rewrite" and { 0.1, 0.9 } or { 0.6, 0.4 } end
      return out
    end }
  local m = memory.new(store(), { today = function() return "2026-10-04" end })
  local l = learn.new({ memory = m, tabpfn = tabpfn, tablua = t })
  local ranked = l:rank("step", { stage = "building", stalls = 2, cause = "the_steps", own_checks = 0, n = 15,
    task = "r", at = 15 }, { "think", "rewrite" })
  spec.eq(ranked[1].name, "rewrite")
  spec.same(asked[1], { "progress", true })
  spec.eq(#fitted.set.rows, 14)
  spec.eq(fitted.set.columns[#fitted.set.columns], "count")
  spec.same(fitted.opts.categorical, tablua.categorical)
  spec.same(scored.rows[2], { "rewrite", "building", -1, 2, "", "", "the_steps", 0, 15, 1 })
  spec.eq(#scored.columns, #scored.rows[1])
end)

spec.test("enough outcomes: fitted once, each option given its chance, best first", function()
  local m = memory.new(store(), { today = function() return "2026-10-02" end })
  for i = 1, 12 do
    local task = m:begin("task " .. i)
    m:step(task, { n = 1, verb = i % 2 == 0 and "run" or "look", outcome = i % 2 == 0 and "complete" or "broken" })
  end
  local fits = 0
  local tabpfn = { fit = function() fits = fits + 1; return "fit-1" end, estimate = function() return 10000 end,
    predict = function(_, _, test)
      local out = {}
      for i, row in ipairs(test.rows) do out[i] = row[3] == "run" and { 0.2, 0.8 } or { 0.7, 0.3 } end
      return out
    end }
  local l = learn.new({ memory = m, tabpfn = tabpfn })
  local ranked = l:rank("step", { request = "task 13", n = 1, fails = 0, task = "request-13", at = 1 }, { "look", "run" })
  spec.eq(ranked[1].name, "run")
  spec.eq(ranked[1].p, 0.8)
  spec.eq(fits, 1)
  spec.eq(m:tokens_today(), 10000)
  -- the same state at a later step is ranked again without a call; a run asks at most learn.per_run times
  local calls = 0
  local predict = tabpfn.predict
  tabpfn.predict = function(...) calls = calls + 1; return predict(...) end
  spec.eq(l:rank("step", { request = "task 13", n = 2, fails = 0, task = "request-13", at = 2 }, { "look", "run" })[1].name, "run")
  spec.eq(calls, 0)
  local was = learn.per_run
  learn.per_run = 2
  spec.ok(l:rank("step", { request = "task 13", n = 3, fails = 1, task = "request-13", at = 3 }, { "look", "run" }))
  spec.eq(calls, 1)
  local none, why = l:rank("step", { request = "task 13", n = 4, fails = 2, task = "request-13", at = 4 }, { "look", "run" })
  spec.eq(none, nil)
  spec.eq(why, "this run's TabPFN predictions are used up")
  learn.per_run = was
end)

spec.run()
