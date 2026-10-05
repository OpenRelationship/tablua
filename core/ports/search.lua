-- The search port: web search on Parallel's Search API, turbo mode by default
-- (about 200 ms, $1 per 1,000 requests; English and Japanese queries only).
--
--   local search = require("ports.search").new(host, { key = k, mode = "turbo" })
--   local results, record = search:search(objective, { "keyword query", ... })
--   local results, record = search:read({ url, ... }, objective)   the pages as they are now (Parallel's Extract),
--                                                                    fetched fresh unless read in the last 10 minutes
--
-- results is a list of { url, title, date, excerpts = { ... } }, best first.
-- The record is what the log keeps: the call's record plus the search id and
-- mode, never the key. Parallel reads the key from x-api-key, not Bearer; with
-- bearer = true it goes as a Bearer token (a service that proxies the search API).
local call = require("ports.call")
local json = require("ports.json")

local M = {}
local Search = {}
Search.__index = Search

M.url = "https://api.parallel.ai/v1/search"
M.extract_url = "https://api.parallel.ai/v1/extract"
M.fresh = 600   -- seconds a page read may be cached (Parallel's least)
M.mode = "turbo"

function M.new(host, opts)
  assert(host and host.fetch, "search needs a host with fetch")
  assert(opts and opts.key, "search needs a key")
  return setmetatable({ host = host, key = opts.key, url = opts.url or M.url, mode = opts.mode or M.mode,
    extract_url = opts.extract_url or M.extract_url, bearer = opts.bearer }, Search)
end

-- opts: mode (turbo, fast, basic, advanced) and max_chars_total, per call.
function Search:search(objective, queries, opts)
  opts = opts or {}
  assert(type(queries) == "table" and #queries > 0, "search needs at least one query")
  local mode = opts.mode or self.mode
  local payload = { objective = objective, search_queries = json.array(queries), mode = mode,
    max_chars_total = opts.max_chars_total }
  local reply, record = call.post(self.host, "parallel", self.url,
    self.bearer and self.key or { header = "x-api-key", value = self.key }, payload)
  record.search_id, record.mode = reply.search_id, mode
  local results = {}
  for i, r in ipairs(reply.results or {}) do
    local date = r.publish_date
    results[i] = { url = r.url, title = r.title, date = date ~= json.null and date or nil,
      excerpts = r.excerpts or {} }
  end
  return results, record
end

local function pages(reply)
  local results = {}
  for i, r in ipairs(reply.results or {}) do
    local date = r.publish_date
    results[i] = { url = r.url, title = r.title ~= json.null and r.title or nil,
      date = date ~= json.null and date or nil, excerpts = r.excerpts or {} }
  end
  return results
end

-- Pages read now, with the parts that answer the objective; opts.timeout is the seconds to wait (60). A page that could not be read comes back with its
-- error in place of excerpts.
function Search:read(urls, objective, opts)
  opts = opts or {}
  assert(type(urls) == "table" and #urls > 0, "read needs at least one url")
  local payload = { urls = json.array(urls), objective = objective, max_chars_total = opts.max_chars_total or 6000,
    advanced_settings = { fetch_policy = { max_age_seconds = M.fresh } } }
  local reply, record = call.post(self.host, "parallel", self.extract_url,
    self.bearer and self.key or { header = "x-api-key", value = self.key }, payload, opts.timeout or 60)
  record.extract_id = reply.extract_id
  local results = pages(reply)
  for _, e in ipairs(reply.errors or {}) do
    results[#results + 1] = { url = e.url, error = tostring(e.error_type) .. (e.http_status_code ~= json.null
      and e.http_status_code and (" " .. e.http_status_code) or ""), excerpts = {} }
  end
  return results, record
end

return M
