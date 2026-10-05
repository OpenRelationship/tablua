-- Unit cases for tablua.tree: a page's nested calls cut into elements with paths, its tables' items, and an item
-- put in and taken out byte for byte. The change block's operations on them are in element_test.
local spec = require("mono.spec")
local tree = require("tablua.tree")

local PAGE = 'local ui = require("ui")\nreturn ui.page{\n  title = "T",\n  ui.p"one", ui.p("two"),\n'
  .. '  ui.list({ ui.item{ "a" }, ui.item{ on = function(x) local a, b = 1, 2 end } }),\n'
  .. '  string.format("%d", 1), ui.div(rows),\n}\n'

spec.test("calls through a dotted name given a table or a string are elements, Lua's own libraries are not", function()
  local paths = {}
  for i, el in ipairs(tree.cut(PAGE).all) do paths[i] = el.path end
  spec.same(paths, { "page", "page/p", "page/p[2]", "page/list", "page/list/item", "page/list/item[2]" })
end)

spec.test("a table's items split at its own commas, never at those in a function's body", function()
  local t = tree.cut(PAGE)
  local item2 = tree.find(t, "page/list/item[2]")
  spec.eq(#item2.items, 1)
  spec.eq(item2.items[1].key, "on")
  spec.eq(#tree.find(t, "page").items, 6)
  spec.eq(tree.index(tree.find(t, "page"), tree.find(t, "page/p[2]")), 3)
  spec.eq(tree.find(t, "page/p[1]"), tree.find(t, "page/p"))
end)

spec.test("an item put in and taken out again leaves the text as it was, at every place", function()
  local t = tree.cut(PAGE)
  local list = tree.find(t, "page/list")
  for k = 1, #list.items + 1 do
    local put, a = tree.insert(PAGE, list, k, 'ui.item"new"')
    spec.eq(put:sub(a, a + #'ui.item"new"' - 1), 'ui.item"new"')
    local again = tree.find(tree.cut(put), "page/list")
    local back, removed = tree.remove(put, again, k)
    spec.eq(back, PAGE)
    local exact = tree.insert(back, tree.find(tree.cut(back), "page/list"), k, removed, true)
    spec.eq(exact, put)
  end
  local empty = 'return ui.x{}\n'
  local put = tree.insert(empty, tree.cut(empty).roots[1], 1, 'ui.y"a"')
  spec.eq(put, 'return ui.x{ ui.y"a" }\n')
  spec.eq((tree.remove(put, tree.cut(put).roots[1], 1)), empty)
end)

spec.test("each element is a row: path, call, parent, depth, children, props and text", function()
  local rows = tree.rows(PAGE)
  spec.same(rows[1], { path = "page", call = "ui.page", parent = "", depth = 1, children = 3, props = "title", text = "" })
  spec.same(rows[3], { path = "page/p[2]", call = "ui.p", parent = "page", depth = 2, children = 0, props = "", text = "two" })
end)

spec.run()
