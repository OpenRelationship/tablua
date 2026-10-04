-- arock-log.manifest: a computer's or an app's manifest.org, read from its parsed org (arock-log.org) and checked.
--
--   local m, errs = manifest.read(doc)   -- doc from org.parse; errs by line, as org's are
--   m = { apps = { { address, name, line } }, tools = { name = tool }, order = { name, ... } }
--   tool = { name, line, run, description, args = { { name, type, choices, default, optional } },
--            every, on, net = { host, ... }, mail = { address, ... }, account, ask, publish, granted, from, output }
--   manifest.arg(text)   -- "city :: string" -> arg | nil, why
--
-- `* Apps` lists apps as links ([[org:fern/plants]]); `* Tools` holds one headline per tool: RUN names its code
-- (code/*.lua), its first paragraph says what it does, a description list gives its arguments, and properties
-- give its triggers (EVERY, ON) and the reach it asks for (NET, MAIL, ACCOUNT, ASK, PUBLISH). GRANTED is written
-- by the host alone, so an agent's manifest carrying it is refused here; the host reads it with { host = true }.
-- A tool a writ made (Arock feature notes) says so in FROM, the writ's address (note-3@2#1-62), and OUTPUT says in
-- words the form its result takes.
local org = require("arock-log.org")

local M = {}

M.PROPS = { RUN = true, NET = true, MAIL = true, ACCOUNT = true, ASK = true, PUBLISH = true, EVERY = true, ON = true,
  ID = true, FROM = true, OUTPUT = true }
M.TYPES = { string = true, number = true, bool = true }

-- "name :: string", "days :: number = 7", "note :: string?", "size :: one of small|large = small" (or small|large)
function M.arg(text)
  local name, spec = text:match("^%s*[-+]%s+([%a_][%w_%-]*)%s+::%s+(.-)%s*$")
  if not name then return nil, "an argument is - name :: type" end
  local a = { name = name }
  local body, default = spec:match("^(.-)%s*=%s*(.+)$")
  spec = body or spec
  a.default = default
  if spec:sub(-1) == "?" then a.optional, spec = true, spec:sub(1, -2) end
  local choices = spec:match("^one of%s+(.+)$") or (spec:find("|", 1, true) and spec)
  if choices then
    a.type, a.choices = "choice", {}
    for c in choices:gmatch("[^|%s]+") do a.choices[#a.choices + 1] = c end
    if #a.choices < 2 then return nil, "one of takes two choices or more, as a|b" end
  elseif M.TYPES[spec] then
    a.type = spec
  else
    return nil, "an argument's type is string, number, bool or one of a|b|c, not " .. spec
  end
  if a.default then
    local ok = a.type == "string" or (a.type == "number" and tonumber(a.default))
      or (a.type == "bool" and (a.default == "true" or a.default == "false"))
    if a.type == "choice" then
      for _, c in ipairs(a.choices) do if c == a.default then ok = true end end
    end
    if not ok then return nil, "the default " .. a.default .. " is not a " .. a.type end
  end
  return a
end

local DAY = { Mon = true, Tue = true, Wed = true, Thu = true, Fri = true, Sat = true, Sun = true }

local function clock(hhmm)
  local h, m = (hhmm or ""):match("^(%d%d?):(%d%d)$")
  return h and tonumber(h) < 24 and tonumber(m) < 60
end

-- a fixed offset from UTC, as UTC-07:00 or UTC+05:30 (the node has no zone database; the Mac writes the person's)
local function offset(z)
  local h, m = (z or ""):match("^UTC[%+%-](%d%d):(%d%d)$")
  return h ~= nil and tonumber(h) <= 14 and (m == "00" or m == "30" or m == "45")
end

-- hourly | daily HH:MM | weekdays HH:MM | weekly Mon HH:MM | every 15m, 2h, 1d; a clock may end in an offset
function M.every(s)
  if s == "hourly" then return true end
  local body, z = s:match("^(.-)%s+(UTC%S*)$")
  if body then
    if not offset(z) or not (body:match("^daily ") or body:match("^weekdays ") or body:match("^weekly ")) then return false end
    s = body
  end
  local t = s:match("^daily%s+(%S+)$") or s:match("^weekdays%s+(%S+)$")
  if t then return clock(t) end
  local d, t2 = s:match("^weekly%s+(%a+)%s+(%S+)$")
  if d then return DAY[d] and clock(t2) end
  local n = s:match("^every%s+(%d+)[mhd]$")
  return n ~= nil and tonumber(n) > 0
end

local function words(s) local out = {} for w in (s or ""):gmatch("[^%s,]+") do out[#out + 1] = w end return out end

local function tool_of(e, errs, opts)
  local t = { name = e.title, line = e.line, args = {}, net = {}, mail = {} }
  local function bad(msg) errs[#errs + 1] = { line = e.line, msg = "the tool " .. e.title .. ": " .. msg } end
  if not e.title:match("^[a-z][a-z0-9%-]*$") then bad("a tool's name is a-z, 0-9 and -, as weather or post-summary") end
  for _, key in ipairs(e.order) do
    local v = e.props[key]
    if key == "GRANTED" then
      if opts.host then t.granted = v else bad("GRANTED is written by the host when the person says yes, never by an agent") end
    elseif not M.PROPS[key] then
      bad(key .. " is not a tool property (RUN, NET, MAIL, ACCOUNT, ASK, PUBLISH, EVERY, ON, FROM, OUTPUT)")
    elseif key == "RUN" then
      if not v:match("^code/[%w_%-/]+%.lua$") then bad("RUN names a code file, as code/weather.lua") end
      t.run = v
    elseif key == "NET" then
      t.net = words(v)
      for _, h in ipairs(t.net) do
        if not h:match("^[%w%-]+%.[%w%.%-]+$") then bad("NET lists host names, as api.open-meteo.com, not " .. h) end
      end
    elseif key == "MAIL" then
      t.mail = words(v)
      for _, a in ipairs(t.mail) do if not org.address(a) then bad("MAIL lists org: addresses, not " .. a) end end
    elseif key == "ACCOUNT" then
      if not v:match("^[a-z][a-z0-9%-]*$") then bad("ACCOUNT names one app, as slack") end
      t.account = v
    elseif key == "ASK" or key == "PUBLISH" then
      if v ~= "" and v ~= "yes" then bad(key .. " is set alone (:" .. key .. ":) or to yes") end
      t[key:lower()] = true
    elseif key == "EVERY" then
      if not M.every(v) then
        bad("EVERY is hourly, daily HH:MM, weekdays HH:MM, weekly Mon HH:MM (each may end in an offset, as UTC-07:00)"
          .. " or every 15m, 2h, 1d, not " .. v)
      end
      t.every = v
    elseif key == "FROM" then
      if not v:match("^note%-%d+@%d+#[%d%-,]+$") then bad("FROM is a writ's address, as note-3@2#1-62") end
      t.from = v
    elseif key == "OUTPUT" then
      t.output = v
    elseif key == "ON" then
      if v ~= "mail" and not v:match("^write%s+%S+$") then bad("ON is mail, or write and a path pattern") end
      t.on = v
    end
  end
  if not t.run then bad("RUN names the code it runs") end
  local n = e.line
  for _, line in ipairs(e.body) do
    n = n + 1
    if line:match("^%s*[-+]%s+.*%s::%s") or line:match("^%s*[-+]%s+.*%s::$") then
      local a, why = M.arg(line)
      if a then t.args[#t.args + 1] = a else bad(why) end
    elseif line:match("%S") and not t.description and not line:match("^%s*[-+|#]") then
      t.description = line:match("^%s*(.-)%s*$")
    end
  end
  if not t.description then bad("its first paragraph says what it does, for the person and for the models") end
  return t
end

function M.read(doc, opts)
  opts = opts or {}
  local m, errs = { apps = {}, tools = {}, order = {} }, {}
  local section
  for _, e in ipairs(doc.entries) do
    if e.level == 1 then
      section = e.title
      if section ~= "Apps" and section ~= "Tools" then
        errs[#errs + 1] = { line = e.line, msg = "a manifest's headings are * Apps and * Tools, not " .. section }
      end
      if section == "Apps" then
        local n = e.line
        for _, line in ipairs(e.body) do
          n = n + 1
          if line:match("%S") then
            local target = line:match("^%s*[-+]%s+%[%[(org:[^%]]+)%]")
            local parts = target and org.address(target)
            if not parts or #parts ~= 2 then
              errs[#errs + 1] = { line = n, msg = "an app is listed as - [[org:<computer>/<app>]]" }
            else
              m.apps[#m.apps + 1] = { address = target, name = parts[2], line = n }
            end
          end
        end
      end
    elseif section == "Tools" and e.level == 2 then
      local t = tool_of(e, errs, opts)
      if m.tools[t.name] then errs[#errs + 1] = { line = e.line, msg = "the tool " .. t.name .. " is declared twice" } end
      m.tools[t.name] = t
      m.order[#m.order + 1] = t.name
    elseif e.level == 2 then
      errs[#errs + 1] = { line = e.line, msg = "only * Tools holds headlines in a manifest" }
    end
    if e.keyword then errs[#errs + 1] = { line = e.line, msg = "a manifest declares; its tasks go in an org file" } end
  end
  return m, errs
end

return M
