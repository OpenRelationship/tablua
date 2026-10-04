-- Unit cases for the vision port with a fake fetch: the request carries the
-- frame and the text, and the reply comes back with its cost; the key never
-- reaches the record.
local spec = require("mono.spec")
local see = require("ports.see")
local json = require("ports.json")

local function host(answer, seen)
  return { fetch = function(req)
    seen.req = json.decode(req.body)
    seen.auth = req.headers.Authorization
    return { status = 200, body = json.encode({ model = "m", usage = { cost = 0.0001, prompt_tokens = 900,
      completion_tokens = 20 }, choices = { { message = { content = answer } } } }) }
  end }
end

spec.test("a frame and a text go out; the reply comes back with its cost", function()
  local seen = {}
  local s = see.new(host("*** Tasks ***", seen), { key = "k" })
  local reply, record = s:look("iVBO\nRw==\n", "does it show chess pieces?")
  spec.eq(reply, "*** Tasks ***")
  spec.eq(record.cost, 0.0001)
  spec.eq(record.usage.prompt, 900)
  spec.eq(seen.req.model, see.model)
  spec.eq(seen.auth, "Bearer k")
  local parts = seen.req.messages[1].content
  spec.eq(parts[1].text, "does it show chess pieces?")
  spec.eq(parts[2].image_url.url, "data:image/png;base64,iVBORw==")
  assert(not json.encode(record):find('"k"', 1, true), "the record holds the key")
end)

spec.test("a sequence goes out as successive images, in order", function()
  local seen = {}
  see.new(host("ok", seen), { key = "k" }):look({ "QQ==", "Qg==", "Qw==" }, "what moves?")
  local parts = seen.req.messages[1].content
  spec.eq(#parts, 4)
  spec.eq(parts[4].image_url.url, "data:image/png;base64,Qw==")
end)

spec.test("no choice comes back as empty text, never as an answer", function()
  local s = see.new({ fetch = function() return { status = 200, body = "{}" } end }, { key = "k" })
  spec.eq((s:look("AA==", "x")), "")
end)

spec.test("on Cerebras the request has reasoning off and no usage field, and the cost comes from its prices", function()
  local seen, reply = {}, { model = "qwen-3.8-27b", usage = { prompt_tokens = 1000000, completion_tokens = 1000000 },
    choices = { { message = { content = "ok" } } } }
  local s = see.new({ fetch = function(req)
    seen.req, seen.url = json.decode(req.body), req.url
    return { status = 200, body = json.encode(reply) }
  end }, { key = "k", service = "cerebras" })
  local _, record = s:look("AA==", "x")
  spec.same({ seen.url, seen.req.model, seen.req.reasoning_effort, seen.req.usage },
    { "https://api.cerebras.ai/v1/chat/completions", "qwen-3.8-27b", "none", nil })
  spec.eq(record.service, "cerebras")
  assert(math.abs(record.cost - 2.48) < 1e-9, record.cost)
end)

spec.test("on Groq the request is Llama 4 Scout with no reasoning setting, priced from its list", function()
  local seen, reply = {}, { usage = { prompt_tokens = 1000000, completion_tokens = 1000000 },
    choices = { { message = { content = "ok" } } } }
  local s = see.new({ fetch = function(req)
    seen.req, seen.url = json.decode(req.body), req.url
    return { status = 200, body = json.encode(reply) }
  end }, { key = "k", service = "groq" })
  local text, record = s:look("AA==", "x")
  spec.same({ text, seen.url, seen.req.model, seen.req.reasoning_effort, seen.req.usage },
    { "ok", "https://api.groq.com/openai/v1/chat/completions", "meta-llama/llama-4-scout-17b-16e-instruct", nil, nil })
  spec.eq(record.service, "groq")
  assert(math.abs(record.cost - 0.45) < 1e-9, record.cost)
end)

spec.run()
