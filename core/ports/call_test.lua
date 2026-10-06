-- The shared HTTP call: a server booting from zero is waited for, within a bound; other failures as before.
local spec = require("spec")
local call = require("ports.call")
local json = require("ports.json")

local function host(statuses)
  local slept, i = {}, 0
  return { slept = slept, sleep = function(s) slept[#slept + 1] = s end, fetch = function()
    i = i + 1
    local s = statuses[i] or statuses[#statuses]
    if s == 200 then return { status = 200, body = json.encode({ ok = true }) } end
    return { status = s, body = s == 503 and "no upstreams available" or "bad" }
  end }
end

spec.test("a server booting from zero answers 503 no upstreams until it is up, and is waited for", function()
  local h = host({ 503, 503, 503, 200 })
  local body, record = call.post(h, "openai", "https://own.test", "k", {})
  spec.same({ body.ok, record.booted, record.tries, #h.slept, h.slept[1] }, { true, true, 1, 3, call.boot_wait })
end)

spec.test("a server that never comes up ends in an error once the boot wait is spent", function()
  local keep = call.boot
  call.boot = 30
  local h = host({ 503 })
  spec.err(function() call.post(h, "openai", "https://own.test", "k", {}) end, "no upstreams")
  call.boot = keep
  spec.ok(#h.slept <= 3 + 2, "it waited " .. #h.slept .. " times")
end)

spec.test("any other 5xx is still tried three times", function()
  local h = host({ 502 })
  spec.err(function() call.post(h, "openai", "https://own.test", "k", {}) end, "502")
  spec.same(h.slept, { 1, 3 })
end)

spec.test("once: a failure is final, not tried again", function()
  local h = host({ 502 })
  spec.err(function() call.post(h, "openai", "https://own.test", "k", {}, 20, nil, true) end, "502")
  spec.same(h.slept, {})
end)

spec.run()
