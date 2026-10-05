-- Unit cases for the rocks port with a fake service: each call goes to /v1/rocks with the session as the bearer, a
-- rock's name is checked before anything is sent, and a refusal comes back in the service's own words.
local spec = require("mono.spec")
local rocks = require("ports.rocks")
local json = require("ports.json")

local function service()
  local seen = {}
  return { seen = seen, fetch = function(req)
    seen[#seen + 1] = req
    assert(req.headers.Authorization == "Bearer prk_s", "no session")
    if req.url:match("/v1/rocks$") then return { status = 200, body = json.encode({ rocks = { { id = "pebbles", name = "Pebbles" } } }) } end
    if req.method == "PUT" then return { status = 200, body = '{"kept":true}' } end
    if req.method == "POST" then return { status = 200, body = json.encode({ kept = #json.decode(req.body).messages }) } end
    if req.url:match("/v1/rocks/gone/") then return { status = 404, body = json.encode({ error = { message = "There is no such rock." } }) } end
    return { status = 200, body = json.encode({ messages = { { seq = 7, uid = "a:1", who = "me", text = "hi" } }, next = 7 }) }
  end }
end

spec.test("list, keep, send and read speak /v1/rocks", function()
  local s = service()
  local p = rocks.new(s, { key = "prk_s", base = "https://svc.test" })
  spec.eq(p:list()[1].name, "Pebbles")
  spec.eq(p:keep({ id = "jade", name = "Jade", pinned = true, look = "stone=jade" }), true)
  spec.eq(s.seen[2].url, "https://svc.test/v1/rocks/jade")
  spec.same(json.decode(s.seen[2].body), { name = "Jade", pinned = true, look = "stone=jade" })
  spec.eq(p:send("jade", { { uid = "a:1", who = "me", text = "hi" } }), 1)
  spec.same(json.decode(s.seen[3].body).messages[1], { uid = "a:1", who = "me", text = "hi", kind = "text", detail = "" })
  local got, next = p:read("jade", 3)
  spec.same({ got[1].text, next, s.seen[4].url }, { "hi", 7, "https://svc.test/v1/rocks/jade/messages?after=3" })
end)

spec.test("a refusal in the service's words, and no request for a bad name", function()
  local s = service()
  local p = rocks.new(s, { key = "prk_s", base = "https://svc.test" })
  local ok, err = pcall(p.read, p, "gone", 0)
  spec.same({ ok, err.status, tostring(err) }, { false, 404, "There is no such rock." })
  spec.err(function() p:keep({ id = "../etc", name = "x" }) end, "not a rock's name")
  spec.eq(#s.seen, 1)
end)

local down = rocks.new({ fetch = function() error("connection refused") end }, { key = "prk_s" })
spec.test("an unreachable service says so", function()
  spec.err(function() down:list() end, "could not be reached")
end)
