-- .lui pages: compiled to Shroomi's elements, escaped, class-checked, with actions wired in one place.
local spec = require("mono.spec")
local lui = require("shroomi.lui")
local page = require("shroomi.page")

local function get(path, query) return { method = "GET", path = path or "/", query = query or {}, form = {}, headers = {} } end
local function post(path, name, form)
  return { method = "POST", path = path, query = { ["do"] = name }, form = form or {}, headers = { ["hx-request"] = "true" } }
end
local function body(html) return string.match(html, "<body[^>]*>(.-)</body>") end

-- the plants a page keeps, in place of a database
STORE = {}

local PLANTS = [[
<lua>
  page.title = "Plants"
  function post.water(req) STORE[req.form.name] = "watered" end
  function post.only(req) STORE[req.form.name] = "watered"; return "#plants" end
</lua>
<card title="Plants">
  <ul id="plants">
    {% for _, name in ipairs({ "Fern", "<script>alert(1)</script>" }) do %}
      <li class="flex gap-2">{{ name }} {{ STORE[name] or "dry" }}
        <button size="sm" post="water" vals={{ { name = name } }}>Water</button>
      </li>
    {% end %}
  </ul>
</card>
]]

spec.test("a page renders with its title, its text escaped and its kit components drawn", function()
  STORE = {}
  local html = lui.answer(PLANTS, "ui/index.lui", get())
  spec.ok(string.find(html, "<title>Plants</title>", 1, true), "title")
  spec.ok(string.find(html, '<div class="card"><header><h2>Plants</h2></header>', 1, true), "card")
  spec.ok(string.find(html, "&lt;script&gt;alert(1)&lt;/script&gt; dry", 1, true), "escaped")
  spec.ok(not string.find(html, "<script>alert", 1, true), "no script")
end)

spec.test("an action is named once: the element posts to it, and the page comes back to be merged", function()
  STORE = {}
  local html = lui.answer(PLANTS, "ui/index.lui", get("/plants"))
  spec.ok(string.find(html, 'data-morph data-size="sm" hx-post="plants?do=water" ' ..
    'hx-vals="{&quot;name&quot;:&quot;Fern&quot;}"', 1, true), "the button's address and vals")
  html = lui.answer(PLANTS, "ui/index.lui", post("/plants", "water", { name = "Fern" }))
  spec.ok(string.find(html, "^<!doctype html>"), "a whole page")
  spec.ok(string.find(html, "Fern watered", 1, true), "Fern shows watered")
  html = lui.answer(PLANTS, "ui/index.lui", get("/plants", { sort = "a b" }))
  spec.ok(string.find(html, 'hx-post="plants?sort=a%20b&amp;do=water"', 1, true), "the page's own query is kept")
end)

spec.test("an action that returns #id sends that element alone, with its styles", function()
  STORE = {}
  local html = lui.answer(PLANTS, "ui/index.lui", post("/", "only", { name = "Fern" }))
  spec.ok(string.find(html, '<body data-part="plants" ', 1, true), "names the part")
  spec.eq(string.match(body(html), "^<ul id=\"plants\">"), '<ul id="plants">')
  spec.ok(not string.find(html, '<div class="card">', 1, true), "the card is not sent")
  spec.ok(string.find(html, ".gap-2{", 1, true), "its styles")
  spec.ok(string.find(html, "Fern watered", 1, true))
end)

spec.test("what an action returns is the render's result, and an unknown action is a 404", function()
  local form = [[
<lua>
  function post.save(req)
    if req.form.email == "" then return { errors = { email = "An address, please." } } end
    return { saved = true }
  end
</lua>
<form post="save">
  <input name="email" label="Email" error={{ result and result.errors and result.errors.email }}/>
  {% if result and result.saved then %}<alert title="Saved"/>{% end %}
  <button>Save</button>
</form>
]]
  local html = lui.answer(form, "ui/s.lui", post("/s", "save", { email = "" }))
  spec.ok(string.find(html, "An address, please.", 1, true), "the error shows")
  html = lui.answer(form, "ui/s.lui", post("/s", "save", { email = "a@b.c" }))
  spec.ok(string.find(html, "Saved", 1, true) and not string.find(html, "An address", 1, true), "saved")
  local res = lui.answer(form, "ui/s.lui", post("/s", "nope"))
  spec.eq(res.status, 404)
end)

spec.test("what the page read before an action is read again after it", function()
  STORE = {}
  local src = "<lua>\n  local n = STORE.n or 0\n  function post.inc() STORE.n = (STORE.n or 0) + 1 end\n</lua>\n<p>{{ n }}</p>"
  spec.eq(body(lui.answer(src, "ui/n.lui", post("/", "inc"))), "<p>1</p>")
end)

spec.test("values: {{ }} alone is the value itself, raw is raw, entities read as text", function()
  local src = [[
<p class="text-sm {{ cls }}" title="{{ n }}" hidden={{ false }}>{{{ "<b>bold</b>" }}} &amp; a &lt; b, a < b</p>
<input type="checkbox" checked="{{ true }}"><input name="x" disabled={{ nil }}>
<pre>  two
  lines</pre>
]]
  _G.cls, _G.n = "font-medium", 3
  local html = body(lui.answer(src, "ui/v.lui", get()))
  spec.eq(html, '<p class="text-sm font-medium" title="3"><b>bold</b> &amp; a &lt; b, a &lt; b</p>' ..
    '<input checked class="input" type="checkbox"><input class="input" id="x" name="x"><pre>  two\n  lines</pre>')
end)

spec.test("{{ e }} alone in a tag names a bare attribute, or none", function()
  local src = '<p>{% for _, v in ipairs({ "a", "b" }) do %}<option value="{{ v }}" {{ v == "b" and "selected" }}>{{ v }}</option>{% end %}</p>'
  spec.eq(body(lui.answer(src, "ui/f.lui", get())), '<p><option value="a">a</option><option selected value="b">b</option></p>')
end)

spec.test("components the page makes are tags, and ui is at hand", function()
  local src = [[
<lua>
  ui.component("plant", function(p) return ui.li{ class = "font-medium", p.name } end)
</lua>
<ul><plant name="Fern"/><plant name="Moss"/></ul>
]]
  spec.eq(body(lui.answer(src, "ui/c.lui", get())),
    '<ul><li class="font-medium">Fern</li><li class="font-medium">Moss</li></ul>')
end)

local function refused(src, want)
  local ok, why = lui.compile(src, "ui/x.lui")
  spec.eq(ok, nil, "compiled: " .. src)
  spec.ok(string.find(why, want, 1, true), "wanted «" .. want .. "», got «" .. tostring(why) .. "»")
end

spec.test("check names the file, the line and what is wrong", function()
  refused('<div>\n  <p class="p-4 glow-9000">x</p>\n</div>', 'ui/x.lui:2: no class "glow-9000"')
  refused("<div>\n<blink>x</blink></div>", "ui/x.lui:2: <blink> is no element")
  refused("<div>\n<script>x</script></div>", "ui/x.lui:2: no <script> on a page")
  refused('<button post="water">W</button>', 'ui/x.lui:1: post="water" names no action: define function post.water(req)')
  refused("<div>\n  <ul>\n</div>", "ui/x.lui:3: </div> closes <ul>, opened on line 2")
  refused("<div>\n  <p>x</p>", "ui/x.lui:1: <div> is never closed")
  spec.eq(body(lui.answer('<p>a<br></br><icon name="leaf">b</p>', "ui/b.lui", get())):gsub("<svg.-</svg>", "svg"), "<p>a<br>svgb</p>")
  refused('<p onclick="x()">x</p>', "ui/x.lui:1: onclick: a page's own script never runs")
  refused("<p>{{ x }</p>", "{{ is never closed with }}")
  refused("<p title={{{ x }}}>x</p>", "{{{ }}} is for text, never an attribute")
  refused("<p>a</p>\n<lua>x = 1</lua>", "ui/x.lui:2: a page has one <lua> block, at its top")
end)

spec.test("the habits of other template languages are answered with the Lua they should be", function()
  refused("<ui.card title=\"x\">y</ui.card>", "a kit component is a tag by its name: <card>, not <ui.card>")
  refused("<html><body><p>x</p></body></html>", "a page is its body")
  refused("<select name=\"s\"><option {% if x then %}selected{% end %}>a</option></select>", "a statement never goes inside a tag")
  refused('<p class="h-[calc(100vh-2rem)] min-h-[80px]">x</p>', "(brackets hold only a length")
  spec.eq(body(lui.answer('<p class="p-2 {% if 1 > 0 then %}font-medium{% end %}" rows=5>x</p>', "ui/a.lui", get())),
    '<p class="p-2 font-medium" rows="5">x</p>')
  refused('<p class="p-2 {% if 1 then %}glow{% end %}">x</p>', 'no class "glow"')
  refused("<ul>{% for p in plants %}<li/>{% endfor %}</ul>", "a Lua loop opens with do")
  refused("<ul>{% for _, p in ipairs(plants) do %}<li/>{% endfor %}</ul>", "{% endfor %} is Jinja's; a Lua block ends with {% end %}")
  refused("{% if x %}<p/>{% end %}", "a Lua if opens with then")
  refused("{% if x then %}<p/>{% elif y %}{% end %}", "Lua says {% elseif cond then %}")
end)

spec.test("Lua's own errors carry the page's lines, at compile time and when it runs", function()
  refused("<lua>\n  local x = = 1\n</lua>\n<p>x</p>", "ui/x.lui:2:")
  refused("<div>\n\n  <p>{{ 1 + }}</p>\n</div>", "ui/x.lui:3:")
  local ok, why = pcall(lui.answer, "<div>\n  <p>{{ nothing.here }}</p>\n</div>", "ui/r.lui", get())
  spec.eq(ok, false)
  spec.ok(string.find(why, "ui/r.lui:2:", 1, true), why)
  ok, why = pcall(lui.answer, '<lua>ui.component("x", function() return "" end)</lua>\n\n<y/>', "ui/r.lui", get())
  spec.ok(not ok and string.find(why, "ui/x.lui", 1, true) == nil and string.find(why, "ui/r.lui:3: <y>", 1, true), why)
end)

spec.test("a host that asks for lines gets each element's line in the page's source, and a person's page has none", function()
  STORE = {}
  local html = lui.answer(PLANTS, "ui/index.lui", get(), nil, { lines = true })
  spec.ok(string.find(html, '<ul id="plants" data-line="7">', 1, true) or
    string.find(html, '<ul data-line="7" id="plants">', 1, true), "the list, on line 7")
  spec.ok(string.find(html, 'data-line="10"', 1, true), "the buttons, on line 10")
  spec.ok(not string.find(lui.answer(PLANTS, "ui/index.lui", get()), "data-line", 1, true), "none unasked")
end)

spec.test("a page in Lua uses the same runtime", function()
  local def = function(_, actions)
    function actions.add() STORE.added = true end
    return function() return page.find({ { "a" } }, "none") or "plain" end
  end
  spec.eq(body(page.answer(def, post("/", "add"))), "plain")
  spec.ok(STORE.added)
end)

spec.run()
