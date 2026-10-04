-- ports.connect over a directory of two services held in memory: one described (calls, a header token and an
-- address part), one only listed. Nothing touches the network or the keychain.
local connect = require("ports.connect")
local json = require("ports.json")

local files = {
  ["index.json"] = json.encode({ index = {
    { slug = "acme", name = "Acme", categories = { "ticketing" }, docs = "https://acme.test/docs", operations = 2,
      env = { "ACME_TOKEN", "ACME_DOMAIN" }, verify = { method = "GET", path = "/me" } },
    { slug = "quiet", name = "Quiet Mail", categories = { "email" }, docs = "https://quiet.test", operations = 0,
      env = { "QUIET_API_KEY", "QUIET_SUBDOMAIN" } },
  } }),
  ["providers/acme/acme.lua"] = [[return {
    provider = "acme", name = "Acme", base = "https://{domain}/api",
    auth = { kind = "key", header = "x-acme-key", format = "{token}", env = "ACME_TOKEN" },
    config = { domain = "ACME_DOMAIN" }, headers = { accept = "application/json" },
    operations = {
      ["acme.tickets_list"] = { method = "GET", url = "https://{domain}/api/tickets", query = { "state" } },
      ["acme.tickets_create"] = { method = "POST", url = "https://{domain}/api/tickets", body = { "title", "body" } },
    } }]],
  ["providers/acme/index.json"] = json.encode({ operations = {
    { slug = "acme.tickets_list", name = "List tickets", description = "Lists the tickets.",
      input = { properties = { state = { type = "string" } } } },
    { slug = "acme.tickets_create", name = "Create a ticket", description = "Opens a new ticket.",
      input = { properties = { title = {}, body = {} }, required = { "title" } } },
  } }),
}

local secrets, sent = {}, {}
local replies = {}
local host = { fetch = function(req)
  sent[#sent + 1] = req
  return table.remove(replies, 1) or { status = 200, body = "{}" }
end }
local c = connect.new(host, { read = function(p) return files[p] end, secret = function(n) return secrets[n] end })

-- finding: by name, by kind
assert(c:find("acme tickets")[1].service == "acme")
assert(c:find("email")[1].service == "quiet")
assert(c:find("tickets")[1].service == "acme", "a plural finds its kind (ticketing)")
assert(#c:find("nothing like it") == 0)

-- its calls, best first, the needed arguments marked and first
local ops = assert(c:operations("acme", "create a ticket"))
assert(ops[1].op == "acme.tickets_create", ops[1].op)
assert(ops[1].args[1] == "title*" and ops[1].args[2] == "body", table.concat(ops[1].args, ","))
local none, why = c:operations("quiet")
assert(none == nil and why:find("publishes no description") and why:find("https://quiet.test"))
assert(c:method("acme.tickets_list") == "GET" and c:method("acme.tickets_create") == "POST")
assert(c:method("acme.nope") == nil)

-- what the person must give, from the pack: the token is a secret, the domain is not
local needs = c:needs("acme")
assert(needs.name == "Acme" and needs.docs == "https://acme.test/docs")
assert(#needs.fields == 2 and needs.fields[1].name == "ACME_TOKEN" and needs.fields[1].secret)
assert(needs.fields[1].label == "token" and needs.fields[2].label == "domain" and not needs.fields[2].secret)
assert(#needs.missing == 2)
-- and from the directory alone, for a service with no calls
local q = c:needs("quiet")
assert(q.fields[1].secret and not q.fields[2].secret and q.fields[2].label == "subdomain")

-- a call with no credential is refused before anything is sent, and says what to ask for
local v, err = c:call("acme.tickets_create", { title = "help" })
assert(v == nil and err.code == "denied" and err.needs and err.needs.service == "acme")
assert(#sent == 0)

-- given the credential, the call is signed, its address made, its body sent as JSON
secrets.ACME_TOKEN, secrets.ACME_DOMAIN = "s3cret", "acme.example"
replies[1] = { status = 201, body = json.encode({ id = 9 }) }
local value, record = c:call("acme.tickets_create", { title = "help", body = "it broke" })
assert(value.id == 9, "the service's answer")
assert(sent[1].method == "POST" and sent[1].url == "https://acme.example/api/tickets")
assert(sent[1].headers["x-acme-key"] == "s3cret")
assert(json.decode(sent[1].body).title == "help")
assert(record.status == 201 and record.method == "POST" and record.service == "acme")
for k, val in pairs(record) do assert(not tostring(val):find("s3cret"), "the record never holds the key: " .. k) end

-- a refused credential is "denied" with what to ask for again
replies[1] = { status = 401, body = "{}" }
v, err = c:call("acme.tickets_list", { state = "open" })
assert(v == nil and err.code == "denied" and err.needs.service == "acme")
assert(sent[2].url == "https://acme.example/api/tickets?state=open")

-- the directory's own test call
replies[1] = { status = 200, body = json.encode({ name = "me" }) }
assert(c:check("acme"))
assert(sent[3].url == "https://acme.example/api/me" and sent[3].headers["x-acme-key"] == "s3cret")

print("connect: ok")
