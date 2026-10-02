-- A plant tracker: a database on the computer, a form that adds, buttons that water, each answered by htmx with
-- just the list again.
local ui = require("shroomi")
local date = require("date")

local M = { title = "Plants", icon = "sprout",
  blurb = "A watering log in a database: add a plant, water it, see what is due. htmx swaps the list in place." }

local function open()
  local d = db.open("data/plants.dbl")
  d:exec([[create table if not exists plant (name text primary key, every int not null, watered text)]])
  if not d:one("select 1 as x from plant") then
    local today = date.now()
    for _, p in ipairs({ { "Fern", 3, -4 }, { "Monstera", 7, -2 }, { "Basil", 2, -1 }, { "Snake plant", 14, -3 } }) do
      d:exec("insert into plant values (?, ?, ?)", p[1], p[2], date.day(date.add(today, { days = p[3] })))
    end
  end
  return d
end

-- days until it wants water: negative when overdue
local function due_in(p)
  if not p.watered then return 0 end
  return date.diff(date.add(date.parse(p.watered), { days = p.every }), date.parse(date.day(date.now())), "days")
end

local function list(d, root)
  local rows = {}
  for _, p in ipairs(d:query("select * from plant order by name")) do
    local n = due_in(p)
    local status = n < 0 and ui.badge{ variant = "destructive", -n .. (n == -1 and " day late" or " days late") }
      or n == 0 and ui.badge"Today"
      or ui.badge{ variant = "outline", "in " .. n .. (n == 1 and " day" or " days") }
    rows[#rows + 1] = ui.li{ class = "flex items-center gap-3 border-b border-border py-3 last:border-0",
      ui.div{ class = "flex size-9 items-center justify-center rounded-full bg-primary/10 text-primary", ui.icon"leaf" },
      ui.div{ class = "flex-1",
        ui.p{ class = "font-medium", p.name },
        ui.p{ class = "text-sm text-muted-foreground", "Every " .. p.every .. " days · last " .. (p.watered or "never") } },
      status,
      ui.button{ size = "sm", variant = "outline", post = root .. "water", target = "#plants", swap = "outerHTML",
        vals = json.encode({ name = p.name }), ui.icon"droplet", "Water" } }
  end
  if #rows == 0 then
    return ui.div{ id = "plants", ui.empty{ title = "No plants yet", description = "Add one above." } }
  end
  return ui.ul{ id = "plants", rows }
end

function M.handle(req, root)
  local d = open()
  if req.method == "POST" and req.path == "/add" then
    local every = tonumber(req.form.every)
    if req.form.name and req.form.name ~= "" and every and every >= 1 then
      d:exec("insert or replace into plant values (?, ?, null)", req.form.name, math.floor(every))
    end
    return ui.render(list(d, root))
  elseif req.method == "POST" and req.path == "/water" then
    d:exec("update plant set watered = ? where name = ?", date.day(date.now()), req.form.name)
    return ui.render(list(d, root))
  end
  return { page = ui.grid{ cols = 3,
    ui.card{ class = "md:col-span-2", title = "Your plants", description = "Water them when they ask.", list(d, root) },
    ui.card{ title = "Add a plant",
      ui.form{ post = root .. "add", target = "#plants", swap = "outerHTML",
        ui.input{ name = "name", label = "Name", placeholder = "Pothos", required = true },
        ui.input{ name = "every", label = "Water every (days)", type = "number", min = 1, value = 7 },
        ui.button{ ui.icon"plus", "Add" } } } } }
end

return M
