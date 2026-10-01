-- A dashboard: figures, a bar chart drawn with nothing but elements and widths, a table, and tabs.
local ui = require("shroomi")

local M = { title = "Dashboard", icon = "chart-column",
  blurb = "Figures, a chart made of plain elements, a table and tabs: a report an agent keeps up to date." }

local WEEK = { { "Mon", 42 }, { "Tue", 58 }, { "Wed", 35 }, { "Thu", 71 }, { "Fri", 64 }, { "Sat", 28 }, { "Sun", 19 } }
local RUNS = {
  { "Import orders", "done", "1.2 s", "2026-10-01 09:12" },
  { "Rebuild index", "done", "8.4 s", "2026-10-01 08:40" },
  { "Send digest", "failed", "0.3 s", "2026-10-01 08:00" },
  { "Water reminder", "done", "0.1 s", "2026-10-01 07:30" },
}

local function stat(label, value, delta, icon)
  local up = string.sub(delta, 1, 1) == "+"
  return ui.card{
    ui.div{ class = "flex items-start justify-between",
      ui.div{ class = "space-y-1",
        ui.p{ class = "text-sm text-muted-foreground", label },
        ui.p{ class = "text-3xl font-semibold tabular-nums", value } },
      ui.div{ class = "rounded-md bg-muted p-2 text-muted-foreground", ui.icon(icon) } },
    ui.p{ class = "mt-2 flex items-center gap-1 text-sm " .. (up and "text-primary" or "text-destructive"),
      ui.icon(up and "trending-up" or "trending-down"), delta .. " on last week" } }
end

local function chart()
  local top = 0
  for _, d in ipairs(WEEK) do top = math.max(top, d[2]) end
  local bars = {}
  for i, d in ipairs(WEEK) do
    bars[i] = ui.div{ class = "flex flex-1 flex-col items-center gap-2",
      ui.div{ class = "flex h-40 w-full items-end",
        ui.div{ class = "w-full rounded-t-md bg-primary", style = "height: " .. math.floor(d[2] / top * 100) .. "%",
          title = d[2] .. " runs" } },
      ui.span{ class = "text-xs text-muted-foreground", d[1] } }
  end
  return ui.div{ class = "flex items-end gap-2", bars }
end

local function runs()
  local rows = {}
  for i, r in ipairs(RUNS) do
    rows[i] = { r[1], ui.badge{ variant = r[2] == "done" and "secondary" or "destructive", r[2] }, r[3], r[4] }
  end
  return ui.data_table{ columns = { "Job", "Status", "Took", "When" }, rows = rows }
end

function M.handle()
  return { page = ui.stack{ gap = 6,
    ui.div{ class = "grid gap-4 md:grid-cols-3",
      stat("Runs this week", "317", "+12%", "chart-column"),
      stat("Files written", "1,204", "+4%", "file-text"),
      stat("Letters sent", "23", "-8%", "send") },
    ui.tabs{ id = "views",
      { "This week", ui.card{ title = "Runs per day", description = "Every command and script the agent ran.",
        chart() } },
      { "Recent jobs", ui.card{ title = "Recent jobs", runs() } },
      { "Goals", ui.card{ title = "Goals", ui.stack{
        ui.div{ class = "space-y-2", ui.p{ class = "text-sm", "Inbox zero" }, ui.progress{ value = 80 } },
        ui.div{ class = "space-y-2", ui.p{ class = "text-sm", "Tests green" }, ui.progress{ value = 100 } },
        ui.div{ class = "space-y-2", ui.p{ class = "text-sm", "Plants watered" }, ui.progress{ value = 45 } } } } } } } }
end

return M
