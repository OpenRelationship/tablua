-- Unit cases for ports.stream: server-sent chat events read as they arrive.
local spec = require("spec")
local stream = require("ports.stream")

local function event(text) return 'data: {"choices":[{"delta":{"content":"' .. text .. '"}}]}\n\n' end

spec.test("each piece is handed on as it arrives, and the whole reply is kept", function()
  local seen = {}
  local r = stream.reader(function(piece, so_far) seen[#seen + 1] = piece .. "|" .. so_far end)
  r:feed(event("Hel")):feed(event("lo"))
  spec.eq(seen[1], "Hel|Hel")
  spec.eq(seen[2], "lo|Hello")
  spec.eq(r.text, "Hello")
end)

spec.test("a chunk cut inside a line waits for the rest", function()
  local r = stream.reader()
  local whole = event("one") .. event(" two") .. "data: [DONE]\n\n"
  for i = 1, #whole, 7 do r:feed(whole:sub(i, i + 6)) end
  spec.eq(r.text, "one two")
  spec.eq(r.done, true)
end)

spec.test("a role chunk, a keep-alive comment and a bad line carry no text", function()
  local r = stream.reader()
  r:feed('data: {"choices":[{"delta":{"role":"assistant"}}]}\n\n: keep-alive\n\ndata: {not json\n\n' .. event("ok"))
  spec.eq(r.text, "ok")
end)

spec.test("the model, the finish and the usage the last events carry are kept", function()
  local r = stream.reader()
  r:feed('data: {"model":"d/v","choices":[{"delta":{"content":"hi"}}]}\n\n')
  r:feed('data: {"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"cost":0.002,"completion_tokens":3}}\n\n')
  spec.same({ r.text, r.model, r.finish, r.usage.cost }, { "hi", "d/v", "stop", 0.002 })
end)

spec.test("carriage returns between events are read as line ends", function()
  local r = stream.reader()
  r:feed('data: {"choices":[{"delta":{"content":"a"}}]}\r\n\r\n')
  spec.eq(r.text, "a")
end)

spec.run()
