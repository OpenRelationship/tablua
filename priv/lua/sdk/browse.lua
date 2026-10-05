-- browse: the built-in steps that use the app's own pages as its person does (Arock eval, 2026-10-03). A feature
-- written in them tests the page itself, not code beside it: the page is what is tested, used and shipped, so a
-- green test is a page that works. Every request is the app's own (the run's scratch databases, its modules loaded
-- afresh as each request of the person's has them), and a press is followed by the page opened again, so what was
-- kept only in memory is gone, as it would be for the person.
--
--   When I open the page                 the app's first page, ui/index.lui (or: I open the "/list" page)
--   When I type "Fern" into "Plant name" a field of a form, by its label, placeholder or name
--   When I press "Add"                   a button: a form's sends the form; a row's sends its row
--   When I press "Water" for "Fern"      the row's button whose row is Fern's
--   Then I see "Fern"                    I do not see "Fern"      I see "Ivy" before "Fern"
--   Then I see "watered" for "Fern"      the row that shows Fern (its tr, li, p or card) shows watered
-- A value "today", "today+7" or "today-1" is that day (2026-10-10).
local M = {}

local ENT = { quot = '"', amp = "&", lt = "<", gt = ">", apos = "'", ["#39"] = "'", nbsp = " " }
local function unescape(s) return (string.gsub(s, "&(#?%w+);", function(e) return ENT[e] or ("&" .. e .. ";") end)) end

local function attrs(tag)
  local out = {}
  for k, v in string.gmatch(tag, '([%w_:%-]+)="([^"]*)"') do out[string.lower(k)] = unescape(v) end
  for k in string.gmatch(tag, "%s([%w_:%-]+)[%s>/]") do if out[k] == nil then out[k] = "" end end
  return out
end

-- what a person reads: no head, styles or scripts, each tag a space
function M.text(html)
  local s = string.gsub(html, "<head.-</head>", " ")
  s = string.gsub(s, "<style.-</style>", " ")
  s = string.gsub(s, "<script.-</script>", " ")
  s = string.gsub(s, "<[^>]*>", " ")
  return (string.gsub(unescape(s), "%s+", " "))
end

-- what names a field, in the order a person reads it: its label, placeholder, name; the missing ones left out
local function says(...)
  local out = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v and v ~= "" then out[#out + 1] = v end
  end
  return out
end

local function low(s) return string.lower(string.gsub(s or "", "^%s*(.-)%s*$", "%1")) end

-- the page's forms (action, fields with what names them, buttons) and the buttons outside them (action, vals, text)
function M.parse(html)
  local labels, forms, buttons = {}, {}, {}
  for a, inner in string.gmatch(html, "<label([^>]*)>(.-)</label>") do
    local f = attrs(a)["for"]
    if f then labels[f] = M.text(inner) end
  end
  local outside = string.gsub(html, "<form([^>]*)>(.-)</form>", function(a, inner)
    local form = { action = attrs(a)["hx-post"] or attrs(a)["action"], fields = {}, buttons = {} }
    for tag in string.gmatch(inner, "<(input[^>]*)>") do
      local t = attrs(tag)
      if t.name then
        form.fields[#form.fields + 1] = { name = t.name, type = t.type or "text", value = t.value,
          says = says(labels[t.id or ""], t.placeholder, t["aria-label"], t.name) }
      end
    end
    for tag in string.gmatch(inner, "<(textarea[^>]*)>") do
      local t = attrs(tag)
      if t.name then form.fields[#form.fields + 1] = { name = t.name, type = "text", says = says(labels[t.id or ""], t.placeholder, t.name) } end
    end
    for tag, body in string.gmatch(inner, "<(select[^>]*)>(.-)</select>") do
      local t = attrs(tag)
      local first = string.match(body, '<option[^>]-value="([^"]*)"')
      if t.name then form.fields[#form.fields + 1] = { name = t.name, type = "select", value = first, says = says(labels[t.id or ""], t.name) } end
    end
    for _, body in string.gmatch(inner, "<button([^>]*)>(.-)</button>") do form.buttons[#form.buttons + 1] = M.text(body) end
    forms[#forms + 1] = form
    return " "
  end)
  for a, body in string.gmatch(outside, "<button([^>]*)>(.-)</button>") do
    local t = attrs(a)
    if t["hx-post"] or t["hx-get"] then
      local ok, vals = pcall(json.decode, t["hx-vals"] or "{}")
      buttons[#buttons + 1] = { text = M.text(body), action = t["hx-post"] or t["hx-get"],
        method = t["hx-post"] and "POST" or "GET", vals = ok and type(vals) == "table" and vals or {} }
    end
  end
  return { forms = forms, buttons = buttons }
end

local function value(v)
  local sign, n = string.match(v, "^today([%+%-])(%d+)$")
  if v == "today" or sign then
    local d = date.now() + (sign == "-" and -1 or 1) * (tonumber(n) or 0) * 86400
    return date.day(d)
  end
  return v
end

-- one request to the app, as the node makes it: its page by path, modules loaded afresh
local scope = "/home"
local function request(method, path, query, form)
  local p = string.match(path, "^[^?]*")
  local name = p == "/" and "index" or string.gsub(string.gsub(p, "^/", ""), "/$", "")
  -- an org page (org and Lua) before a .lui one, as the node serves them (Moss.Computer.Pages)
  local file = scope .. "/ui/" .. name .. ".org"
  if not fs.read(file) then file = scope .. "/ui/" .. name .. ".lui" end
  if not fs.read(file) then
    local base = string.gsub(string.gsub(file, "^/home/", ""), "%.lui$", "")
    error(("there is no page %s.org or %s.lui yet for %s: write it"):format(base, base, p), 0)
  end
  if __fresh_modules then __fresh_modules() end
  -- each of the node's requests is a fresh run: what a page left in a global is gone by the next
  local before = {}
  for k in pairs(_G) do before[k] = true end
  local status, _, body = __serve({ method = method, path = p, query = query or {}, form = form or {},
    headers = method == "POST" and { ["hx-request"] = "true" } or {}, page = file })
  for k in pairs(_G) do if not before[k] then rawset(_G, k, nil) end end
  return status, tostring(body or "")
end

local function open(w, path)
  local status, body = request("GET", path or w.path or "/")
  w.path, w.html, w.typed = path or w.path or "/", body, {}
  if status >= 400 then error(("%s answered %d: %s"):format(w.path, status, string.sub(M.text(body), 1, 300)), 0) end
  w.page = M.parse(body)
end

local function seen(w)
  if not w.html then open(w) end
  return M.text(w.html)
end

local function shows(w) return string.sub((string.gsub(seen(w), "^%s+", "")), 1, 400) end

local function names(field)
  return field.says[1] or field.name
end

-- send: the action against the page's path (?do=add on /list is /list?do=add), then the page opened again
local function send(w, method, action, form)
  local query = {}
  for k, v in string.gmatch(string.match(action or "", "%?(.*)$") or "", "([^&=]+)=([^&]*)") do query[k] = v end
  local status, body = request(method, w.path, query, form)
  if status >= 400 then
    error(("pressing it answered %d: %s"):format(status, string.sub(M.text(body), 1, 300)), 0)
  end
  open(w, w.path)
end

-- the steps, for the features of scope (/home, or /home/apps/<app>), whose pages are its ui/
function M.install(test, at)
  -- what the run's scenarios typed so far, and what this scenario typed (w.mine): a check that misses a value only an
  -- earlier scenario typed is told so, since each scenario starts from an empty app (the notes and birthdays evals,
  -- 2026-10-04: two runs of 150 steps rewrote right pages against scenarios that used what another one made)
  local ever = {}
  local function unmade(w, ...)
    for _, v in ipairs({ ... }) do
      v = value(v)
      if ever[v] and not (w.mine or {})[v] then
        return ('; "%s" was typed only in an earlier scenario, and each scenario starts from an empty app, so this '
          .. 'one adds it itself'):format(v)
      end
    end
    return ""
  end
  scope = at or "/home"
  test.step("I open the page", function(w) open(w, "/") end)
  test.step("I open the app", function(w) open(w, "/") end)
  test.step("I open the page again", function(w) open(w, w.path or "/") end)
  test.step("I open the {string} page", function(w, path)
    open(w, string.sub(path, 1, 1) == "/" and path or ("/" .. path))
  end)

  test.step("I type {string} into {string}", function(w, v, field)
    if not w.page then open(w) end
    local want = low(field)
    for fi, form in ipairs(w.page.forms) do
      for _, f in ipairs(form.fields) do
        for _, s in ipairs(f.says) do
          if (low(s) == want or string.find(low(s), want, 1, true)) then
            w.typed[fi] = w.typed[fi] or {}
            w.typed[fi][f.name] = value(v)
            ever[value(v)], w.mine = true, w.mine or {}
            w.mine[value(v)] = true
            return
          end
        end
      end
    end
    local all = {}
    for _, form in ipairs(w.page.forms) do for _, f in ipairs(form.fields) do all[#all + 1] = '"' .. names(f) .. '"' end end
    error(('no field "%s" on the page; its fields: %s'):format(field, #all > 0 and table.concat(all, ", ") or "none"), 0)
  end)

  -- the innermost rows (a table row, list item, paragraph, card or block) that show `row`, in that order; one with
  -- another of its kind inside is left to that one
  local function rows(html, row)
    local out = {}
    for _, tag in ipairs({ "tr", "li", "p", "article", "section", "div" }) do
      for i in string.gmatch(html, "()<" .. tag .. "[%s>]") do
        local _, j = string.find(html, "</" .. tag .. ">", i, true)
        local block = string.sub(html, i, j or #html)
        if string.find(M.text(block), row, 1, true) and not string.find(block, "<" .. tag .. "[%s>]", 2) then
          out[#out + 1] = block
        end
      end
    end
    return out
  end

  local function press(w, label, row)
    if not w.page then open(w) end
    local want = low(label)
    if not row then
      for fi, form in ipairs(w.page.forms) do
        for _, b in ipairs(form.buttons) do
          if low(b) == want then
            local data = {}
            for _, f in ipairs(form.fields) do
              if f.value and f.type ~= "checkbox" then data[f.name] = f.value end
            end
            for k, v in pairs(w.typed[fi] or {}) do data[k] = v end
            return send(w, "POST", form.action, data)
          end
        end
      end
    end
    for _, b in ipairs(w.page.buttons) do
      if low(b.text) == want then
        local hit = not row
        for _, v in pairs(b.vals) do hit = hit or low(tostring(v)) == low(row) end
        if hit then return send(w, b.method, b.action, b.vals) end
      end
    end
    -- the row's button by where it is: the innermost row that shows `row` holds a button of that label (its vals
    -- may carry only an id)
    local shown = false
    if row then
      for _, block in ipairs(rows(w.html or "", row)) do
        shown = true
        for a, body in string.gmatch(block, "<button([^>]*)>(.-)</button>") do
          local t = attrs(a)
          if low(M.text(body)) == want and (t["hx-post"] or t["hx-get"]) then
            local ok, vals = pcall(json.decode, t["hx-vals"] or "{}")
            return send(w, t["hx-post"] and "POST" or "GET", t["hx-post"] or t["hx-get"],
              ok and type(vals) == "table" and vals or {})
          end
        end
      end
    end
    local all = {}
    for _, form in ipairs(w.page.forms) do for _, b in ipairs(form.buttons) do all[#all + 1] = '"' .. b .. '"' end end
    for _, b in ipairs(w.page.buttons) do all[#all + 1] = '"' .. b.text .. '"' end
    if row and not shown then
      error(('nothing on the page shows "%s", so it has no "%s" for it: each scenario starts from an empty app, so '
        .. 'the scenario makes "%s" itself before it uses it%s; the page shows: %s'):format(row, label, row,
        unmade(w, row), shows(w)), 0)
    end
    error(('no button "%s"%s on the page; its buttons: %s'):format(label, row and (' for "' .. row .. '"') or "",
      #all > 0 and table.concat(all, ", ") or "none"), 0)
  end
  test.step("I press {string}", function(w, label) press(w, label) end)
  test.step("I press {string} for {string}", function(w, label, row) press(w, label, row) end)

  test.step("I see {string}", function(w, s)
    if not string.find(seen(w), value(s), 1, true) then
      error(('the page does not show "%s"%s; it shows: %s'):format(value(s), unmade(w, s), shows(w)), 0)
    end
  end)
  -- the row (a table row, list item, paragraph or card) that shows `row` also shows `s`
  test.step("I see {string} for {string}", function(w, s, row)
    if not w.html then open(w) end
    local want = value(s)
    -- the first block that shows more than the name: a name in a <p> of its own inside its row's <div> is its cell,
    -- not its row (a plants run rewrote a right page seventy steps against "the row of Fern shows: Fern", 2026-10-05)
    local found, cell
    for _, block in ipairs(rows(w.html, row)) do
      local t = (string.gsub(string.gsub(M.text(block), "^%s+", ""), "%s+$", ""))
      if t ~= row then found = t; break end
      cell = cell or t
    end
    found = found or cell
    if found then
      if string.find(found, want, 1, true) then return end
      error(('the row of "%s" does not show "%s"; it shows: %s'):format(row, want, found), 0)
    end
    error(('no row shows "%s"%s; the page shows: %s'):format(row, unmade(w, row), shows(w)), 0)
  end)
  -- the same check in the words a feature often has
  local function see(w, s)
    if not string.find(seen(w), value(s), 1, true) then
      error(('the page does not show "%s"; it shows: %s'):format(value(s), shows(w)), 0)
    end
  end
  test.step("I see {string} in the list", see)
  test.step("I should see {string}", see)
  test.step("I do not see {string}", function(w, s)
    if string.find(seen(w), value(s), 1, true) then error(('the page still shows "%s"'):format(value(s)), 0) end
  end)
  test.step("I see {string} before {string}", function(w, a, b)
    local t = seen(w)
    local i, j = string.find(t, a, 1, true), string.find(t, b, 1, true)
    if not i or not j then
      error(('the page does not show both "%s" and "%s"%s; it shows: %s'):format(a, b, unmade(w, a, b), shows(w)), 0)
    end
    if i > j then error(('"%s" comes after "%s" on the page: %s'):format(a, b, shows(w)), 0) end
  end)
end

-- browse is used through its steps, never called: code that asks it for anything else is told the steps (an agent
-- wrote browse.navigate("/") in a step file of its own and spent 20 steps on it)
local STEPS = 'I open the page, I type "x" into "field", I press "button", I press "button" for "row", I see "x", '
  .. 'I see "x" for "row", I do not see "x", I see "a" before "b", I open the page again'
return setmetatable(M, { __index = function(_, k)
  error(("browse has no %s: the page is used through the computer's own steps, written in the feature (%s); a step "
    .. "file never requires browse"):format(tostring(k), STEPS), 2)
end })
