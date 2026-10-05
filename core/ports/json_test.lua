-- Unit cases for ports.json and the call's retry rule.
local spec = require("spec")
local json = require("ports.json")
local call = require("ports.call")

spec.test("objects are written with sorted keys", function()
  spec.eq(json.encode({ b = 1, a = { 2, 3 }, c = "x" }), '{"a":[2,3],"b":1,"c":"x"}')
end)

spec.test("strings escape quotes, backslashes and control bytes and keep UTF-8", function()
  spec.eq(json.encode('a"b\\c\n\1é'), '"a\\"b\\\\c\\n\\u0001é"')
end)

spec.test("numbers keep integers whole and floats exact", function()
  spec.eq(json.encode(3), "3")
  spec.eq(json.encode(-0.1), "-0.1")
  spec.eq(json.decode("-0.1"), -0.1)
  spec.eq(json.decode("1e3"), 1000)
end)

spec.test("empty tables are objects unless marked as arrays", function()
  spec.eq(json.encode({}), "{}")
  spec.eq(json.encode(json.array({})), "[]")
  spec.eq(json.encode(json.decode("[]")), "[]")
end)

spec.test("decoding reads escapes and surrogate pairs", function()
  spec.eq(json.decode('"\\u00e9\\ud83d\\ude00\\/\\t"'), "é\240\159\152\128/\t")
end)

spec.test("null stays in arrays and leaves objects", function()
  local v = json.decode('{"a":null,"b":[1,null,3]}')
  spec.eq(v.a, nil)
  spec.eq(#v.b, 3)
  spec.eq(v.b[2], json.null)
end)

spec.test("a round trip keeps nested values", function()
  local text = '{"answers":{"t":{"choice":"fail","probabilities":{"fail":0.8,"pass":0.2}}},"id":"gen-1","ok":true}'
  spec.eq(json.encode(json.decode(text)), text)
end)

spec.test("malformed text is refused with a position", function()
  spec.err(function() json.decode('{"a":1,}') end, "expected a key at byte 8")
  spec.err(function() json.decode("[1] x") end, "trailing text")
  spec.err(function() json.decode('"open') end, "unterminated")
end)

spec.test("a network failure is tried three times, a second and then three apart, and then reported", function()
  local tries, slept = 0, {}
  local host = { fetch = function() tries = tries + 1; error("timeout") end,
    sleep = function(s) slept[#slept + 1] = s end }
  spec.err(function() call.post(host, "jev", "u", "k", {}) end, "jev unreachable: .*timeout")
  spec.eq(tries, 3)
  spec.eq(table.concat(slept, ","), "1,3")
end)

spec.test("a service's error message is kept, the key is not", function()
  local host = { fetch = function() return { status = 402, body = '{"error":{"message":"no credits"}}' } end }
  local ok, e = pcall(call.post, host, "mercury", "u", "secret-key", {})
  spec.eq(ok, false)
  spec.eq(tostring(e), "mercury answered 402: no credits")
  spec.eq(e.record.tries, 1)
  spec.eq(tostring(e):find("secret-key", 1, true), nil)
end)

spec.run()
