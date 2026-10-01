-- Settings: a form the server checks, fields that say what is wrong, switches, and a dialog that asks first.
local ui = require("shroomi")

local M = { title = "Settings", icon = "settings",
  blurb = "A form the server validates field by field, with switches, a select and a dialog before anything is lost." }

local FILE = "gallery-settings.json"

local function load()
  local saved = fs.read(FILE)
  return saved and json.decode(saved) or { name = "Pebbles", email = "pebbles@example.com", tone = "warm",
    digest = true, sounds = false }
end

local function check(f)
  local errors = {}
  if (f.name or "") == "" then errors.name = "A name, please." end
  if not string.match(f.email or "", "^[^@%s]+@[^@%s]+%.[^@%s]+$") then errors.email = "That is not an address." end
  return errors
end

local function form(root, s, errors, saved)
  return ui.form{ id = "settings", post = root .. "save", swap = "outerHTML",
    saved and ui.alert{ title = "Saved", "Your settings are kept on this computer." } or false,
    ui.input{ name = "name", label = "Name", value = s.name, error = errors.name,
      hint = "What the rock calls itself." },
    ui.input{ name = "email", label = "Email", type = "email", value = s.email, error = errors.email },
    ui.select{ name = "tone", label = "Tone", value = s.tone,
      options = { { "warm", "Warm" }, { "plain", "Plain" }, { "brief", "Brief" } } },
    ui.switch{ name = "digest", label = "Send a digest every morning", checked = s.digest },
    ui.switch{ name = "sounds", label = "Play sounds", checked = s.sounds },
    ui.row{ class = "justify-between",
      ui.button{ ui.icon"check", "Save" },
      ui.dialog{ id = "reset", trigger = "Reset everything", title = "Reset every setting?",
        description = "Your name, address and choices go back to how they began.",
        footer = ui.row{ ui.button{ type = "button", variant = "outline", ["data-close"] = "reset", "Keep them" },
          ui.button{ variant = "destructive", post = root .. "reset", target = "#settings", swap = "outerHTML",
            ["data-close"] = "reset", "Reset" } } } } }
end

function M.handle(req, root)
  if req.method == "POST" and req.path == "/save" then
    local f = req.form
    local s = { name = f.name, email = f.email, tone = f.tone, digest = f.digest == "on", sounds = f.sounds == "on" }
    local errors = check(f)
    if next(errors) then return ui.render(form(root, s, errors, false)) end
    fs.write(FILE, json.encode(s))
    return ui.render(form(root, s, {}, true))
  elseif req.method == "POST" and req.path == "/reset" then
    fs.remove(FILE)
    return ui.render(form(root, load(), {}, false))
  end
  return { page = ui.div{ class = "mx-auto max-w-xl",
    ui.card{ title = "Settings", description = "Checked on the computer, not in the browser.",
      form(root, load(), {}, false) } } }
end

return M
