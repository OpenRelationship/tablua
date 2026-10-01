-- An inbox: a list on the left, the letter on the right, loaded by htmx without leaving the page.
local ui = require("shroomi")

local M = { title = "Inbox", icon = "inbox",
  blurb = "A two-pane mail reader: the list stays, the letter loads beside it, unread ones stand out." }

local LETTERS = {
  { id = 1, from = "moss-7", subject = "Cuttings are rooted", when = "09:14", unread = true,
    body = "The pothos cuttings have roots about two centimetres long. Shall I pot them up this week?" },
  { id = 2, from = "billing", subject = "Your receipt for October", when = "08:02", unread = true,
    body = "Thank you. Your subscription renews on 1 November." },
  { id = 3, from = "moss-2", subject = "Re: compost order", when = "Yesterday", unread = false,
    body = "Ordered two bags of seed compost; they arrive Friday." },
  { id = 4, from = "calendar", subject = "Repot the monstera", when = "Mon", unread = false,
    body = "A reminder you set: repot the monstera before the weekend." },
}

local function letter(l)
  return ui.div{ id = "reader",
    ui.card{ title = l.subject, description = "From " .. l.from .. " · " .. l.when,
      footer = ui.row{ ui.button{ size = "sm", ui.icon"send", "Reply" },
        ui.button{ size = "sm", variant = "outline", ui.icon"archive", "Archive" } },
      ui.p{ class = "leading-relaxed", l.body } } }
end

local function list(root, open)
  local items = {}
  for i, l in ipairs(LETTERS) do
    items[i] = ui.li{
      ui.a{ href = root .. "letter/" .. l.id, get = root .. "letter/" .. l.id, target = "#reader", swap = "outerHTML",
        class = "flex flex-col gap-1 rounded-md p-3 hover:bg-accent " .. (l.id == open and "bg-accent" or ""),
        ui.span{ class = "flex items-center justify-between gap-2",
          ui.span{ class = l.unread and "font-semibold" or "", l.from },
          ui.span{ class = "text-xs text-muted-foreground", l.when } },
        ui.span{ class = "truncate text-sm " .. (l.unread and "" or "text-muted-foreground"), l.subject } } }
  end
  return ui.ul{ class = "space-y-1", items }
end

function M.handle(req, root)
  local id = tonumber(string.match(req.path, "^/letter/(%d+)$") or "1")
  local l = LETTERS[id] or LETTERS[1]
  if req.headers["hx-request"] then return ui.render(letter(l)) end
  local unread = 0
  for _, x in ipairs(LETTERS) do if x.unread then unread = unread + 1 end end
  return { page = ui.div{ class = "grid gap-4 md:grid-cols-3",
    ui.card{ title = "Inbox", description = unread .. " unread",
      ui.tabs{ id = "boxes", { "Received", list(root, l.id) },
        { "Sent", ui.empty{ title = "Nothing sent yet", description = "Letters you send land here." } } } },
    ui.div{ class = "md:col-span-2", letter(l) } } }
end

return M
