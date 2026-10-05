-- Unit cases for ports.mercury with a fake fetch: chat's request as Inception reads it, its tool calls in the
-- record, and the temperature floor Mercury honours.
local spec = require("spec")
local mercury = require("ports.mercury")
local json = require("ports.json")

local function host(seen, message)
  return { fetch = function(req)
    seen[#seen + 1] = json.decode(req.body)
    return { status = 200, body = json.encode({ model = "mercury-2.5", usage = { prompt_tokens = 10, completion_tokens = 2 },
      choices = { { message = message } } }) }
  end }
end

spec.test("chat sends the system and the person's words, without reasoning by default", function()
  local seen = {}
  local m = mercury.new(host(seen, { content = "hello" }), { key = "k" })
  local text, record = m:chat({ system = "s", user = "u" })
  spec.eq(text, "hello")
  spec.eq(seen[1].reasoning_effort, "instant")
  spec.eq(seen[1].temperature, 0.5)
  spec.same(seen[1].messages, { { role = "system", content = "s" }, { role = "user", content = "u" } })
  spec.eq(record.tool_calls, nil)
end)

spec.test("with tools, Mercury's calls come back in the record", function()
  local seen = {}
  local call = { id = "c1", type = "function", ["function"] = { name = "computer", arguments = '{"cmd": "ls"}' } }
  local m = mercury.new(host(seen, { tool_calls = { call } }), { key = "k" })
  local tool = { type = "function", ["function"] = { name = "computer", strict = true, parameters = { type = "object" } } }
  local text, record = m:chat({ messages = { { role = "user", content = "list" } }, tools = { tool },
    tool_choice = "required", temperature = 0.6, reasoning_effort = "medium" })
  spec.eq(text, nil)
  spec.eq(record.tool_calls[1]["function"].arguments, '{"cmd": "ls"}')
  spec.eq(seen[1].tool_choice, "required")
  spec.eq(seen[1].temperature, 0.6)
  spec.eq(seen[1].tools[1]["function"].strict, true)
  spec.same(seen[1].messages, { { role = "user", content = "list" } })
end)

spec.test("a temperature under Mercury's floor is raised to it, not sent to be reset to 1", function()
  local seen = {}
  mercury.new(host(seen, { content = "x" }), { key = "k" }):chat({ system = "s", user = "u", temperature = 0.2 })
  spec.eq(seen[1].temperature, 0.5)
end)

spec.run()
