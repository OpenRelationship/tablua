-- Unit cases for the search port with a fake fetch: a search and a page read go to Parallel's paths with the key in
-- x-api-key (or as a Bearer token for a service that proxies it), and their results come back in one shape.
local spec = require("spec")
local search = require("ports.search")
local json = require("ports.json")

local function host(seen, body)
  return { fetch = function(req)
    seen[#seen + 1] = req
    return { status = 200, body = json.encode(body) }
  end }
end

spec.test("a search sends the objective and queries with the key in x-api-key", function()
  local seen = {}
  local s = search.new(host(seen, { search_id = "s1", results = { { url = "https://a.test", title = "A",
    publish_date = json.null, excerpts = { "a" } } } }), { key = "par" })
  local results, record = s:search("granite", { "granite" })
  spec.same({ seen[1].url, seen[1].headers["x-api-key"], results[1].url, results[1].date, record.search_id },
    { "https://api.parallel.ai/v1/search", "par", "https://a.test", nil, "s1" })
end)

spec.test("a page read asks for the page as it is now, and reports a page it could not read", function()
  local seen = {}
  local s = search.new(host(seen, { extract_id = "e1",
    results = { { url = "https://scores.test", title = "Scores", publish_date = "2026-09-29", excerpts = { "Cubs 0, Padres 3" } } },
    errors = { { url = "https://gone.test", error_type = "fetch_failed", http_status_code = 404 } } }), { key = "par" })
  local results, record = s:read({ "https://scores.test", "https://gone.test" }, "the Cubs score")
  local sent = json.decode(seen[1].body)
  spec.same({ seen[1].url, sent.advanced_settings.fetch_policy.max_age_seconds, sent.objective },
    { "https://api.parallel.ai/v1/extract", 600, "the Cubs score" })
  spec.same({ results[1].excerpts[1], results[2].url, results[2].error, record.extract_id },
    { "Cubs 0, Padres 3", "https://gone.test", "fetch_failed 404", "e1" })
end)

spec.test("for a proxying service the key goes as a Bearer token to the service's paths", function()
  local seen = {}
  local s = search.new(host(seen, { results = {} }), { key = "prk_s", bearer = true, url = "https://svc.test/v1/search",
    extract_url = "https://svc.test/v1/extract" })
  s:read({ "https://a.test" }, "x")
  spec.same({ seen[1].url, seen[1].headers.Authorization }, { "https://svc.test/v1/extract", "Bearer prk_s" })
end)

spec.run()
