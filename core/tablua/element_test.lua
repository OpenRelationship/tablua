-- Unit cases for tablua.element: a change block's operations on a page's elements, through tablua.change, each
-- with its reverse, and the refusals named by operation. The spec's scenarios are in
-- context/projects/arock/features/change-blocks (page-elements).
local spec = require("mono.spec")
local change = require("tablua.change")

local PAGE = 'local ui = require("ui")\nreturn ui.page{\n  ui.form{ post = "add", ui.input{ name = "n" } },\n'
  .. '  ui.p"x",\n}\n'

local function rows(page) return { sections = { { kind = "markup", lang = "lua", body = page or PAGE } } } end

local function round(block)
  local done = assert(change.apply(rows(), block))
  local back = assert(change.apply(done.rows, done.reverse))
  spec.eq(back.rows.sections[1].body, PAGE)
  local again = assert(change.apply(back.rows, block))
  spec.eq(again.rows.sections[1].body, done.rows.sections[1].body)
  return done.rows.sections[1].body, done
end

spec.test("set changes, adds and takes away a prop, each undone", function()
  spec.ok(round('%% set page/form post\n"save"\n'):find('post = "save"', 1, true))
  spec.ok(round('%% set page/form class\n"wide"\n'):find('ui.input{ name = "n" }, class = "wide"', 1, true))
  spec.ok(not round("%% set page/form post\n"):find("post", 1, true))
end)

spec.test("put, drop and move by place, each undone", function()
  spec.ok(round('%% put first in page/form\nui.label"Name"\n'):find('ui.form{ ui.label"Name", post', 1, true))
  spec.ok(round('%% put before page/p\nui.h1"Top"\n'):find('ui.h1"Top",\n  ui.p"x"', 1, true))
  spec.ok(not round("%% drop page/form/input\n"):find("input", 1, true))
  spec.ok(round("%% move page/p in page/form at 2\n"):find('post = "add", ui.p"x", ui.input', 1, true))
  spec.ok(round("%% drop in page/form at 1\n"):find('ui.form{ ui.input', 1, true))
end)

spec.test("wrap puts an element where the wrapper's ... is, unwrap takes the wrapper away", function()
  local body = round('%% wrap page/p\nui.div{ class = "box", ... }\n')
  spec.ok(body:find('ui.div{ class = "box", ui.p"x" }', 1, true))
  local _, done = round('%% wrap page/p\nui.div{ ... }\n%% unwrap page/div\n')
  spec.eq(done.rows.sections[1].body, PAGE)
end)

spec.test("refusals name the operation, and a failing change leaves the page as it was", function()
  local function why(block) return select(2, change.apply(rows(), block)) end
  spec.eq(why("%% drop page/none\n"), 'operation 1 names no element "page/none"')
  spec.eq(why("%% drop page\n"), "operation 1: page is the page's root; change the unit instead")
  spec.eq(why("%% put in page/p\nui.b\"x\"\n"), "operation 1: page/p holds no table to put into")
  spec.eq(why("%% put in page\n1 + 2\n"), "operation 1: its source should be one element, a call such as ui.p{ ... }")
  spec.eq(why("%% wrap page/p\nui.div{ }\n"), "operation 1: the wrapper's source needs ... where page/p goes")
  spec.eq(why("%% move page/form in page/form/input\n"), "operation 1: page/form cannot move into itself")
  spec.eq(why("%% set page/form post\n\"a\"\n%% unwrap page\n"), "operation 2: page holds 2 elements; unwrap takes a wrapper of one")
  spec.eq(select(2, change.apply({ sections = {} }, "%% drop page/p\n")), "operation 1: the program has no page written in Lua")
end)

spec.test("an element's operation records its call, its path, the lines it adds and the posts it leaves broken", function()
  local done = assert(change.apply(rows(), '%% set page/form post\n"save"\n%% drop page/p\n'))
  spec.same(done.ops[1], { op = "set", kind = "ui.form", name = "page/form", lines = 0, named_by = 0, breaks = 1 })
  spec.same(done.ops[2], { op = "drop", kind = "ui.p", name = "page/p", lines = -1, named_by = 0, breaks = 0 })
end)

spec.run()
