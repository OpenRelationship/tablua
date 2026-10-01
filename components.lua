-- The kit: Basecoat's components as Lua, so a page looks finished without a line of CSS. Each takes props (string
-- keys) and children (the list); any prop it does not use goes on its outer element as an attribute, so htmx
-- (post = "plants") and classes work everywhere.
--
--   layout     ui.container{...}  ui.stack{gap = 4, ...}  ui.row{gap = 2, ...}  ui.grid{cols = 3, ...}
--   actions    ui.button{"Add", variant = "primary|secondary|outline|ghost|link|destructive", size = "sm|lg|icon"}
--              ui.link_button{"Open", href = "x"}  ui.dialog{id, title, description, trigger = "Open", footer, ...}
--   content    ui.card{title, description, footer, ...}  ui.alert{title, variant = "destructive", ...}
--              ui.badge{"new", variant = "secondary|outline|destructive"}  ui.empty{title, description, ...}
--              ui.tabs{{"First", panel}, {"Second", panel}}  ui.data_table{columns = {...}, rows = {{...}}}
--              ui.kbd"K"  ui.progress{value = 40}  ui.skeleton{class = "h-4 w-32"}  ui.markdown(text)
--   forms      ui.form{post = "plants", ...}  ui.field{label, hint, error, input}  ui.input{name, label, ...}
--              ui.textarea{name, label}  ui.select{name, label, options = {"a", {"b", "B"}}}
--              ui.checkbox{name, label, checked}  ui.switch{name, label}
return function(ui)
  local markdown = require("shroomi.markdown")
  local el = ui.el

  -- the props a component does not read, as attributes on its element; class joined with its own
  local function attrs(props, used, class)
    local a = {}
    for k, v in pairs(props) do if not used[k] then a[k] = v end end
    if type(a.class) == "table" then a.class = table.concat(a.class, " ") end
    a.class = class and (a.class and class .. " " .. a.class or class) or a.class
    return a
  end

  local function with(a, children)
    for i = 1, ui.maxn(children) do a[i] = children[i] end
    return a
  end

  local function gap(n, fallback) return "gap-" .. tostring(n or fallback) end

  ui.component("container", function(p, c)
    return el("main", with(attrs(p, {}, "mx-auto w-full max-w-3xl p-6"), c))
  end)
  ui.component("stack", function(p, c)
    return el("div", with(attrs(p, { gap = true }, "flex flex-col " .. gap(p.gap, 4)), c))
  end)
  ui.component("row", function(p, c)
    return el("div", with(attrs(p, { gap = true }, "flex flex-wrap items-center " .. gap(p.gap, 2)), c))
  end)
  ui.component("grid", function(p, c)
    local cols = tonumber(p.cols) or 2
    return el("div", with(attrs(p, { gap = true, cols = true }, "grid grid-cols-1 md:grid-cols-" .. cols .. " " ..
      gap(p.gap, 4)), c))
  end)

  local function button(tag)
    return function(p, c)
      local a = attrs(p, { variant = true, size = true }, "btn")
      a["data-variant"], a["data-size"] = p.variant, p.size
      if tag == "button" and not a.type then a.type = (p.post or p.put or p.patch or p.delete or p.get) and "button" or "submit" end
      return el(tag, with(a, c))
    end
  end
  ui.component("button", button("button"))
  ui.component("link_button", button("a"))

  ui.component("card", function(p, c)
    local a = attrs(p, { title = true, description = true, footer = true }, "card")
    local parts = {}
    if p.title or p.description then
      parts[#parts + 1] = el("header", { p.title and el("h2", p.title), p.description and el("p", p.description) })
    end
    parts[#parts + 1] = el("section", with({}, c))
    if p.footer then parts[#parts + 1] = el("footer", { p.footer }) end
    return el("div", with(a, parts))
  end)

  ui.component("alert", function(p, c)
    local a = attrs(p, { title = true, variant = true }, "alert")
    a.role = a.role or "alert"
    a["data-variant"] = p.variant
    return el("div", with(a, { p.title and el("h2", p.title), el("section", with({}, c)) }))
  end)

  ui.component("badge", function(p, c)
    local a = attrs(p, { variant = true }, "badge")
    a["data-variant"] = p.variant
    return el("span", with(a, c))
  end)

  ui.component("empty", function(p, c)
    local a = attrs(p, { title = true, description = true }, "empty")
    return el("div", with(a, { el("header", { p.title and el("h3", p.title), p.description and el("p", p.description) }),
      #c > 0 and el("section", with({}, c)) or nil }))
  end)

  ui.component("kbd", function(p, c) return el("kbd", with(attrs(p, {}, "kbd"), c)) end)
  ui.component("skeleton", function(p) return el("div", attrs(p, {}, "skeleton")) end)
  ui.component("progress", function(p)
    local v = math.max(0, math.min(100, tonumber(p.value) or 0))
    local a = attrs(p, { value = true }, "progress")
    a.role, a["aria-valuenow"], a["aria-valuemin"], a["aria-valuemax"] = "progressbar", v, 0, 100
    return el("div", with(a, { el("div", { style = "width: " .. v .. "%" }) }))
  end)

  ui.component("markdown", function(p, c)
    local text = p.text or c[1] or ""
    return el("div", { class = p.class or "prose", ui.raw(markdown.html(text)) })
  end)

  ui.component("tabs", function(p, c)
    local id = p.id or "tabs"
    local nav, panels = {}, {}
    for i, t in ipairs(c) do
      local on = i == (tonumber(p.open) or 1)
      nav[i] = el("button", { type = "button", role = "tab", id = id .. "-tab-" .. i, ["aria-controls"] = id .. "-panel-" .. i,
        ["aria-selected"] = on and "true" or "false", tabindex = on and "0" or "-1", t[1] })
      panels[i] = el("div", { role = "tabpanel", id = id .. "-panel-" .. i, ["aria-labelledby"] = id .. "-tab-" .. i,
        tabindex = "-1", hidden = not on, t[2] })
    end
    local a = attrs(p, { id = true, open = true }, "tabs")
    a.id = id
    return el("div", with(a, { el("nav", with({ role = "tablist", ["aria-orientation"] = "horizontal" }, nav)), panels }))
  end)

  ui.component("data_table", function(p, c)
    local head, body = {}, {}
    for i, col in ipairs(p.columns or {}) do head[i] = el("th", { col }) end
    for i, row in ipairs(p.rows or {}) do
      local cells = {}
      for j, v in ipairs(row) do cells[j] = el("td", { v }) end
      body[i] = el("tr", cells)
    end
    local a = attrs(p, { columns = true, rows = true }, "table")
    return el("div", { class = "table-container", el("table", with(a, { el("thead", { el("tr", head) }),
      el("tbody", with(body, c)) })) })
  end)

  ui.component("dialog", function(p, c)
    local id = p.id or "dialog"
    local a = attrs(p, { id = true, title = true, description = true, trigger = true, footer = true }, "dialog")
    a.id, a["data-shroomi-dialog"] = id, true
    local box = el("div", {
      (p.title or p.description) and el("header", { p.title and el("h2", p.title), p.description and el("p", p.description) }),
      el("section", with({}, c)),
      p.footer and el("footer", { p.footer }),
      el("button", { type = "button", ["aria-label"] = "Close", ["data-close"] = id, "×" }),
    })
    return {
      p.trigger and el("button", { type = "button", class = "btn", ["data-variant"] = "outline", ["data-open"] = id, p.trigger }),
      el("dialog", with(a, { box })),
    }
  end)

  -- forms
  ui.component("form", function(p, c)
    return el("form", with(attrs(p, {}, "form grid gap-4"), c))
  end)

  ui.component("field", function(p, c)
    local a = attrs(p, { label = true, hint = true, error = true, ["for"] = true }, "field")
    if p.error then a["data-invalid"] = "true" end
    return el("div", with(a, {
      p.label and el("label", { ["for"] = p["for"], p.label }),
      c,
      p.hint and el("p", { p.hint }),
      p.error and el("p", { role = "alert", p.error }),
    }))
  end)

  local function control(tag, class)
    return function(p, c)
      local a = attrs(p, { label = true, hint = true, error = true, options = true }, class)
      a.id = a.id or a.name
      if p.error then a["aria-invalid"] = "true" end
      local node
      if tag == "select" then
        local opts = {}
        for i, o in ipairs(p.options or {}) do
          local value, text = o, o
          if type(o) == "table" then value, text = o[1], o[2] or o[1] end
          opts[i] = el("option", { value = value, selected = tostring(value) == tostring(p.value), text })
        end
        a.value = nil
        node = el("select", with(a, opts))
      elseif tag == "textarea" then
        local text = a.value
        a.value = nil
        node = el("textarea", with(a, { text }))
      else
        node = el("input", a)
      end
      if not (p.label or p.hint or p.error) then return node end
      return ui.field{ label = p.label, hint = p.hint, error = p.error, ["for"] = a.id, node }
    end
  end
  ui.component("input", control("input", "input"))
  ui.component("textarea", control("textarea", "textarea"))
  ui.component("select", control("select", "select"))

  local function box(role)
    return function(p)
      local a = attrs(p, { label = true }, "input")
      a.type, a.id = "checkbox", a.id or a.name
      if role then a.role = role end
      return el("label", { class = "label gap-3", el("input", a), p.label })
    end
  end
  ui.component("checkbox", box(nil))
  ui.component("switch", box("switch"))
end
