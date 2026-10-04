-- Unit cases for tablua.edit: one unit replaced or added by name, in a plain Lua file and in an org page, the rest
-- of the file as it was; a unit that does not compile, or a page that does not exist yet, refused with why.
local spec = require("mono.spec")
local edit = require("tablua.edit")

local PAGE = table.concat({ "* Code", "#+begin_src lua", 'local d = db.open("data/x.dbl")', "",
  "function post.add(req) d:exec('insert into item (name) values (?)', req.form.name) end", "#+end_src",
  "* Page", "#+begin_src lua", "return ui.container{ ui.h1\"Items\" }", "#+end_src", "" }, "\n")

spec.test("a Lua file's unit is replaced in place, or added at the end, the rest kept", function()
  local text = "local M = {}\n\nfunction M.add(x) return x end\n\nreturn M\n"
  local out = assert(edit.apply("code/items.lua", text, "M.add", "function M.add(x) return x + 1 end"))
  spec.eq(out, "local M = {}\n\nfunction M.add(x) return x + 1 end\n\nreturn M\n")
  spec.same(edit.index("code/items.lua", out), { "M", "M.add" })
  local added = assert(edit.apply("code/steps/items.lua", nil, 'there are {int} items',
    'test.step("there are {int} items", function(w, n) end)'))
  spec.eq(added, 'test.step("there are {int} items", function(w, n) end)\n')
end)

spec.test("a page's action or its Page is replaced, and the page stays org", function()
  spec.same(edit.index("ui/index.org", PAGE), { "d", "post.add", "page" })
  local out = assert(edit.apply("ui/index.org", PAGE, "post.add",
    "function post.add(req) d:exec('insert into item (name) values (?)', req.form.item) end"))
  spec.ok(out:find("req.form.item", 1, true) and not out:find("req.form.name", 1, true))
  spec.ok(out:find('ui.h1"Items"', 1, true))
  local paged = assert(edit.apply("ui/index.org", out, "page", 'return ui.container{ ui.h1"Things" }'))
  spec.ok(paged:find('ui.h1"Things"', 1, true) and paged:find("req.form.item", 1, true))
  local more = assert(edit.apply("ui/index.org", paged, "post.remove", "-- take one away\nfunction post.remove(req) end"))
  spec.same(edit.index("ui/index.org", more), { "d", "post.add", "post.remove", "page" })
end)

spec.test("what would break the file is refused, saying why", function()
  local out, why = edit.apply("ui/index.org", PAGE, "post.add", "function post.add(req")
  spec.eq(out, nil)
  spec.ok(why:find("does not compile", 1, true))
  out, why = edit.apply("ui/new.org", nil, "page", "return ui.p'x'")
  spec.ok(out == nil and why:find("write_page", 1, true))
  out, why = edit.apply("features/a.feature", "Feature: a\n", "x", "x = 1")
  spec.ok(out == nil and why:find("ui/*.org", 1, true))
  spec.eq((edit.apply("code/a.lua", "x = 1\n", "", "y = 2")), nil)
end)

spec.run()
