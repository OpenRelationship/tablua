-- The TabPFN port: Prior Labs' hosted TabPFN-3.5 over its REST flow, an
-- optional batch calibrator (PROJECT.md 7.7).
--
--   local tabpfn = require("ports.tabpfn").new(host, { key = k })
--   local tokens, r = tabpfn:estimate{ operation = "predict", train_rows, test_rows, raw_columns }
--   local fitted, r = tabpfn:fit(train, labels, { model = "v3.5_default", cache = true })
--   local probas, r = tabpfn:predict(fitted, test)
--   local fitted, r = tabpfn:fit(train, numbers, { task = "regression" })
--   local qs, r = tabpfn:predict(fitted, test, { task = "regression", output = "quantiles", quantiles = { 0.5, 0.9 } })
--   local limits, r = tabpfn:limits()      -- each version's row, column and output limits, before any upload
--
-- A table is { columns = { name, ... }, rows = { { v, ... }, ... } }; a value
-- is a number, a string (text or category, sent as is), a boolean, or nil
-- (missing). labels is a list, one per row. probas is one list of class
-- probabilities per test row, classes in sorted order.
--
-- fit is prepare upload -> PUT X and y to the signed URLs -> fit; predict is
-- prepare upload -> PUT X -> predict. Only the calls to the API carry the key;
-- a signed URL is its own credential, so the PUTs carry only the headers the
-- API asked for. Every record is what the log keeps: step, status, seconds and
-- sizes, the signed URLs without their query strings, never the key.
local call = require("ports.call")
local json = require("ports.json")

local M = {}
local TabPFN = {}
TabPFN.__index = TabPFN

M.url = "https://api.priorlabs.ai"
M.model = "v3.5_default"
-- estimate_cost names versions, fit names checkpoints.
M.versions = { ["v3.5_default"] = "v3.5", ["v3.5-fast_default"] = "v3.5-fast", ["v3_default"] = "v3" }
-- each checkpoint's default ensemble size, so an estimate prices what a fit will run (Fast runs 4, not 8)
M.estimators = { ["v3.5_default"] = 8, ["v3.5-fast_default"] = 4, ["v3_default"] = 8 }

function M.new(host, opts)
  assert(host and host.fetch, "tabpfn needs a host with fetch")
  assert(opts and opts.key, "tabpfn needs a key")
  return setmetatable({ host = host, key = opts.key, url = opts.url or M.url, model = opts.model or M.model }, TabPFN)
end

-- CSV ------------------------------------------------------------------------

local function cell(v)
  -- v ~= v is NaN (checked before its type: tv-labs lua, in Moss, calls NaN userdata)
  if v == nil or v == json.null or v ~= v then return "" end
  if type(v) == "boolean" then return v and "1" or "0" end
  if type(v) == "number" then
    if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return ("%d"):format(v) end
    return ("%.10g"):format(v)
  end
  local s = tostring(v)
  if s:find('[,"\r\n]') or s:match("^%s") or s:match("%s$") then
    return '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

-- One CSV document, header first; a row may be shorter than the header
-- (its trailing values are missing).
function M.csv(columns, rows)
  local out = {}
  local head = {}
  for i, c in ipairs(columns) do head[i] = cell(c) end
  out[1] = table.concat(head, ",")
  for r, row in ipairs(rows) do
    local line = {}
    for i = 1, #columns do line[i] = cell(row[i]) end
    out[r + 1] = table.concat(line, ",")
  end
  return table.concat(out, "\n") .. "\n"
end

-- Calls ----------------------------------------------------------------------

local function now(host) return host.now and host.now() end

function TabPFN:post(step, path, payload, timeout, steps)
  local body, record = call.post(self.host, "tabpfn", self.url .. path, self.key, payload, timeout)
  record.step = step
  steps[#steps + 1] = record
  return body
end

-- A PUT to a signed URL: no key, only the headers the API required.
function TabPFN:put(step, info, body, steps)
  assert(type(info) == "table" and type(info.signed_urls) == "table" and info.signed_urls[1],
    "tabpfn gave no signed url for " .. step)
  local url = info.signed_urls[1]
  local headers = {}
  for k, v in pairs(info.required_headers or {}) do headers[k] = v end
  local record = { service = "tabpfn", step = step, url = url:match("^[^?]*"), bytes = #body, tries = 0 }
  local t0 = now(self.host)
  for try = 1, 2 do
    record.tries = try
    local ok, res = pcall(self.host.fetch, { method = "PUT", url = url, headers = headers, body = body, timeout = 120 })
    record.status = ok and res.status or nil
    if ok and res.status >= 200 and res.status < 300 then break end
    if try == 2 or (ok and res.status < 500 and res.status ~= 429) then
      if t0 then record.seconds = now(self.host) - t0 end
      steps[#steps + 1] = record
      error(setmetatable({ message = ("tabpfn upload %s failed: %s"):format(step,
        ok and ("status " .. res.status) or tostring(res)), record = record },
        { __tostring = function(e) return e.message end }), 0)
    end
  end
  if t0 then record.seconds = now(self.host) - t0 end
  steps[#steps + 1] = record
end

local function finish(host, record, t0)
  if t0 then record.seconds = now(host) - t0 end
  return record
end

-- The token charge of one operation, before any upload; free.
-- q = { operation = predict|cache_predict|thinking_fit|thinking_predict,
--       train_rows, test_rows, raw_columns, n_estimators?, model? }
function TabPFN:estimate(q)
  local steps = {}
  local t0 = now(self.host)
  local body = self:post("estimate", "/tabpfn/estimate_cost", {
    model_version = M.versions[q.model or self.model] or q.model or self.model,
    operation = q.operation or "predict", train_rows = q.train_rows, test_rows = q.test_rows or 0,
    raw_columns = q.raw_columns, n_estimators = q.n_estimators or M.estimators[q.model or self.model] or 8,
    thinking_effort = q.thinking_effort,
  }, 30, steps)
  return body.estimated_cost, finish(self.host, { service = "tabpfn", op = "estimate", steps = steps,
    tokens = body.estimated_cost, pricing_version = body.pricing_version }, t0)
end

-- Fit a classifier, or with opts.task "regression" a regressor (labels are numbers). opts: model, cache (fit_with_cache: later predicts reuse
-- the training set's attention state and cost less), n_estimators, thinking
-- (medium|high), categorical (0-based column indices), text (false drops the
-- text system).
function TabPFN:fit(train, labels, opts)
  opts = opts or {}
  assert(#labels == #train.rows, ("tabpfn fit: %d labels for %d rows"):format(#labels, #train.rows))
  local steps, t0 = {}, now(self.host)
  local prep = self:post("prepare_train", "/tabpfn/prepare_train_set_upload",
    { x_train_info = { format = "csv" }, y_train_info = { format = "csv" } }, 60, steps)
  local y = {}
  for i, v in ipairs(labels) do y[i] = { v } end
  self:put("x_train", prep.x_train_info, M.csv(train.columns, train.rows), steps)
  self:put("y_train", prep.y_train_info, M.csv({ "y" }, y), steps)
  local model = opts.model or self.model
  local config = { model_path = model, n_estimators = opts.n_estimators,
    fit_mode = opts.cache and "fit_with_cache" or nil,
    categorical_features_indices = opts.categorical and json.array(opts.categorical) or nil }
  local systems = { "preprocessing" }
  if opts.text ~= false then systems[2] = "text" end
  if opts.thinking then systems[#systems + 1] = "thinking" end
  local task = opts.task or "classification"
  local body = self:post("fit", "/tabpfn/fit", { train_set_upload_id = prep.train_set_upload_id,
    task = task, tabpfn_config = config, tabpfn_systems = json.array(systems),
    thinking_effort = opts.thinking }, opts.thinking and 900 or 300, steps)
  local fitted = assert(body.fitted_train_set_id, "tabpfn fit returned no fitted_train_set_id")
  return fitted, finish(self.host, { service = "tabpfn", op = "fit", task = task, model = model,
    cache = opts.cache or false,
    rows = #train.rows, columns = #train.columns, fitted = fitted, steps = steps }, t0)
end

-- One answer per test row against a fitted training set: class probabilities by default; with opts.task
-- "regression", opts.output "mean" (the default), "median" or "mode" (a number a row), "quantiles" (opts.quantiles,
-- one list a row in their order) or "full" (as the API gives it).
function TabPFN:predict(fitted, test, opts)
  opts = opts or {}
  local task = opts.task or "classification"
  local output = opts.output or (task == "regression" and "mean" or "probas")
  local params = { output_type = output }
  if output == "quantiles" then
    assert(type(opts.quantiles) == "table" and #opts.quantiles > 0, "tabpfn predict: quantiles needs opts.quantiles")
    params.quantiles = json.array(opts.quantiles)
  end
  local steps, t0 = {}, now(self.host)
  local prep = self:post("prepare_test", "/tabpfn/prepare_test_set_upload",
    { fitted_train_set_id = fitted, x_test_info = { format = "csv" } }, 60, steps)
  self:put("x_test", prep.x_test_info, M.csv(test.columns, test.rows), steps)
  local body = self:post("predict", "/tabpfn/predict", { test_set_upload_id = prep.test_set_upload_id,
    fitted_train_set_id = fitted, task_config = { task = task, predict_params = params } }, 600, steps)
  local probas = assert(body.prediction, "tabpfn predict returned no prediction")
  -- quantiles come one list per quantile; the port gives one list per row
  if output == "quantiles" and #probas == #opts.quantiles and type(probas[1]) == "table"
    and #probas[1] == #test.rows then
    local rows = {}
    for r = 1, #test.rows do
      rows[r] = {}
      for k = 1, #opts.quantiles do rows[r][k] = probas[k][r] end
    end
    probas = rows
  end
  if output ~= "full" then
    assert(#probas == #test.rows, ("tabpfn returned %d predictions for %d rows"):format(#probas, #test.rows))
  end
  local meta = body.metadata or {}
  return probas, finish(self.host, { service = "tabpfn", op = "predict", task = task, output = output,
    fitted = fitted, rows = #test.rows,
    cache_outcome = meta.cache_outcome, billing_model_version = meta.billing_model_version,
    package_version = meta.package_version, steps = steps }, t0)
end

-- Each model version's limits (rows, columns, classes, the rows a full regression output may have), read before an
-- upload so a training set too big for the plan is cut here, not refused there. Free, a GET with the key.
function TabPFN:limits()
  local t0 = now(self.host)
  local res = self.host.fetch({ method = "GET", url = self.url .. "/tabpfn/get_model_limits", timeout = 30,
    headers = { Authorization = "Bearer " .. self.key } })
  local record = { service = "tabpfn", op = "limits", status = res.status }
  if res.status ~= 200 then
    error(("tabpfn limits: status %s"):format(tostring(res.status)), 0)
  end
  return json.decode(res.body), finish(self.host, record, t0)
end

return M
