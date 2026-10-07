-- Unit cases for agent.loop, pi's agent loop in Lua (badlogic/pi-mono, packages/agent/src/agent-loop.ts): a model
-- that calls tools until it answers without one, tool errors as results, steering between turns, follow-ups after
-- the model would stop, hooks around each tool call, a reply cut at its limit failing its calls, and an abort.
local spec = require("spec")
local loop = require("agent.loop")
local json = require("ports.json")

-- a model that answers from a script: each entry is a reply (text, tool calls, finish) or a function of the request
local function model(script)
  local m = { seen = {} }
  function m.chat(_, req)
    m.seen[#m.seen + 1] = req
    local r = table.remove(script, 1)
    if type(r) == "function" then r = r(req) end
    if r.error then error(r.error, 0) end
    local calls
    for i, c in ipairs(r.calls or {}) do
      calls = calls or {}
      calls[i] = { id = "c" .. #m.seen .. "_" .. i, type = "function",
        ["function"] = { name = c[1], arguments = type(c[2]) == "string" and c[2] or json.encode(c[2]) } }
    end
    return r.text or "", { tool_calls = calls or {}, finish = r.finish or (calls and "tool_calls" or "stop"),
      reasoning = r.reasoning, usage = { prompt = 10, completion = 5 } }
  end
  return m
end

local function adder(log)
  return { name = "add", description = "Add two numbers.",
    parameters = { type = "object", properties = { a = { type = "number" }, b = { type = "number" } },
      required = { "a", "b" } },
    execute = function(args)
      log[#log + 1] = args.a + args.b
      return { content = tostring(args.a + args.b), details = { sum = args.a + args.b } }
    end }
end

spec.test("the model calls tools until it answers without one; results go back as tool messages", function()
  local log = {}
  local m = model({ { calls = { { "add", { a = 1, b = 2 } } }, reasoning = "sum it" }, { text = "It is 3." } })
  local l = loop.new{ model = m, system = "You add.", tools = { adder(log) } }
  local out = l:prompt("What is 1 + 2?")
  spec.same({ out.stop, #l.messages, log[1] }, { "stop", 4, 3 })
  spec.same({ l.messages[1].role, l.messages[2].role, l.messages[3].role, l.messages[4].content },
    { "user", "assistant", "tool", "It is 3." })
  -- the second request carries the call, its reasoning and the result, as the provider takes them
  local sent = m.seen[2].messages
  spec.same({ sent[2].tool_calls[1]["function"].name, sent[2].reasoning_content, sent[3].role, sent[3].content,
    sent[3].details }, { "add", "sum it", "tool", "3", nil })
  spec.eq(m.seen[1].system, "You add.")
  spec.eq(m.seen[1].tools[1]["function"].name, "add")
end)

spec.test("a tool that fails, an unknown tool and bad arguments come back to the model as error results", function()
  local m = model({ { calls = { { "add", "{not json" }, { "nope", {} }, { "boom", {} } } }, { text = "Sorry." } })
  local boom = { name = "boom", description = "x", parameters = { type = "object" },
    execute = function() error("the engine fell over", 0) end }
  local l = loop.new{ model = m, system = "s", tools = { adder({}), boom } }
  l:prompt("go")
  local results = {}
  for _, msg in ipairs(l.messages) do if msg.role == "tool" then results[#results + 1] = msg end end
  spec.eq(#results, 3)
  spec.ok(results[1].is_error and results[1].content:find("not valid JSON", 1, true), results[1].content)
  spec.eq(results[2].content, "Tool nope not found")
  spec.same({ results[3].is_error, results[3].content }, { true, "the engine fell over" })
end)

spec.test("hooks: before a call may block it, after a call may change its result, every event is heard", function()
  local events, log = {}, {}
  local m = model({ { calls = { { "add", { a = 1, b = 1 } }, { "add", { a = 2, b = 2 } } } }, { text = "done" } })
  local l = loop.new{ model = m, system = "s", tools = { adder(log) },
    before_tool = function(_, args) if args.a == 2 then return { block = true, reason = "no twos" } end end,
    after_tool = function(_, _, result) return { content = result.content .. " (checked)" } end,
    on = function(e) events[#events + 1] = e.type end }
  l:prompt("go")
  spec.same(log, { 2 })
  spec.same({ l.messages[3].content, l.messages[4].content, l.messages[4].is_error }, { "2 (checked)", "no twos", true })
  spec.same({ events[1], events[2], events[#events] }, { "agent_start", "turn_start", "agent_end" })
  local starts = 0
  for _, e in ipairs(events) do if e == "tool_start" then starts = starts + 1 end end
  spec.eq(starts, 2)
end)

spec.test("steering is read between turns; a follow-up after the model would stop starts another turn", function()
  local m = model({ { calls = { { "add", { a = 1, b = 2 } } } },
    function(req) return { text = "seen: " .. req.messages[#req.messages].content } end, { text = "and the follow-up" } })
  local l = loop.new{ model = m, system = "s", tools = { adder({}) } }
  l:steer("use small numbers")
  l:follow_up("now say bye")
  local out = l:prompt("go")
  -- the steer was queued before the run, so it is read before the first reply; the follow-up after the model stopped
  spec.eq(m.seen[1].messages[2].content, "use small numbers")
  spec.eq(l.messages[#l.messages].content, "and the follow-up")
  spec.eq(out.stop, "stop")
end)

spec.test("a reply cut at its token limit fails its calls rather than running them", function()
  local log = {}
  local m = model({ { calls = { { "add", { a = 1, b = 2 } } }, finish = "length" }, { text = "ok" } })
  local l = loop.new{ model = m, system = "s", tools = { adder(log) } }
  l:prompt("go")
  spec.eq(#log, 0)
  spec.ok(l.messages[3].is_error and l.messages[3].content:find("token limit", 1, true))
end)

spec.test("a model that fails ends the run with its error; an abort ends it after the call in hand", function()
  local l = loop.new{ model = model({ { error = "openrouter answered 400: bad" } }), system = "s", tools = {} }
  local out = l:prompt("go")
  spec.same({ out.stop, out.error }, { "error", "openrouter answered 400: bad" })
  local log = {}
  local l2
  l2 = loop.new{ model = model({ { calls = { { "add", { a = 1, b = 1 } }, { "add", { a = 5, b = 5 } } } } }),
    system = "s", tools = { adder(log) }, after_tool = function() l2:abort() end }
  spec.eq(l2:prompt("go").stop, "aborted")
  spec.same(log, { 2 })
end)

spec.test("a result may carry an image: the tool message keeps the text and the image follows as a user turn", function()
  local m = model({ { calls = { { "look", {} } } }, { text = "I see it." } })
  local look = { name = "look", description = "x", parameters = { type = "object" },
    execute = function() return { content = "the sheet", image = "UE5H" } end }
  local l = loop.new{ model = m, system = "s", tools = { look } }
  l:prompt("go")
  local sent = m.seen[2].messages
  spec.same({ sent[3].role, sent[3].content, sent[4].role, sent[4].content[2].image_url.url },
    { "tool", "the sheet", "user", "data:image/png;base64,UE5H" })
end)

spec.test("finish_turn may end the run after a turn, or ask for one more turn of the context alone", function()
  local m = model({ { calls = { { "add", { a = 1, b = 2 } } } }, { text = "never" } })
  local l = loop.new{ model = m, system = "s", tools = { adder({}) }, finish_turn = function() return "end" end }
  l:prompt("go")
  spec.eq(#m.seen, 1)
end)

spec.run()
