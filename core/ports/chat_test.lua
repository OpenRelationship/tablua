-- Unit cases for the chat port with a fake fetch: OpenRouter asks for its usage and cost; Cerebras gets the
-- reasoning effort as asked and no usage field, and its cost comes from its listed prices.
local spec = require("spec")
local chat = require("ports.chat")
local json = require("ports.json")

local function host(seen, usage)
  return { fetch = function(req)
    seen.req, seen.url = json.decode(req.body), req.url
    return { status = 200, body = json.encode({ usage = usage, choices = { { message = { content = "done" } } } }) }
  end }
end

spec.test("on OpenRouter the request asks for usage and the cost is OpenRouter's", function()
  local seen = {}
  local m = chat.new(host(seen, { cost = 0.01, prompt_tokens = 10, completion_tokens = 5 }), { key = "k", model = "a/b" })
  local text, record = m:chat{ system = "s", user = "u", max_tokens = 100, reasoning_effort = "high" }
  spec.same({ text, record.cost, record.service, seen.req.usage.include, seen.req.reasoning_effort },
    { "done", 0.01, "openrouter", true, nil })
end)

spec.test("on Cerebras the effort goes as asked, no usage field, and the cost comes from its prices", function()
  local seen = {}
  local m = chat.new(host(seen, { prompt_tokens = 2000000, completion_tokens = 1000000 }),
    { key = "k", service = "cerebras", model = "gpt-oss-120b" })
  local _, record = m:chat{ system = "s", user = "u", max_tokens = 100, reasoning_effort = "high" }
  spec.same({ seen.url, seen.req.reasoning_effort, seen.req.usage, record.service },
    { "https://api.cerebras.ai/v1/chat/completions", "high", nil, "cerebras" })
  assert(math.abs(record.cost - 1.45) < 1e-9, record.cost)
  assert(not json.encode(record):find('"k"', 1, true), "the record holds the key")
end)

spec.test("with thinking off, OpenRouter is asked not to reason and no reasoning tokens are reserved", function()
  local seen = {}
  local m = chat.new(host(seen, {}), { key = "k", model = "deepseek/deepseek-v4.1-flash", thinking = false,
    sort = "latency" })
  m:chat{ system = "s", user = "u", max_tokens = 300 }
  spec.same({ seen.req.reasoning.enabled, seen.req.max_tokens, seen.req.provider.sort }, { false, 300, "latency" })
end)

spec.test("a conversation goes as real turns after the system text", function()
  local seen = {}
  local m = chat.new(host(seen, {}), { key = "k", model = "a/b" })
  m:chat{ system = "s", messages = { { role = "user", content = "hi" }, { role = "assistant", content = "hey" },
    { role = "user", content = "tired" } } }
  local roles = {}
  for i, x in ipairs(seen.req.messages) do roles[i] = x.role .. ":" .. x.content end
  spec.same(roles, { "system:s", "user:hi", "assistant:hey", "user:tired" })
end)

spec.test("with on_text the reply is asked for as a stream and heard as it comes, then returned whole", function()
  local seen, heard = {}, {}
  local fake = { fetch = function(req)
    seen.req = json.decode(req.body)
    local body = ""
    for _, piece in ipairs({ "Sure", ", on", " it." }) do
      local chunk = 'data: {"model":"d/v","choices":[{"delta":{"content":"' .. piece .. '"}}]}\n\n'
      body = body .. chunk
      req.on_data(chunk)
    end
    local last = 'data: {"choices":[],"usage":{"cost":0.001,"prompt_tokens":9,"completion_tokens":4}}\n\ndata: [DONE]\n\n'
    req.on_data(last)
    return { status = 200, body = body .. last }
  end }
  local m = chat.new(fake, { key = "k", model = "d/v", thinking = false })
  local text, record = m:chat{ system = "s", user = "u", on_text = function(_, so_far) heard[#heard + 1] = so_far end }
  spec.same({ seen.req.stream, text, record.cost, record.usage.completion, record.model },
    { true, "Sure, on it.", 0.001, 4, "d/v" })
  spec.same(heard, { "Sure", "Sure, on", "Sure, on it." })
end)

spec.test("an unknown service is refused", function()
  assert(not pcall(chat.new, { fetch = function() end }, { key = "k", model = "m", service = "elsewhere" }))
end)

spec.run()

spec.test("tools go as asked, and a reply of tool calls alone is an answer, the calls in the record", function()
  local seen = {}
  local calls = { { id = "c", type = "function", ["function"] = { name = "computer", arguments = "{}" } } }
  local m = chat.new({ fetch = function(req)
    seen.req = json.decode(req.body)
    return { status = 200, body = json.encode({ usage = {}, choices = { { message = { tool_calls = calls } } } }) }
  end }, { key = "k", model = "qwen/qwen3.8-omni-flash" })
  local text, record = m:chat{ messages = { { role = "system", content = "s" }, { role = "user", content = "u" } },
    tools = { { type = "function" } }, tool_choice = "required", temperature = 0.6 }
  spec.same({ text, record.tool_calls[1].id, seen.req.tool_choice, seen.req.temperature, #seen.req.messages,
    seen.req.messages[1].role }, { "", "c", "required", 0.6, 2, "system" })
  m.tool_choice = "auto"
  m:chat{ messages = { { role = "user", content = "u" } }, tools = { { type = "function" } }, tool_choice = "required" }
  spec.eq(seen.req.tool_choice, "auto")
end)
