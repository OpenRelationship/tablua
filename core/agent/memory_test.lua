-- Unit cases for agent/memory.lua: what the agent did and how it turned out, as rows in a store, folded back the
-- same when the store is opened again.
local spec = require("mono.spec")
local memory = require("agent.memory")

local function store(rows)
  rows = rows or {}
  return { rows = rows,
    events = function(self) return self.rows end,
    append = function(self, task, keyword, args) self.rows[#self.rows + 1] = { task = task, keyword = keyword, args = args } end }
end

spec.test("a request, its steps, Jev's sureness and how it ended", function()
  local s = store()
  local m = memory.new(s, { today = function() return "2026-10-02" end })
  local task = m:begin("list my files")
  m:step(task, { n = 1, verb = "run", outcome = "complete" })
  m:sure(task, 1, "run", 0.9, 0.8)
  m:outcome(task, "complete", "judged by Jev")
  spec.eq(m.requests[task].text, "list my files")
  spec.eq(m.requests[task].outcome, "complete")
  spec.eq(m.steps[1].outcome, "complete")
  spec.eq(m.steps[1].p, 0.9)
  spec.eq(m:worked(m.steps[1]), 1)
  -- opened again, the rows fold to the same
  local again = memory.new(store(s.rows))
  spec.eq(again.steps[1].p, 0.9)
  spec.eq(again.requests[task].outcome, "complete")
end)

spec.test("a step in a request judged a false claim did not work", function()
  local m = memory.new(store())
  local task = m:begin("x")
  m:step(task, { n = 1, verb = "run", outcome = "complete" })
  m:outcome(task, "hallucination")
  spec.eq(m:worked(m.steps[1]), 0)
end)

spec.test("TabPFN's tokens are counted by the day", function()
  local m = memory.new(store(), { today = function() return "2026-10-02" end })
  m:called("step", 12000)
  m:called("step", 10000)
  spec.eq(m:tokens_today(), 22000)
end)

spec.run()
