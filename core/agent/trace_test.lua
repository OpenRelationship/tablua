-- Unit cases for agent/trace.lua: every turn and every port call as rows, in a store a day.
local spec = require("spec")
local trace = require("agent.trace")

local function stores()
  local by = {}
  return by, function(day)
    by[day] = by[day] or { rows = {}, events = function(self) return self.rows end,
      append = function(self, task, keyword, args) self.rows[#self.rows + 1] = { task = task, keyword = keyword, args = args } end }
    return by[day]
  end
end

spec.test("a wrapped port's calls are rows, under the turn they came in", function()
  local by, open = stores()
  local t = trace.new({ open = open, today = function() return "2026-10-02" end, now = function() return 0 end })
  local task = t:turn("hello")
  local jev = t:wrap("jev", { decide = function(_, _, _) return { next = { choice = "run" } } end })
  spec.eq(jev:decide("state", {}).next.choice, "run")
  local rows = by["2026-10-02"].rows
  spec.eq(task, "turn-1")
  spec.eq(rows[1].keyword, "Heard")
  spec.eq(rows[2].keyword, "Port Call")
  spec.eq(rows[3].keyword, "Port Answer")
  spec.eq(rows[3].args[1], "jev.decide")
end)

spec.test("a failed call is a row, and the error still reaches the caller", function()
  local by, open = stores()
  local t = trace.new({ open = open, today = function() return "2026-10-02" end, now = function() return 0 end })
  local m = t:wrap("mercury", { chat = function() error("down") end })
  spec.err(function() m:chat({}) end, "down")
  spec.eq(by["2026-10-02"].rows[2].keyword, "Port Failed")
end)

spec.run()
