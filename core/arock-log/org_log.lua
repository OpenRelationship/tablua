-- arock-log.org_log: an org file kept on the log. arock-log is the truth; the file is how an agent reads and edits it.
--
--   org_log.write(s, path, text, opts) -> text | nil, errs   -- the file read back, or refusals by line
--     opts.actor    agent (default), user or host; only the host may write GRANTED
--     opts.task     the task the events go under (default "org")
--     opts.now      "2026-10-02 Fri 12:00" for what the host stamps (default: the store's clock)
--     opts.resolve  function(target) -> true | false, why: org:, mail: and feature: links, as the node resolves
--                   them; file: links name a file in the store unless opts.resolve says otherwise
--   org_log.read(s, path)    -> the file as the log holds it (nil when the log has none)
--   org_log.history(s, path) -> what org_diff.plan reads
--
-- A write is checked whole (arock-log.org_diff) and its events appended in one transaction: all of them, or none.
local org = require("arock-log.org")
local org_diff = require("arock-log.org_diff")

local M = {}

-- the store's clock ("2026-10-02T12:00:00Z") as an org stamp's inside
local function org_now(s)
  local y, m, d, hh, mm = tostring(s.clock()):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d)")
  if not y then return nil end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  return ("%04d-%02d-%02d %s %s:%s"):format(y, m, d, org.weekday(y, m, d), hh, mm)
end

function M.history(s, path)
  local h = { path = path, entries = {}, known = {} }
  for _, r in ipairs(s.db:exec("select id, text from org_entries where path = ? and archived = 0 order by pos", { path })) do
    h.entries[#h.entries + 1] = { id = r.id, text = r.text }
  end
  for _, r in ipairs(s.db:exec("select id from org_entries")) do h.known[r.id] = true end
  local f = s.db:exec("select header from org_files where path = ?", { path })[1]
  h.header = f and f.header or nil
  -- every ID ever given counts, an undone one too, so none is given twice
  h.next_id = s.db:exec("select count(*) as n from events where keyword = 'Add Entry'")[1].n + 1
  return h
end

function M.read(s, path)
  local h = M.history(s, path)
  if #h.entries == 0 and not h.header then return nil end
  local parts = {}
  if h.header and h.header ~= "\n" then parts[#parts + 1] = h.header end
  for _, e in ipairs(h.entries) do parts[#parts + 1] = e.text end
  return org.render(org.parse(table.concat(parts, "\n")))
end

function M.write(s, path, text, opts)
  opts = opts or {}
  local resolve = opts.resolve
  if not resolve then
    resolve = function(target)
      local file = target:match("^file:(.+)$")
      if file then return s:file(file) ~= nil, "the link " .. target .. " names no file on this computer" end
      return true
    end
  end
  local plan, errs = org_diff.plan(text, M.history(s, path), {
    now = opts.now or org_now(s), host = opts.actor == "host", resolve = resolve,
  })
  if not plan then return nil, errs end
  local task, actor = opts.task or "org", opts.actor or "agent"
  s:batch(function()
    for _, ev in ipairs(plan.events) do s:append(task, ev[1], ev[2], actor) end
  end)
  -- a file with nothing in it is kept as nothing: the log holds no entry and no header for it
  return M.read(s, path) or ""
end

return M
