-- Unit cases for the CSV the TabPFN port uploads, and its calls against a fake host: regression, quantiles, limits
-- and the estimate's ensemble size.
local spec = require("spec")
local json = require("ports.json")
local tabpfn = require("ports.tabpfn")

spec.test("numbers keep integers whole and floats to ten digits", function()
  spec.eq(tabpfn.csv({ "a", "b", "c" }, { { 3, 0.1, 1 / 3 } }), "a,b,c\n3,0.1,0.3333333333\n")
end)

spec.test("text with commas, quotes, newlines or edge spaces is quoted", function()
  spec.eq(tabpfn.csv({ "t" }, { { 'say "hi", then' }, { "two\nlines" }, { " pad" }, { "plain" } }),
    't\n"say ""hi"", then"\n"two\nlines"\n" pad"\nplain\n')
end)

spec.test("missing values, NaN and JSON null are empty cells; booleans are 1 and 0", function()
  spec.eq(tabpfn.csv({ "a", "b", "c", "d" }, { { nil, 0 / 0, json.null, true } }), "a,b,c,d\n,,,1\n")
  spec.eq(tabpfn.csv({ "a", "b" }, { { false } }), "a,b\n0,\n")
end)
-- a host that answers the API's routes and keeps what each call sent
local function fake(prediction)
  local sent = {}
  local signed = { signed_urls = { "https://store.test/x?sig=1" }, required_headers = {} }
  local answers = {
    ["/tabpfn/prepare_train_set_upload"] = { train_set_upload_id = "t1", x_train_info = signed, y_train_info = signed },
    ["/tabpfn/fit"] = { fitted_train_set_id = "f1" },
    ["/tabpfn/prepare_test_set_upload"] = { test_set_upload_id = "u1", x_test_info = signed },
    ["/tabpfn/predict"] = { prediction = prediction, metadata = {} },
    ["/tabpfn/estimate_cost"] = { estimated_cost = 10000 },
    ["/tabpfn/get_model_limits"] = { ["v3.5"] = { train_set_max_rows = 1000000 } },
  }
  local host = { fetch = function(req)
    local path = req.url:match("^https://api%.priorlabs%.ai(/[^?]*)")
    if not path then return { status = 200, body = "" } end
    sent[path] = { method = req.method, body = req.body and req.body ~= "" and json.decode(req.body) or nil,
      auth = req.headers and req.headers.Authorization }
    return { status = 200, body = json.encode(answers[path]) }
  end }
  return tabpfn.new(host, { key = "k" }), sent
end

local train = { columns = { "a" }, rows = { { 1 }, { 2 }, { 3 } } }

spec.test("a regression fit says so, and a quantiles predict gives one list a row", function()
  local t, sent = fake({ { 1, 2 }, { 5, 6 } })
  local fitted = t:fit(train, { 1.5, 2.5, 3.5 }, { task = "regression" })
  spec.eq(sent["/tabpfn/fit"].body.task, "regression")
  local qs = t:predict(fitted, { columns = { "a" }, rows = { { 4 }, { 5 } } },
    { task = "regression", output = "quantiles", quantiles = { 0.5, 0.9 } })
  local cfg = sent["/tabpfn/predict"].body.task_config
  spec.eq(cfg.task, "regression")
  spec.eq(cfg.predict_params.output_type, "quantiles")
  spec.same(cfg.predict_params.quantiles, { 0.5, 0.9 })
  spec.same(qs, { { 1, 5 }, { 2, 6 } })
end)

spec.test("a classifier predicts probabilities by default, as before", function()
  local t, sent = fake({ { 0.2, 0.8 } })
  local p = t:predict("f1", { columns = { "a" }, rows = { { 1 } } })
  spec.eq(sent["/tabpfn/predict"].body.task_config.predict_params.output_type, "probas")
  spec.same(p, { { 0.2, 0.8 } })
end)

spec.test("limits is a GET with the key; an estimate prices each checkpoint's own ensemble", function()
  local t, sent = fake({})
  local limits = t:limits()
  spec.eq(sent["/tabpfn/get_model_limits"].method, "GET")
  spec.eq(sent["/tabpfn/get_model_limits"].auth, "Bearer k")
  spec.eq(limits["v3.5"].train_set_max_rows, 1000000)
  t:estimate({ train_rows = 10, raw_columns = 3, model = "v3.5-fast_default" })
  spec.eq(sent["/tabpfn/estimate_cost"].body.n_estimators, 4)
  t:estimate({ train_rows = 10, raw_columns = 3 })
  spec.eq(sent["/tabpfn/estimate_cost"].body.n_estimators, 8)
end)


spec.test("a spent daily limit is asked once, never retried, and the port asks no more", function()
  local calls, slept = 0, 0
  local host = { sleep = function(n) slept = slept + n end, fetch = function()
    calls = calls + 1
    return { status = 429, body = json.encode({ message = "Daily usage limit reached. Resets at 2026-10-06 00:00:00 UTC." }) }
  end }
  local t = tabpfn.new(host, { key = "k" })
  local ok, err = pcall(t.estimate, t, { train_rows = 10, raw_columns = 3 })
  spec.ok(not ok and err.spent)
  spec.eq(calls, 1)
  spec.eq(slept, 0)
  ok = pcall(t.estimate, t, { train_rows = 10, raw_columns = 3 })
  spec.ok(not ok)
  spec.eq(calls, 1)
end)

spec.test("a moment's 429 is still retried", function()
  local calls = 0
  local host = { sleep = function() end, fetch = function()
    calls = calls + 1
    if calls < 3 then return { status = 429, body = json.encode({ message = "too many requests" }) } end
    return { status = 200, body = json.encode({ estimated_cost = 5 }) }
  end }
  spec.eq(tabpfn.new(host, { key = "k" }):estimate({ train_rows = 1, raw_columns = 1 }), 5)
  spec.eq(calls, 3)
end)

spec.run()
