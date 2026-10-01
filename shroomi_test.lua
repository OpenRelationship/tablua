-- Building pages: elements escape what they show, htmx in short, components, a whole page with its assets.
local spec = require("mono.spec")
local ui = require("shroomi")

spec.test("an element escapes its text and its attributes, and sorts its attributes", function()
  spec.eq(ui.render(ui.p{ id = "a\"b", class = { "x", "y" }, "<script>alert(1)</script> & co" }),
    '<p class="x y" id="a&quot;b">&lt;script&gt;alert(1)&lt;/script&gt; &amp; co</p>')
  spec.eq(ui.render(ui.el("input", { disabled = true, checked = false, name = "n" })), '<input disabled name="n">')
  spec.eq(ui.render(ui.div"just text"), "<div>just text</div>")
  spec.eq(ui.render(ui.raw("<b>kept</b>")), "<b>kept</b>")
end)

spec.test("a child left out as nil or false leaves no hole", function()
  local none = nil
  spec.eq(ui.render(ui.div{ ui.span"a", none, false, ui.span"b" }), "<div><span>a</span><span>b</span></div>")
  spec.eq(ui.render({ "x", none, "y" }), "xy")
end)

spec.test("htmx's names are short props", function()
  spec.eq(ui.render(ui.button{ post = "plants", target = "#list", swap = "outerHTML", "Add" }),
    '<button class="btn" hx-post="plants" hx-swap="outerHTML" hx-target="#list" type="button">Add</button>')
end)

spec.test("a tag the policy does not allow is not offered", function()
  spec.eq(ui.script, nil)
  spec.eq(ui.iframe, nil)
  spec.ok(ui.section)
end)

spec.test("the kit's components render Basecoat's markup", function()
  spec.eq(ui.render(ui.button{ "Go", variant = "outline", size = "sm" }),
    '<button class="btn" data-size="sm" data-variant="outline" type="submit">Go</button>')
  spec.eq(ui.render(ui.card{ title = "Ferns", "Two of them" }),
    '<div class="card"><header><h2>Ferns</h2></header><section>Two of them</section></div>')
  spec.eq(ui.render(ui.input{ name = "name", label = "Name" }),
    '<div class="field"><label for="name">Name</label><input class="input" id="name" name="name"></div>')
  spec.eq(ui.render(ui.select{ name = "kind", value = "b", options = { "a", { "b", "Bee" } } }),
    '<select class="select" id="kind" name="kind"><option value="a">a</option>' ..
    '<option selected value="b">Bee</option></select>')
  spec.eq(ui.render(ui.data_table{ columns = { "Name" }, rows = { { "fern" } } }),
    '<div class="table-container"><table class="table"><thead><tr><th>Name</th></tr></thead>' ..
    '<tbody><tr><td>fern</td></tr></tbody></table></div>')
  spec.eq(ui.render(ui.stack{ gap = 2, class = "p-4", "a" }), '<div class="flex flex-col gap-2 p-4">a</div>')
end)

spec.test("tabs and dialogs open by data attributes, never by inline script", function()
  spec.eq(ui.render(ui.tabs{ id = "t", { "One", "first" }, { "Two", "second" } }),
    '<div class="tabs" id="t"><nav aria-orientation="horizontal" role="tablist">' ..
    '<button aria-controls="t-panel-1" aria-selected="true" id="t-tab-1" role="tab" tabindex="0" type="button">One</button>' ..
    '<button aria-controls="t-panel-2" aria-selected="false" id="t-tab-2" role="tab" tabindex="-1" type="button">Two</button>' ..
    '</nav><div aria-labelledby="t-tab-1" id="t-panel-1" role="tabpanel" tabindex="-1">first</div>' ..
    '<div aria-labelledby="t-tab-2" hidden id="t-panel-2" role="tabpanel" tabindex="-1">second</div></div>')
  local d = ui.render(ui.dialog{ id = "d", title = "Sure?", trigger = "Delete", "It goes for good." })
  spec.ok(string.find(d, 'data-open="d"', 1, true))
  spec.ok(string.find(d, 'data-close="d"', 1, true))
  spec.eq(string.find(d, "onclick", 1, true), nil)
end)

spec.test("an agent's own component is a function of props and children", function()
  ui.component("plant", function(p, c) return ui.li{ class = "flex gap-2", ui.strong(p.name), c } end)
  spec.eq(ui.render(ui.plant{ name = "fern", "every 3 days" }),
    '<li class="flex gap-2"><strong>fern</strong>every 3 days</li>')
  local found = false
  for _, n in ipairs(ui.kit) do if n == "plant" then found = true end end
  spec.ok(found)
  spec.err(function() ui.component("bad name", function() end) end, "plain name")
end)

spec.test("a page carries Basecoat, htmx and Shroomi's script, and CSS for the classes it uses only", function()
  local page = ui.page{ title = "Plants & co", ui.container{ ui.h1{ class = "text-2xl font-bold", "Plants" } } }
  spec.ok(string.find(page, "<title>Plants &amp; co</title>", 1, true))
  spec.ok(string.find(page, '<link rel="stylesheet" href="/shroomi/basecoat-1.0.2.min.css">', 1, true))
  spec.ok(string.find(page, '<script src="/shroomi/htmx-2.0.4.min.js"></script>', 1, true))
  spec.ok(string.find(page, '<script src="/shroomi/shroomi.js"></script>', 1, true))
  spec.ok(string.find(page, ".text-2xl{font-size: 1.5rem;line-height: 2rem;}", 1, true))
  spec.ok(string.find(page, ".max-w-3xl{max-width: 48rem;}", 1, true))
  spec.eq(string.find(page, ".text-xl{", 1, true), nil)
end)

spec.test("rendering a page again gives the page, not its source as text", function()
  local page = ui.page{ title = "Books", ui.p"one" }
  spec.eq(ui.render(page), page)
  spec.eq(ui.render(ui.p"<!doctype html>"), "<p>&lt;!doctype html&gt;</p>")
end)

spec.test("a page follows the person's light or dark, unless it says which", function()
  spec.ok(string.find(ui.page{ "x" }, '<html lang="en" data-theme="auto">', 1, true))
  spec.ok(string.find(ui.page{ dark = true, "x" }, '<html lang="en" class="dark" data-theme="dark">', 1, true))
  spec.ok(string.find(ui.page{ dark = false, "x" }, '<html lang="en" data-theme="light">', 1, true))
end)

spec.test("check names the classes Shroomi does not know", function()
  spec.same(ui.check('<div class="p-4 text-red-500 hover:bg-primary/10 fancy">'), { "text-red-500", "fancy" })
end)

spec.test("markdown and templates are part of the page", function()
  spec.eq(ui.render(ui.markdown("**hi** <b>")), '<div class="prose"><p><strong>hi</strong> &lt;b&gt;</p>\n</div>')
  spec.eq(ui.template("<p>{{name}}</p>{{#xs}}<i>{{.}}</i>{{/xs}}", { name = "<a>", xs = { 1, 2 } }),
    "<p>&lt;a&gt;</p><i>1</i><i>2</i>")
end)

spec.run()
