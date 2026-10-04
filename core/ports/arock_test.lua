-- Unit cases for the Arock service port with a fake fetch: Mercury's and Jev's requests go to the service's
-- paths with the session as the bearer; refusals come back in the service's own words; the record never holds
-- the session.
local spec = require("mono.spec")
local arock = require("ports.arock")
local json = require("ports.json")

local function host(seen, status, body)
  return { fetch = function(req)
    seen[#seen + 1] = req
    return { status = status or 200, body = json.encode(body or { model = "arock", usage = {},
      choices = { { message = { content = "Hi there" }, text = "x" } }, answers = { ok = { noul = 1 } } }) }
  end }
end

spec.test("chat, fill, edit and decide reach the service with the session", function()
  local seen = {}
  local p = arock.new(host(seen), { key = "prk_s", base = "https://svc.test" })
  local text, record = p:chat{ system = "s", user = "u" }
  p:fill{ path = "a.lua", before = "x", after = "y" }
  p:edit{ path = "a.lua", lines = { "a", "b" }, first = 1, last = 2 }
  local answers = p:decide("state", { ok = { kind = "noul", text = "?", yes = "y", no = "n" } })
  local urls = {}
  for i, r in ipairs(seen) do
    urls[i] = r.url
    assert(r.headers.Authorization == "Bearer prk_s", "no session on " .. r.url)
  end
  spec.same(urls, { "https://svc.test/v1/chat/completions", "https://svc.test/v1/fim/completions",
    "https://svc.test/v1/edit/completions", "https://svc.test/v1/decisions" })
  spec.same({ text, record.service, answers.ok.noul }, { "Hi there", "arock", 1 })
  assert(not json.encode(record):find("prk_s", 1, true), "the record holds the session")
end)

spec.test("a refusal is the service's own message, with its status", function()
  local said = "Arock needs a subscription, $20 a month. Subscribe at https://svc.test/subscribe"
  local p = arock.new(host({}, 402, { error = { message = said, code = "not_subscribed" } }), { key = "k", base = "https://svc.test" })
  local ok, err = pcall(p.chat, p, { system = "s", user = "u" })
  spec.same({ ok, err.status, tostring(err) }, { false, 402, said })
end)

spec.test("an unreachable service is said plainly", function()
  local p = arock.new({ fetch = function() error("curl: Could not resolve host", 0) end }, { key = "k" })
  local ok, err = pcall(p.chat, p, { system = "s", user = "u" })
  spec.same({ ok, err.message }, { false, "Arock's service could not be reached: curl: Could not resolve host" })
end)

spec.test("the account is read with the session, and a lapsed session is a 401", function()
  local seen = {}
  local p = arock.new(host(seen, 200, { email = "a@b.c", subscribed = true }), { key = "prk_s", base = "https://svc.test" })
  spec.same({ p:account().email, seen[1].method, seen[1].url }, { "a@b.c", "GET", "https://svc.test/v1/account" })
  local gone = arock.new(host({}, 401, { error = { message = "Sign in to Arock first." } }), { key = "k" })
  local ok, err = pcall(gone.account, gone)
  spec.same({ ok, err.status, err.message }, { false, 401, "Sign in to Arock first." })
end)

spec.test("on a node the service hears the person, and a request elsewhere does not", function()
  local seen = {}
  local h = host(seen, 200, { choices = { { message = { content = "hi" } } } })
  local p = arock.new(h, { key = "node-token", person = "user-sam", base = "https://svc.test" })
  p:chat{ system = "s", user = "u" }
  spec.same({ seen[1].headers["X-Arock-Person"], seen[1].headers.Authorization }, { "user-sam", "Bearer node-token" })
  p.host.fetch({ method = "PUT", url = "https://uploads.priorlabs.test/signed", headers = {} })
  spec.same(seen[2].headers["X-Arock-Person"], nil)
end)

spec.test("a command runs on one of the person's computers, and a refusal is said in the node's words", function()
  local seen = {}
  local p = arock.new(host(seen, 200, { results = { { code = 0, out = "hello\n", err = "", cwd = "/home" } } }),
    { key = "prk_s", base = "https://svc.test" })
  local r = p:run("rock-1a2b", "echo hello")
  spec.same({ r.code, r.out, r.cwd }, { 0, "hello\n", "/home" })
  spec.same({ seen[1].method, seen[1].url, seen[1].headers.Authorization, json.decode(seen[1].body).lines },
    { "POST", "https://svc.test/computers/rock-1a2b/run", "Bearer prk_s", { "echo hello" } })
  local theirs = arock.new({ fetch = function() return { status = 403, body = "There is no computer rock-1a2b of yours." } end }, { key = "k" })
  local ok, err = pcall(theirs.run, theirs, "rock-1a2b", "ls")
  spec.same({ ok, err.status, err.message }, { false, 403, "There is no computer rock-1a2b of yours." })
  local ok2, err2 = pcall(p.run, p, "../v1/account", "ls")
  spec.same({ ok2, err2.message }, { false, "not a computer's name: ../v1/account" })
end)

spec.test("the person writes on their computer, grants and takes back reach, and agrees to a feature", function()
  local seen = {}
  local p = arock.new(host(seen, 200, { ok = true }), { key = "prk_s", base = "https://svc.test" })
  spec.same({ p:write("rock-1a2b", "writs/note-3.md", "@pebbles is kind.") }, { true })
  spec.same({ p:grant("rock-1a2b", "file-mail", "ACCOUNT", "google-mail") }, { true })
  spec.same({ p:revoke("rock-1a2b", "file-mail", "ACCOUNT", "google-mail") }, { true })
  spec.same({ p:agree("rock-1a2b", "features/plantwatch.feature") }, { true })
  local urls = {}
  for i, r in ipairs(seen) do
    urls[i] = r.method .. " " .. r.url
    assert(r.headers.Authorization == "Bearer prk_s", "no session on " .. r.url)
  end
  spec.same(urls, { "POST https://svc.test/computers/rock-1a2b/write", "POST https://svc.test/computers/rock-1a2b/grant",
    "POST https://svc.test/computers/rock-1a2b/revoke", "POST https://svc.test/computers/rock-1a2b/agree" })
  spec.same(json.decode(seen[1].body), { path = "writs/note-3.md", text = "@pebbles is kind." })
  spec.same(json.decode(seen[2].body), { tool = "file-mail", reach = "ACCOUNT", value = "google-mail" })
  spec.same(json.decode(seen[4].body), { feature = "features/plantwatch.feature" })
  -- the node's no is the second answer, in its words
  local no = arock.new(host({}, 200, { ok = false, why = "manifest.org is refused:\n2: RUN names the code it runs" }),
    { key = "k", base = "https://svc.test" })
  spec.same({ no:write("rock-1a2b", "manifest.org", "x") }, { false, "manifest.org is refused:\n2: RUN names the code it runs" })
  local ok, err = pcall(p.grant, p, "../v1/account", "t", "NET", "a.b")
  spec.same({ ok, err.message }, { false, "not a computer's name: ../v1/account" })
end)

spec.run()
