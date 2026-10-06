-- The world model's port over a fake chat: its own system prompt, thinking off, and the foreseen screen read out.
local spec = require("spec")
local agentworld = require("ports.agentworld")

spec.test("it sends AgentWorld's prompt and the session's turns with thinking off, and gives back the screen", function()
  local seen
  local chat = { chat = function(_, req)
    seen = req
    return "The file was written in turn 1.\n<predicted_observation>root@x:/app# cat a\nhi\nroot@x:/app#</predicted_observation>",
      { cost = 0 }
  end }
  local w = agentworld.new(chat)
  local screen = w:foresee({ opening = "root@x:/app#", turns = {} }, "cat a\n", 1)
  spec.eq(screen, "root@x:/app# cat a\nhi\nroot@x:/app#")
  spec.same({ seen.thinking, seen.temperature, #seen.messages }, { false, 0.6, 1 })
  spec.ok(seen.system:find("Terminal World Model", 1, true), "the system prompt is AgentWorld's")
end)

spec.test("a failed call or a reply with no screen is nil and why", function()
  local w = agentworld.new({ chat = function() error({ message = "503 no upstreams", status = 503 }) end })
  local screen, why = w:foresee({ opening = "", turns = {} }, "ls\n", 1)
  spec.same({ screen, why }, { nil, "503 no upstreams" })
  w = agentworld.new({ chat = function() return "hmm" end })
  spec.same({ w:foresee({ opening = "", turns = {} }, "ls\n", 1) }, { nil, "the world model foresaw no screen" })
end)

spec.test("encode sends the same turns to the encoder and gives back its vector", function()
  local seen
  local host = { fetch = function(req)
    seen = require("ports.json").decode(req.body)
    return { status = 200, body = require("ports.json").encode({ data = { { embedding = { 0.5, -1, 2 } } } }) }
  end }
  local w = agentworld.new({ chat = function() end }, { encoder = { host = host, url = "https://enc.test/v1/embeddings",
    key = "k", model = "qwen-world-encoder" } })
  local v = w:encode({ opening = "root@x:/app#", turns = {} }, "make\n", 30)
  spec.same(v, { 0.5, -1, 2 })
  spec.same({ seen.model, seen.messages[1].role, #seen.messages }, { "qwen-world-encoder", "system", 2 })
  spec.ok(seen.messages[2].content:find('"keystrokes": "make\\n"', 1, true), seen.messages[2].content)
end)

spec.run()
