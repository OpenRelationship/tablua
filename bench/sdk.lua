-- The SDK's real work, timed: what an agent's computer spends its Lua on. One line per job: name, ms.
local ui, csv, date = require("shroomi"), require("csv"), require("date")
local md = require("shroomi.markdown")

local function time(name, n, f)
  local t0 = os.clock()
  for _ = 1, n do f() end
  print(string.format("%-18s %8.2f ms", name, (os.clock() - t0) * 1000 / n))
end

local rows = { "name,every,watered" }
for i = 1, 500 do rows[#rows + 1] = "plant " .. i .. "," .. (i % 14 + 1) .. ",2026-09-" .. string.format("%02d", i % 28 + 1) end
local text = table.concat(rows, "\n")
local doc = string.rep("## Heading\n\nSome *emphasis*, **strong**, `code` and a [link](https://x.y).\n\n- one\n- two\n\n", 20)

time("shroomi page", 1, function()
  local items = {}
  for i = 1, 50 do items[i] = ui.li{ class = "flex items-center gap-3 border-b py-3", ui.icon"leaf",
    ui.span{ class = "flex-1", "plant " .. i }, ui.badge{ variant = "outline", "in " .. i .. " days" },
    ui.button{ size = "sm", post = "water", "Water" } } end
  return ui.page{ title = "Plants", ui.container{ ui.card{ title = "Plants", ui.ul(items) } } }
end)
time("csv parse 500", 1, function() return csv.parse(text, { header = true }) end)
time("json 500 rows", 1, function() return json.decode(json.encode(csv.parse(text, { header = true }))) end)
time("markdown 20 secs", 1, function() return md.html(doc) end)
time("date 1000", 1, function() for i = 1, 1000 do date.iso(date.add(date.parse("2026-10-01"), { days = i })) end end)
time("template 50", 1, function()
  local list = {}
  for i = 1, 50 do list[i] = { name = "p" .. i } end
  return ui.template("<ul>{{#list}}<li>{{name}}</li>{{/list}}</ul>", { list = list })
end)
