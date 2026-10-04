-- Unit cases for the writs port with a fake service: each version goes to /v1/writs/<note> with the session as the
-- bearer; sync sends only what the service does not have yet and stops at a refusal, so nothing is skipped.
local spec = require("mono.spec")
local writs = require("ports.writs")
local json = require("ports.json")

-- a fake service keeping versions as the worker does
local function service(fail_at)
  local kept, seen = {}, {}
  return { fetch = function(req)
    seen[#seen + 1] = req
    assert(req.headers.Authorization == "Bearer prk_s", "no session")
    local note = req.url:match("/v1/writs/([^/]+)$")
    if req.method == "PUT" and note then
      local b = json.decode(req.body)
      if fail_at and #seen == fail_at then return { status = 503, body = json.encode({ error = { message = "busy" } }) } end
      kept[note] = kept[note] or {}
      kept[note][b.version] = b.text
      return { status = 200, body = '{"kept":true}' }
    end
    if req.url:match("/v1/writs$") then
      local out = {}
      for k, vs in pairs(kept) do out[#out + 1] = { note = k, version = #vs, text = vs[#vs] } end
      return { status = 200, body = json.encode({ writs = out }) }
    end
    return { status = 404, body = json.encode({ error = { message = "There is nothing here." } }) }
  end, kept = kept, seen = seen }
end

spec.test("keep, newest and a refusal in the service's words", function()
  local s = service()
  local p = writs.new(s, { key = "prk_s", base = "https://svc.test" })
  spec.eq(p:keep("note-1", 1, "kind", "Rocks"), true)
  spec.eq(s.seen[1].url, "https://svc.test/v1/writs/note-1")
  spec.same(json.decode(s.seen[1].body), { version = 1, text = "kind", folder = "Rocks" })
  spec.eq(p:newest()[1].text, "kind")
  local ok, err = pcall(p.versions, p, "note-9")
  spec.same({ ok, err.status, tostring(err) }, { false, 404, "There is nothing here." })
  spec.err(function() p:keep("../etc", 1, "x") end, "not a writ's name")
end)

spec.test("sync sends only what is new, and stops at a refusal without skipping", function()
  local s = service(3)
  local p = writs.new(s, { key = "prk_s", base = "https://svc.test" })
  local list = { { id = "note-1", folder = "", versions = { "a", "b" } }, { id = "note-2", folder = "", versions = { "x" } } }
  local sent = {}
  local n, err = writs.sync(p, list, sent)
  spec.same({ n, sent["note-1"], sent["note-2"], err.status }, { 2, 2, nil, 503 })
  n = writs.sync(p, list, sent)
  spec.same({ n, sent["note-2"] }, { 1, 1 })
  list[1].versions[3] = "c"
  spec.eq(writs.sync(p, list, sent), 1)
  spec.eq(writs.sync(p, list, sent), 0)
  spec.same(s.kept["note-1"], { "a", "b", "c" })
end)

spec.run()
