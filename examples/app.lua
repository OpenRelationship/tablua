-- The gallery: Shroomi's examples as one app on a computer (/home/app.lua, with the examples in /home/examples).
-- "/" lists them; "/<name>/..." is that example, given the rest of the path and its own root for its links;
-- "/<name>/code" shows its Lua. Every page here is written in Shroomi and nothing else.
local ui = require("shroomi")

local NAMES = { "plants", "notes", "dashboard", "settings", "report", "inbox" }
local examples = {}
for _, n in ipairs(NAMES) do examples[n] = require("examples." .. n) end

local function shell(title, active, body)
  local links = { ui.link_button{ href = "./", variant = active and "ghost" or "secondary", size = "sm", "Gallery" } }
  for _, n in ipairs(NAMES) do
    links[#links + 1] = ui.link_button{ href = n .. "/", size = "sm",
      variant = n == active and "secondary" or "ghost", ui.icon(examples[n].icon), examples[n].title }
  end
  return ui.page{ title = title .. " · Shroomi",
    ui.header{ class = "border-b border-border bg-background",
      ui.div{ class = "mx-auto flex max-w-6xl flex-wrap items-center gap-1 px-4 py-2",
        ui.strong{ class = "mr-3 flex items-center gap-2", ui.icon{ "sprout", size = 18 }, "Shroomi" }, links } },
    ui.div{ class = "mx-auto max-w-6xl px-4 py-6", body },
  }
end

local function index()
  local cards = {}
  for _, n in ipairs(NAMES) do
    local e = examples[n]
    cards[#cards + 1] = ui.card{ title = e.title, description = e.blurb,
      footer = ui.row{ ui.link_button{ href = n .. "/", size = "sm", "Open" },
        ui.link_button{ href = n .. "/code", size = "sm", variant = "outline", "Read the Lua" } },
      ui.div{ class = "flex size-10 items-center justify-center rounded-lg bg-primary/10 text-primary",
        ui.icon{ e.icon, size = 20 } } }
  end
  return shell("Gallery", nil, ui.stack{ gap = 6,
    ui.div{ class = "space-y-2",
      ui.h1{ class = "text-3xl font-semibold tracking-tight", "Made with Shroomi" },
      ui.p{ class = "max-w-2xl text-muted-foreground",
        "Each of these is an app an agent could write on its own computer: Lua that builds HTML, styled by the " ..
        "kit and utility classes, moved by htmx. Open one, or read the Lua that made it." } },
    ui.grid{ cols = 3, cards } })
end

local function code(name)
  local src = fs.read("code/examples/" .. name .. ".lua") or "-- not found"
  local _, lines = string.gsub(src, "\n", "")
  return shell(examples[name].title .. " · Lua", name, ui.stack{
    ui.row{ class = "justify-between",
      ui.h1{ class = "text-2xl font-semibold", "code/examples/" .. name .. ".lua" },
      ui.row{ ui.badge{ variant = "secondary", lines .. " lines" },
        ui.link_button{ href = name .. "/", size = "sm", "Open the app" } } },
    ui.pre{ class = "overflow-x-auto rounded-lg border border-border bg-muted p-4 text-sm leading-relaxed",
      ui.code(src) } })
end

return function(req)
  local name, rest = string.match(req.path, "^/([%w_]+)(.*)$")
  if not name or not examples[name] then return index() end
  if rest == "/code" then return code(name) end
  req.path = rest == "" and "/" or rest
  local res = examples[name].handle(req, name .. "/")
  if type(res) == "table" and res.page then return shell(examples[name].title, name, res.page) end
  return res
end
