-- The query tool over a fake engine: rows come back one JSON line each under a count, and SQL the engine refuses is
-- said in SQLite's words with the tables there are, as data and not an error.
local spec = require("spec")
local tools = require("studio.tools")

local function tool(reply)
  local asked
  local s = { comp = "c.lua", engine = { query = function(_, comp, sql) asked = { comp, sql } return reply end } }
  for _, t in ipairs(tools.list(s)) do if t.name == "query" then return t, function() return asked end end end
end

spec.test("the rows of a query, one line each, under their count", function()
  local t, asked = tool({ count = 2, rows = { { id = "title", f0 = 41 }, { id = "logo", f0 = 42 } }, tables = { "box" } })
  local r = t.execute({ sql = "select id, f0 from box" })
  spec.same(asked(), { "c.lua", "select id, f0 from box" })
  spec.ok(r.content:find("^2 rows\n"), r.content)
  spec.ok(r.content:find('"id":"title"', 1, true) and r.content:find('"f0":42', 1, true), r.content)
  spec.eq(r.details.outcome, "complete")
end)

spec.test("SQL the engine refuses comes back as data, with the tables", function()
  local t = tool({ error = "no such column: nope", tables = { "box", "node" } })
  local r = t.execute({ sql = "select nope from box" })
  spec.eq(r.content, "SQLite refused it: no such column: nope\nTables: box, node")
  spec.eq(r.details.outcome, "rejected")
end)

spec.run()
