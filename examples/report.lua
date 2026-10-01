-- A report: the kind of artifact an agent publishes when a job is done. Prose from Markdown, figures, a table
-- from a CSV on its disk, and callouts.
local ui = require("shroomi")
local csv = require("csv")

local M = { title = "Report", icon = "file-text",
  blurb = "A finished piece of work: prose from Markdown, figures, a table read from a CSV, and callouts." }

local DATA = "plant,watered,missed\nFern,12,1\nMonstera,4,0\nBasil,15,3\nSnake plant,2,0\n"

local SUMMARY = [[
September went well. Every plant was watered on **33 of 37** days it asked, and the misses were all in the
week the reminders were paused.

The basil is the one to watch: it wants water every two days and missed three. Moving its reminder to the
morning digest should close the gap.
]]

local function figure(label, value)
  return ui.div{ class = "rounded-lg border border-border p-4",
    ui.p{ class = "text-sm text-muted-foreground", label },
    ui.p{ class = "text-2xl font-semibold tabular-nums", value } }
end

function M.handle()
  local rows = {}
  for i, r in ipairs(csv.parse(DATA, { header = true })) do
    rows[i] = { r.plant, r.watered, tonumber(r.missed) > 0 and ui.badge{ variant = "destructive", r.missed } or "0" }
  end
  return { page = ui.article{ class = "mx-auto max-w-3xl space-y-8",
    ui.header{ class = "space-y-3",
      ui.row{ ui.badge{ variant = "secondary", "Report" }, ui.span{ class = "text-sm text-muted-foreground",
        "Written by the agent · 1 October 2026" } },
      ui.h1{ class = "text-4xl font-semibold tracking-tight", "The garden in September" },
      ui.p{ class = "text-lg text-muted-foreground", "What was watered, what was missed, and one change to make." } },
    ui.div{ class = "grid grid-cols-3 gap-4",
      figure("Days asked", "37"), figure("Watered on time", "89%"), figure("Missed", "4") },
    ui.markdown(SUMMARY),
    ui.alert{ title = "One change", "Move the basil's reminder into the morning digest." },
    ui.section{ class = "space-y-3",
      ui.h2{ class = "text-xl font-semibold", "By plant" },
      ui.data_table{ columns = { "Plant", "Watered", "Missed" }, rows = rows } },
    ui.alert{ variant = "destructive", title = "Paused 14–20 September",
      "Reminders were off that week; every miss falls inside it." },
  } }
end

return M
