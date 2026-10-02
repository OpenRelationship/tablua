-- Notes in Markdown: a list, an editor, and a preview htmx asks for as you type.
local ui = require("shroomi")
local date = require("date")

local M = { title = "Notes", icon = "notebook-pen",
  blurb = "Markdown notes kept on the computer's disk, with a preview that follows your typing." }

local DIR = "files/notes"

local function seed()
  if fs.isdir(DIR) then return end
  fs.mkdir(DIR)
  fs.write(DIR .. "/welcome.md", "# Welcome\n\nNotes are **Markdown** files on this computer's disk.\n\n" ..
    "- Lists, *emphasis* and `code`\n- [Links](https://example.com)\n\n> The preview is the same HTML a page shows.")
  fs.write(DIR .. "/garden.md", "# Garden\n\n1. Repot the monstera\n2. Cuttings from the pothos\n3. Order seed compost")
end

local function slug(s) return (string.gsub(string.lower(s), "[^%w]+", "-")) end

local function sidebar(root, current)
  local items = {}
  local names = fs.list(DIR) or {}
  table.sort(names)
  for _, f in ipairs(names) do
    local name = string.gsub(f, "%.md$", "")
    items[#items + 1] = ui.li{ ui.link_button{ href = root .. "note/" .. name, size = "sm", class = "w-full justify-start",
      variant = name == current and "secondary" or "ghost", ui.icon"file-text", name } }
  end
  return ui.card{ title = "Notes", description = #items .. " on disk",
    ui.ul{ class = "space-y-1", items },
    ui.form{ class = "mt-4 flex gap-2", post = root .. "new",
      ui.input{ name = "title", placeholder = "New note", required = true, class = "flex-1" },
      ui.button{ size = "icon", ["aria-label"] = "Add", ui.icon"plus" } } }
end

local function preview(text)
  return ui.div{ id = "preview", class = "space-y-3 leading-relaxed", ui.markdown(text) }
end

local function editor(root, name)
  local text = fs.read(DIR .. "/" .. name .. ".md") or ""
  return ui.div{ class = "grid gap-4 md:grid-cols-2",
    ui.card{ title = name, description = "Saved as you type",
      ui.form{ post = root .. "save/" .. name, trigger = "input changed delay:400ms", target = "#preview",
        swap = "outerHTML",
        ui.textarea{ name = "text", rows = 16, class = "font-mono text-sm", value = text } } },
    ui.card{ title = "Preview", preview(text) } }
end

function M.handle(req, root)
  seed()
  local name = string.match(req.path, "^/note/([%w%-]+)$")
  local saving = string.match(req.path, "^/save/([%w%-]+)$")
  if req.method == "POST" and saving then
    fs.write(DIR .. "/" .. saving .. ".md", req.form.text or "")
    return ui.render(preview(req.form.text or ""))
  elseif req.method == "POST" and req.path == "/new" and (req.form.title or "") ~= "" then
    local s = slug(req.form.title)
    if not fs.exists(DIR .. "/" .. s .. ".md") then
      fs.write(DIR .. "/" .. s .. ".md", "# " .. req.form.title .. "\n\nWritten " .. date.day(date.now()) .. ".\n")
    end
    return { redirect = root .. "note/" .. s }
  end
  name = name or "welcome"
  return { page = ui.div{ class = "grid gap-4 md:grid-cols-4",
    ui.div{ sidebar(root, name) }, ui.div{ class = "md:col-span-3", editor(root, name) } } }
end

return M
