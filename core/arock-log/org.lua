-- arock-log.org: the org an agent writes, parsed into entries and checked against the subset we speak.
--
--   local doc, errs = org.parse(text)   -- errs: { { line = n, msg = "..." }, ... }, empty when the text is ours
--   org.render(doc)                     -- the text again, in one canonical form (read back from the fold)
--
-- The subset: `#+TITLE`, `#+DATE`, `#+FILETAGS`; headlines with a keyword (TODO, WAIT, DONE, DROP), a priority
-- ([#A] to [#C]) and tags; one planning line (SCHEDULED, DEADLINE, CLOSED); a property drawer and a LOGBOOK;
-- paragraphs, lists, checkboxes, description lists, tables and quote, example and source blocks, kept as text.
-- Links name id:, org:, file:, mail:, feature:, http: or https:. Nothing in an org file runs: Babel (header
-- arguments, #+CALL, inline src_ and call_), macros, #+INCLUDE and #+SETUPFILE are refused, each by its line.
--
-- doc = { title, date, filetags = {...}, preamble = { lines }, entries = { entry, ... } }
-- entry = { line, level, keyword, priority, title, tags = {...}, scheduled, deadline, closed,
--           props = { KEY = value }, order = { KEY, ... }, logbook = { lines }, body = { lines },
--           links = { { target, line } }, parent = index or nil }
-- A date is { y, m, d, hh, mm, active, repeat } and renders back with its weekday computed.
local M = {}

M.KEYWORDS = { TODO = true, WAIT = true, DONE = true, DROP = true }
M.SCHEMES = { id = true, org = true, file = true, mail = true, feature = true, http = true, https = true }
M.FILE_KEYS = { TITLE = true, DATE = true, FILETAGS = true }
M.BLOCKS = { QUOTE = true, EXAMPLE = true, SRC = true }
-- words that look like a keyword elsewhere in org but are not ours
local LOOKALIKE = { NEXT = true, DOING = true, STARTED = true, WAITING = true, HOLD = true, CANCELED = true,
  CANCELLED = true }

local DAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function leap(y) return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 end

-- Sakamoto's method: 0 is Sunday
local function weekday(y, m, d)
  local t = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
  if m < 3 then y = y - 1 end
  return (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + t[m] + d) % 7
end
M.weekday = function(y, m, d) return DAYS[weekday(y, m, d) + 1] end

-- "<2026-10-02 Fri 09:30 +1w>" or "[...]"; the weekday may be any word (it is recomputed)
function M.date(s)
  local open, inner, close = s:match("^([<%[])(.-)([>%]])$")
  if not open or (open == "<") ~= (close == ">") then return nil, "a date is <YYYY-MM-DD> or [YYYY-MM-DD]" end
  local y, m, d, rest = inner:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$")
  if not y then return nil, "a date starts YYYY-MM-DD" end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m < 1 or m > 12 then return nil, "no month " .. m end
  local most = MONTH_DAYS[m] + ((m == 2 and leap(y)) and 1 or 0)
  if d < 1 or d > most then return nil, ("no day %d in %04d-%02d"):format(d, y, m) end
  local out = { y = y, m = m, d = d, active = open == "<" }
  for word in rest:gmatch("%S+") do
    local hh, mm = word:match("^(%d%d?):(%d%d)$")
    if hh then
      hh, mm = tonumber(hh), tonumber(mm)
      if hh > 23 or mm > 59 then return nil, "no time " .. word end
      out.hh, out.mm = hh, mm
    elseif word:match("^%+%d+[dwmy]$") then
      out["repeat"] = word
    elseif not word:match("^%a+%.?$") then
      return nil, "a date holds a day, a time (HH:MM) and a repeat (+1w), not " .. word
    end
  end
  return out
end

-- "org:fern/plants/weather" -> { "fern", "plants", "weather" }; a computer or segment is a-z, 0-9 and -, at most 64
function M.address(s)
  local rest = type(s) == "string" and s:match("^org:(.+)$")
  if not rest then return nil, "an address is org:<computer>/<path>" end
  local parts = {}
  for seg in (rest .. "/"):gmatch("(.-)/") do
    if not seg:match("^[a-z0-9][a-z0-9%-]*$") or #seg > 64 then
      return nil, "an address's parts are a-z, 0-9 and -, at most 64: " .. s
    end
    parts[#parts + 1] = seg
  end
  return parts
end

function M.date_text(t)
  local s = ("%04d-%02d-%02d %s"):format(t.y, t.m, t.d, M.weekday(t.y, t.m, t.d))
  if t.hh then s = s .. (" %02d:%02d"):format(t.hh, t.mm) end
  if t["repeat"] then s = s .. " " .. t["repeat"] end
  return t.active and ("<" .. s .. ">") or ("[" .. s .. "]")
end

local function lines_of(text)
  local out = {}
  for line in (text:gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
  if out[#out] == "" then out[#out] = nil end
  return out
end

-- every link on a line; a bad scheme or a macro or inline Babel is an error
local function scan_text(line, n, links, errs)
  for target in line:gmatch("%[%[([^%[%]]*)%]") do
    local scheme = target:match("^(%a[%w+.-]*):")
    if not scheme then
      errs[#errs + 1] = { line = n, msg = "a link names its scheme (id:, org:, file:, mail:, feature:, https:): " .. target }
    elseif not M.SCHEMES[scheme] then
      errs[#errs + 1] = { line = n, msg = "a link of scheme " .. scheme .. ": is outside the org we speak" }
    elseif scheme == "org" and not M.address(target) then
      errs[#errs + 1] = { line = n, msg = select(2, M.address(target)) }
    else
      links[#links + 1] = { target = target, line = n }
    end
  end
  if line:find("{{{", 1, true) then errs[#errs + 1] = { line = n, msg = "macros ({{{ }}}) are outside the org we speak" } end
  if line:match("src_[%w-]+[%[{]") or line:match("call_[%w-]+[%[(]") then
    errs[#errs + 1] = { line = n, msg = "inline Babel (src_, call_) is outside the org we speak: nothing in org runs" }
  end
end

-- s without its outer whitespace. Linear: (.-)%s*$ and gsub("%s+$", "") go back over a run of spaces from each
-- place in it, so a hostile line of spaces costs its length squared.
local function trim(s) return (s:match("^.*%S") or ""):match("^%s*(.*)$") end

local function headline(line, n, errs)
  local stars, rest = line:match("^(%*+)%s+(.*)$")
  local e = { line = n, level = #stars, tags = {}, props = {}, order = {}, logbook = {}, body = {}, links = {} }
  local first, after = rest:match("^(%S+)%s*(.*)$")
  if first and M.KEYWORDS[first] then
    e.keyword, rest = first, after
  elseif first and LOOKALIKE[first] then
    errs[#errs + 1] = { line = n, msg = first .. " is not a keyword we speak: use TODO, WAIT, DONE or DROP" }
  end
  local p, after2 = rest:match("^%[#(%a)%]%s*(.*)$")
  if p then
    if not p:match("^[ABC]$") then errs[#errs + 1] = { line = n, msg = "a priority is [#A], [#B] or [#C]" } end
    e.priority, rest = p, after2
  end
  rest = trim(rest)
  local tags = rest:match("^(:[%w_@#%%:]+:)$") or rest:match("%s(:[%w_@#%%:]+:)$")
  e.title = tags and trim(rest:sub(1, #rest - #tags)) or rest
  if tags then for tag in tags:gmatch("[^:]+") do e.tags[#e.tags + 1] = tag end end
  if e.title == "" then errs[#errs + 1] = { line = n, msg = "a headline has a title" } end
  return e
end

local function planning(line, e, n, errs)
  local any = false
  for word, stamp in line:gmatch("(%u+):%s*([<%[][^<>%[%]]*[>%]])") do
    any = true
    local key = word:lower()
    if key ~= "scheduled" and key ~= "deadline" and key ~= "closed" then
      errs[#errs + 1] = { line = n, msg = word .. " is not a planning word (SCHEDULED, DEADLINE, CLOSED)" }
    else
      local t, why = M.date(stamp)
      if not t then errs[#errs + 1] = { line = n, msg = word .. ": " .. why } else e[key] = t end
    end
  end
  return any
end

function M.parse(text)
  local doc = { filetags = {}, preamble = {}, entries = {} }
  local errs = {}
  local lines = lines_of(text)
  local cur, stack = nil, {}
  local block, drawer -- the open block's name; the open drawer's name
  local state         -- "head" right after a headline, "planline" after planning lines, "props" after its drawer, then "body"
  for n, line in ipairs(lines) do
    local target = cur and cur.body or doc.preamble
    if block then
      if line:match("^%s*#%+[Ee][Nn][Dd]_(%a+)%s*$") and line:match("_(%a+)"):upper() == block then block = nil end
      target[#target + 1] = line
    elseif drawer then
      if line:match("^%s*:END:%s*$") then
        drawer = nil
      elseif drawer == "PROPERTIES" then
        local key, value = line:match("^%s*:([%w_%-]+):(.*)$")
        value = value and trim(value)
        if not key then
          errs[#errs + 1] = { line = n, msg = "a property is :KEY: value" }
        else
          key = key:upper()
          if cur.props[key] ~= nil then errs[#errs + 1] = { line = n, msg = "the property " .. key .. " is set twice" } end
          if cur.props[key] == nil then cur.order[#cur.order + 1] = key end
          cur.props[key] = value
        end
      else
        cur.logbook[#cur.logbook + 1] = (line:gsub("^%s+", ""))
      end
    elseif line:match("^%*+%s") then
      cur = headline(line, n, errs)
      while #stack > 0 and doc.entries[stack[#stack]].level >= cur.level do stack[#stack] = nil end
      cur.parent = stack[#stack]
      doc.entries[#doc.entries + 1] = cur
      stack[#stack + 1] = #doc.entries
      scan_text(cur.title, n, cur.links, errs)
      state = "head"
    elseif line:match("^%s*:(%u+):%s*$") then
      local name = line:match(":(%u+):")
      if name == "END" then
        errs[#errs + 1] = { line = n, msg = ":END: closes nothing" }
      elseif not cur then
        errs[#errs + 1] = { line = n, msg = "a drawer belongs under a headline" }
      elseif name == "PROPERTIES" then
        if state ~= "head" and state ~= "planline" then
          errs[#errs + 1] = { line = n, msg = "the property drawer comes right after the headline (and its planning line)" }
        end
        drawer, state = name, "props"
      elseif name == "LOGBOOK" then
        drawer = name
      else
        errs[#errs + 1] = { line = n, msg = "the drawer :" .. name .. ": is outside the org we speak (PROPERTIES, LOGBOOK)" }
        drawer = name
      end
    elseif line:match("^%s*#%+") then
      local key, value = line:match("^%s*#%+([%w_]+):?(.*)$")
      value = value and trim(value)
      key = (key or ""):upper()
      local bname = key:match("^BEGIN_(%a+)$")
      if bname then
        if not M.BLOCKS[bname] then
          errs[#errs + 1] = { line = n, msg = "#+BEGIN_" .. bname .. " is outside the org we speak (QUOTE, EXAMPLE, SRC)" }
        elseif bname == "SRC" and value:find(":", 1, true) then
          errs[#errs + 1] = { line = n, msg = "a source block takes only its language: header arguments are Babel, and nothing in org runs" }
        end
        block = bname
        target[#target + 1] = line
      elseif cur == nil and M.FILE_KEYS[key] then
        if key == "TITLE" then doc.title = value
        elseif key == "DATE" then doc.date = value
        else for tag in value:gmatch("[^:%s]+") do doc.filetags[#doc.filetags + 1] = tag end end
      else
        errs[#errs + 1] = { line = n, msg = "#+" .. key .. " is outside the org we speak" ..
          ((key == "INCLUDE" or key == "SETUPFILE" or key == "CALL") and ": nothing in org runs or reads another file" or "") }
      end
    elseif cur and (state == "head" or state == "planline") and line:match("^%s*%u+:%s*[<%[]")
      and planning(line, cur, n, errs) then
      state = "planline"
    else
      if line:match("%S") then state = "body" end
      target[#target + 1] = line
      scan_text(line, n, cur and cur.links or {}, errs)
      local box = line:match("^%s*[-+]%s+%[(.)%]") or line:match("^%s*%d+[.)]%s+%[(.)%]")
      if box and not box:match("^[ X%-]$") then
        errs[#errs + 1] = { line = n, msg = "a checkbox is [ ], [X] or [-]" }
      end
    end
  end
  if block then errs[#errs + 1] = { line = #lines, msg = "#+BEGIN_" .. block .. " is never ended" } end
  if drawer then errs[#errs + 1] = { line = #lines, msg = "the drawer :" .. drawer .. ": is never closed with :END:" } end
  return doc, errs
end

local function trim_end(list)
  local n = #list
  while n > 0 and not list[n]:match("%S") do n = n - 1 end
  local out = {}
  for i = 1, n do out[i] = list[i] end
  return out
end

function M.render(doc)
  local out = {}
  if doc.title then out[#out + 1] = "#+TITLE: " .. doc.title end
  if doc.date then out[#out + 1] = "#+DATE: " .. doc.date end
  if doc.filetags and #doc.filetags > 0 then out[#out + 1] = "#+FILETAGS: :" .. table.concat(doc.filetags, ":") .. ":" end
  local pre = trim_end(doc.preamble or {})
  if #out > 0 and #pre > 0 then out[#out + 1] = "" end
  for _, l in ipairs(pre) do out[#out + 1] = l end
  for _, e in ipairs(doc.entries) do
    if #out > 0 then out[#out + 1] = "" end
    local h = ("*"):rep(e.level)
    if e.keyword then h = h .. " " .. e.keyword end
    if e.priority then h = h .. " [#" .. e.priority .. "]" end
    if e.title ~= "" then h = h .. " " .. e.title end
    if #e.tags > 0 then h = h .. " :" .. table.concat(e.tags, ":") .. ":" end
    out[#out + 1] = h
    local plan = {}
    for _, key in ipairs({ "closed", "scheduled", "deadline" }) do
      if e[key] then plan[#plan + 1] = key:upper() .. ": " .. M.date_text(e[key]) end
    end
    if #plan > 0 then out[#out + 1] = table.concat(plan, " ") end
    if #e.order > 0 then
      out[#out + 1] = ":PROPERTIES:"
      for _, key in ipairs(e.order) do out[#out + 1] = ":" .. key .. ": " .. e.props[key] end
      out[#out + 1] = ":END:"
    end
    if #e.logbook > 0 then
      out[#out + 1] = ":LOGBOOK:"
      for _, l in ipairs(e.logbook) do out[#out + 1] = l end
      out[#out + 1] = ":END:"
    end
    local body = trim_end(e.body)
    local first = 1
    while body[first] and not body[first]:match("%S") do first = first + 1 end
    for i = first, #body do out[#out + 1] = body[i] end
  end
  return table.concat(out, "\n") .. "\n"
end

return M
