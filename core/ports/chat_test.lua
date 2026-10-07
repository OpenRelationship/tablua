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

spec.test("a call may turn thinking off for itself alone, and asks no cap unless given one", function()
  local seen = {}
  local m = chat.new(host(seen, {}), { key = "k", model = "z-ai/glm-5.3-flash" })
  m:chat{ system = "s", user = "u", thinking = false }
  spec.same({ seen.req.reasoning.enabled, seen.req.max_tokens }, { false, nil })
  m:chat{ system = "s", user = "u" }
  spec.eq(seen.req.reasoning, nil)
  m:chat{ system = "s", user = "u", reasoning_effort = "low" }
  spec.same(seen.req.reasoning, { effort = "low" })
end)

spec.test("a turn keeps its tool calls and the call a tool's reply answers", function()
  local seen = {}
  local m = chat.new(host(seen, {}), { key = "k", model = "a/b" })
  local call = { id = "c1", type = "function", ["function"] = { name = "search", arguments = "{}" } }
  m:chat{ system = "s", messages = { { role = "user", content = "go" }, { role = "assistant", content = "", tool_calls = { call } },
    { role = "tool", tool_call_id = "c1", content = "found" } } }
  spec.same({ seen.req.messages[3].tool_calls[1].id, seen.req.messages[4].tool_call_id }, { "c1", "c1" })
end)

spec.test("an OpenAI-compatible server at the host's url; thinking off goes in Qwen's chat template", function()
  local seen = {}
  local m = chat.new(host(seen, {}), { key = "k.s", service = "openai", url = "https://own.test/v1/chat/completions",
    model = "qwen-agent" })
  m:chat{ system = "s", user = "u", thinking = false }
  spec.same({ seen.url, seen.req.chat_template_kwargs.enable_thinking, seen.req.reasoning }, { "https://own.test/v1/chat/completions", false, nil })
  spec.err(function() chat.new(host(seen, {}), { key = "k", service = "openai", model = "m" }) end)
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

spec.test("an OpenAI-compatible server is sent the reasoning effort as asked (Ollama turns thinking off with none)", function()
  local seen = {}
  local m = chat.new(host(seen, {}), { key = "k", service = "openai", url = "http://localhost:11434/v1/chat/completions",
    model = "qwen3.5:0.8b" })
  m:chat{ system = "s", user = "u", reasoning_effort = "none" }
  spec.eq(seen.req.reasoning_effort, "none")
  m:chat{ system = "s", user = "u" }
  spec.eq(seen.req.reasoning_effort, nil)
end)

spec.test("MiniMax's own API: its url, thinking kept out of the answer, thinking off as MiniMax words it", function()
  local seen = {}
  local m = chat.new(host(seen, {}), { key = "k", service = "minimax", model = "MiniMax-M3" })
  local text = m:chat{ system = "s", user = "u", reasoning_effort = "low" }
  spec.same({ text, seen.url, seen.req.reasoning_split, seen.req.reasoning_effort, seen.req.thinking, seen.req.usage },
    { "done", "https://api.minimax.io/v1/chat/completions", true, "low", nil, nil })
  m:chat{ system = "s", user = "u", thinking = false }
  spec.same(seen.req.thinking, { type = "disabled" })
end)

spec.test("a reply whose budget went to reasoning says so, with the tokens spent, and how to get an answer", function()
  local m = chat.new({ fetch = function()
    return { status = 200, body = json.encode({ usage = { completion_tokens = 11000,
      completion_tokens_details = { reasoning_tokens = 11000 } },
      choices = { { finish_reason = "length", message = { content = "", reasoning = "hmm" } } } }) }
  end }, { key = "k", model = "minimax/minimax-m3" })
  local ok, err = pcall(m.chat, m, { system = "s", user = "u", max_tokens = 5000 })
  spec.ok(not ok)
  spec.ok(tostring(err):find("11000 tokens reasoning", 1, true), err)
  spec.ok(tostring(err):find("thinking = false", 1, true), err)
end)

spec.test("a tool turn keeps the reasoning MiniMax asks to be sent back with it", function()
  local seen = {}
  local m = chat.new(host(seen, {}), { key = "k", service = "minimax", model = "MiniMax-M3" })
  m:chat{ system = "s", messages = { { role = "user", content = "go" },
    { role = "assistant", content = "", reasoning_content = "why", tool_calls = { { id = "c1" } } } } }
  spec.eq(seen.req.messages[3].reasoning_content, "why")
end)

spec.run()
