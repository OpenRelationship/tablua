-- arock-log.org_diff: an agent's new text for an org file against what the log holds for it, as events or refusals.
-- Pure: the history comes in as tables, so the rules hold the same wherever arock-log runs.
--
--   local plan, errs = org_diff.plan(text, history, opts)
--   history = { path = "org/plants.org",              -- the file
--               entries = { { id, text }, ... },  -- the file's live entries in order, as the fold holds them
--               header = "...",                   -- the file's header text (keywords and preamble), or nil
--               known = { id = true },            -- every ID the log has given, in any file, archived too
--               next_id = n }                     -- the number the next new ID takes
--   opts = { now = "2026-10-02 Fri 12:00", host = false, resolve = function(target) -> true | false, why }
--   plan = { events = { { keyword, args } }, entries = { { id, text } }, header, archived = { id, ... },
--            order = { id, ... }, next_id }
--
-- The rules: an ID is given by the computer and never reused; a link names something the log knows (id:) or the
-- node resolves (org:, file:, mail:, feature:, through opts.resolve); a task's keyword changes only as allowed
-- (DONE and DROP reopen only to TODO, and a task never loses its keyword); CLOSED is stamped by the host when a
-- task becomes DONE and never rewritten; the LOGBOOK and GRANTED are the host's; a property that was a number
-- stays one; and an entry leaves the file only by archiving (the tag :ARCHIVE:). A refused write keeps nothing.
local org = require("arock-log.org")

local M = {}

local NEXT = {
  [""] = { TODO = true, WAIT = true, DONE = true, DROP = true },
  TODO = { WAIT = true, DONE = true, DROP = true },
  WAIT = { TODO = true, DONE = true, DROP = true },
  DONE = { TODO = true },
  DROP = { TODO = true },
}
M.NEXT = NEXT

local function one(text)
  local doc = org.parse(text)
  return doc.entries[1]
end

-- an entry alone, in canonical form
function M.entry_text(e)
  local text = org.render({ filetags = {}, preamble = {}, entries = { e } })
  return text
end

function M.header_text(doc)
  return org.render({ title = doc.title, date = doc.date, filetags = doc.filetags, preamble = doc.preamble,
    entries = {} })
end

local function has_tag(e, tag)
  for _, t in ipairs(e.tags) do if t == tag then return true end end
  return false
end

local function same_list(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local function date_or_empty(t) return t and org.date_text(t) or "" end

local function stamp(opts) return org.date("[" .. opts.now .. "]") end

function M.plan(text, history, opts)
  opts = opts or {}
  local doc, errs = org.parse(text)
  if #errs > 0 then return nil, errs end
  local function err(line, msg) errs[#errs + 1] = { line = line, msg = msg } end
  local old, old_order = {}, {}
  for _, h in ipairs(history.entries or {}) do
    old[h.id] = one(h.text)
    old_order[#old_order + 1] = h.id
  end
  local known = history.known or {}
  local next_id = history.next_id or 1
  local seen, out, events, archived, order = {}, {}, {}, {}, {}
  local function ev(keyword, ...) events[#events + 1] = { keyword, { ... } } end

  for _, e in ipairs(doc.entries) do
    local id = e.props.ID
    local before
    if id then
      if seen[id] then err(e.line, "the ID " .. id .. " is on two entries") end
      seen[id] = true
      before = old[id]
      if not before then
        err(e.line, known[id] and ("the ID " .. id .. " belongs to another entry; leave :ID: out of a new one")
          or ("IDs are given by the computer; leave :ID: out of a new entry, not " .. id))
      end
    end
    local kw, was = e.keyword or "", before and (before.keyword or "") or ""
    if before then
      if kw ~= was and not NEXT[was][kw] then
        err(e.line, kw == "" and ("a task keeps its keyword; DROP it instead of clearing " .. was)
          or (was .. " becomes only TODO again, not " .. kw))
      end
      if e.closed and date_or_empty(e.closed) ~= date_or_empty(before.closed) then
        err(e.line, before.closed and "CLOSED is history and never rewritten" or "CLOSED is stamped by the computer; leave it out")
      end
      if #e.logbook > 0 and not same_list(e.logbook, before.logbook) then
        err(e.line, "the LOGBOOK is the computer's; leave it as read, or out")
      end
      for _, key in ipairs(e.order) do
        local v, w = e.props[key], before.props[key]
        if key == "GRANTED" and v ~= w and not opts.host then
          err(e.line, "GRANTED is written by the host when the person says yes, never by an agent")
        elseif w and tonumber(w) and not tonumber(v) then
          err(e.line, "the property " .. key .. " was a number (" .. w .. "), not " .. v)
        end
      end
    else
      if e.closed then err(e.line, "CLOSED is stamped by the computer when a task becomes DONE; leave it out") end
      if #e.logbook > 0 then err(e.line, "the LOGBOOK is kept by the computer; leave it out") end
      if e.props.GRANTED and not opts.host then
        err(e.line, "GRANTED is written by the host when the person says yes, never by an agent")
      end
    end
    for _, l in ipairs(e.links) do
      local scheme = l.target:match("^(%a[%w+.-]*):")
      if scheme == "id" then
        local target = l.target:sub(4)
        if not known[target] then err(l.line, "the link " .. l.target .. " names no entry the log knows") end
      elseif scheme ~= "http" and scheme ~= "https" and opts.resolve then
        local ok, why = opts.resolve(l.target)
        if not ok then err(l.line, why or ("the link " .. l.target .. " names nothing on this node")) end
      end
    end
    e.before, e.was = before, was
  end

  for _, id in ipairs(old_order) do
    if not seen[id] then
      local b = old[id]
      err(1, "the entry \"" .. b.title .. "\" (" .. id .. ") left the file; an entry leaves only by archiving: tag it :ARCHIVE:")
    end
  end
  if #errs > 0 then
    table.sort(errs, function(a, b) return a.line < b.line end)
    return nil, errs
  end

  for _, e in ipairs(doc.entries) do
    local before, was, kw = e.before, e.was, e.keyword or ""
    if before then
      -- what the agent left out stays as the log has it
      e.logbook = before.logbook
      if not e.props.GRANTED and before.props.GRANTED then
        e.props.GRANTED = before.props.GRANTED
        e.order[#e.order + 1] = "GRANTED"
      end
      e.closed = before.closed
    else
      local id = "e" .. next_id
      next_id = next_id + 1
      e.props.ID = id
      table.insert(e.order, 1, "ID")
    end
    local id = e.props.ID
    if kw ~= was and opts.now then
      if kw == "DONE" then e.closed = stamp(opts) elseif was == "DONE" then e.closed = nil end
      local line = ('- State "%s" from "%s" %s'):format(kw, was, org.date_text(stamp(opts)))
      if was == "" and not before then line = ('- State "%s" %s'):format(kw, org.date_text(stamp(opts))) end
      table.insert(e.logbook, 1, line)
    end
    local entry = M.entry_text(e)
    if not before then
      ev("Add Entry", history.path, id, entry)
    else
      if kw ~= was then ev("Set State", id, was, kw) end
      for _, which in ipairs({ "scheduled", "deadline" }) do
        if date_or_empty(e[which]) ~= date_or_empty(before[which]) then ev("Set Date", id, which, date_or_empty(e[which])) end
      end
      for _, key in ipairs(e.order) do
        if key ~= "ID" and e.props[key] ~= before.props[key] then ev("Set Property", id, key, e.props[key]) end
      end
      for _, key in ipairs(before.order) do
        if e.props[key] == nil then ev("Set Property", id, key, "") end
      end
      local had = {}
      for _, l in ipairs(before.links) do had[l.target] = true end
      for _, l in ipairs(e.links) do if not had[l.target] then ev("Link", id, l.target) end end
      if entry ~= M.entry_text(before) then ev("Edit Entry", id, entry) end
    end
    if has_tag(e, "ARCHIVE") then
      archived[#archived + 1] = id
      ev("Archive Entry", id)
    else
      out[#out + 1] = { id = id, text = entry }
      order[#order + 1] = id
    end
  end
  local header = M.header_text(doc)
  if header ~= (history.header or "\n") then ev("Set Header", history.path, header) end
  -- the fold keeps the old entries in their order and puts new ones after; anything else is a move
  local expected = {}
  for _, id in ipairs(old_order) do
    for _, o in ipairs(order) do if o == id then expected[#expected + 1] = id end end
  end
  for _, e in ipairs(doc.entries) do
    if not e.before and not has_tag(e, "ARCHIVE") then expected[#expected + 1] = e.props.ID end
  end
  if not same_list(order, expected) then ev("Move Entry", history.path, table.concat(order, " ")) end
  return { events = events, entries = out, header = header, archived = archived, order = order, next_id = next_id }
end

return M
