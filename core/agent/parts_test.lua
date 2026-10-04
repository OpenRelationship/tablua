-- Unit cases for agent/parts.lua: Mercury splits a long request into goals, every prompt shows each part as done,
-- now or to do, and Jev is offered plan until there are parts, next_part while one is under way, and neither after.
local spec = require("mono.spec")
local parts = require("agent.parts")

-- an agent whose Mercury gives `reply`, keeping the rows it writes
local function agent(reply)
  local a = { name = "Fern", kept = {}, world = { state = function(_, req) return req.text end },
    env = { mercury = { chat = function() return reply end } } }
  function a:rows(keyword, args) self.kept[#self.kept + 1] = { keyword, args } end
  return a
end

spec.test("plan is offered until there are parts, then next_part until the last is done", function()
  local options = {}
  parts.options({ req = { text = "x" } }, options)
  spec.ok(options.plan and not options.next_part)
  options = {}
  parts.options({ req = { parts = { "a", "b" }, part = 1 } }, options)
  spec.ok(options.next_part and not options.plan)
  options = {}
  parts.options({ req = { parts = { "a", "b" }, part = 3 } }, options)
  spec.ok(not options.next_part and not options.plan)
end)

spec.test("Mercury's goals become the parts, shown as done, now and to do", function()
  local a = agent('{"parts": [{"goal": "Notes is open"}, {"goal": "a note exists"}]}')
  local req, step = { text = "make a note" }, { lines = {} }
  parts.plan(a, req, step)
  spec.eq(step.note, "Planned in 2 parts.")
  spec.eq(parts.render(req), "Parts of this request (now: 1): 1. now: Notes is open; 2. to do: a note exists")
  parts.next(a, req, { lines = {} })
  spec.eq(parts.render(req), "Parts of this request (now: 2): 1. done: Notes is open; 2. now: a note exists")
  parts.next(a, req, { lines = {} })
  spec.eq(parts.render(req), "Every part of this request is done; answer the person.")
end)

spec.test("fewer than two goals is no plan", function()
  local a = agent('{"parts": [{"goal": "one"}]}')
  local req, step = { text = "x" }, { lines = {} }
  parts.plan(a, req, step)
  spec.eq(req.parts, nil)
  spec.ok(step.note:find("Planning the parts failed", 1, true))
end)

spec.run()
