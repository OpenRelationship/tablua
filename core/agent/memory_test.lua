-- Unit cases for agent/memory.lua: a request, its steps and how it ended, as rows in a store, folded back the same
-- when the store is opened again.
local spec = require("mono.spec")
local memory = require("agent.memory")

local function store(rows)
  rows = rows or {}
  return { rows = rows,
    events = function(self) return self.rows end,
    append = function(self, task, keyword, args) self.rows[#self.rows + 1] = { task = task, keyword = keyword, args = args } end }
end

spec.test("a request, its steps and how it ended", function()
  local s = store()
  local m = memory.new(s, { today = function() return "2026-10-02" end })
  local task = m:begin("list my files")
  m:step(task, { n = 1, verb = "run", outcome = "complete" })
  m:outcome(task, "complete", "judged by Jev")
  spec.eq(m.requests[task].text, "list my files")
  spec.eq(m.requests[task].outcome, "complete")
  spec.same(s.rows[2].args, { "1", "run", "", "0", "", "", "", "" })
  spec.same(s.rows[3].args, { "step", "complete", "", "1" })
  -- opened again, the rows fold to the same
  local again = memory.new(store(s.rows))
  spec.eq(again.requests[task].outcome, "complete")
  spec.eq(again:begin("next"), "request-2")
end)

spec.test("TabPFN's tokens are counted by the day", function()
  local m = memory.new(store(), { today = function() return "2026-10-02" end })
  m:called("step", 12000)
  m:called("step", 10000)
  spec.eq(m:tokens_today(), 22000)
end)

spec.run()
