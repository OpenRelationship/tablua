-- The program as rows (issue #2, M6a): the rows are the program, and its file is real org (core/tablua/org.lua;
-- owner, 2026-10-04), a compile target with its sections in a fixed order: notes, feature, steps, code, page
-- (markup). Steps and code carry their language (lang; Lua when none is given): Lua is the harness's language, not
-- the output's (owner, 2026-10-05). A Lua section is cut into its top-level statements (units: an action, a function, a local, a step, any
-- other statement), each with the blank lines and comments above it; a feature into its header and its scenarios,
-- each scenario's step lines kept as rows too; a section in any other language is one unit, its whole text. Every cut falls between lines, so nothing is lost:
-- compile(decode(org)) is org, byte for byte, for a compiled file, and each section's text comes back whole.
--
--   local src = require("tablua.source")
--   local rows = src.decode(org)        -> { sections = { { kind, body, units?, scenarios? }, ... } }
--   local org = src.compile(rows)
--   local rows = src.from_files{ feature = f, steps = s, code = c, markup = m, notes = n, lang? }
--   local rows = src.from_lui(text)     -- a .lui page in Shroomi's tagged sections, until Shroomi goes
local org = require("tablua.org")

local M = {}

M.order = { "notes", "feature", "steps", "code", "markup" }
-- a .lui page's tags, by section: its code is in <lua>
local TAG = { notes = "notes", feature = "feature", steps = "steps", code = "lua" }

-- whether a section's text is Lua: its lang, or none given
function M.lua(s) return (s.lang or "lua") == "lua" end

-- Lua: where the top-level statements are -----------------------------------------------------------------------

-- the block and bracket depth a line leaves, and whether it ends inside a long string or comment
local function scan(line, st)
  local i, n = 1, #line
  while i <= n do
    if st.long then
      local close = "]" .. st.long .. "]"
      local j = line:find(close, i, true)
      if not j then return end
      i, st.long = j + #close, nil
    else
      local c = line:sub(i, i)
      if c == "-" and line:sub(i, i + 1) == "--" then
        local eq = line:match("^%[(=*)%[", i + 2)
        if eq then st.long, i = eq, i + 4 + #eq else return end
      elseif c == "[" and line:match("^%[=*%[", i) then
        local eq = line:match("^%[(=*)%[", i)
        st.long, i = eq, i + 2 + #eq
      elseif c == '"' or c == "'" then
        local j = i + 1
        while j <= n do
          local d = line:sub(j, j)
          if d == "\\" then j = j + 2 elseif d == c then break else j = j + 1 end
        end
        i = j + 1
      elseif c:match("[%a_]") then
        local word = line:match("^[%w_]+", i)
        if word == "function" or word == "if" or word == "do" or word == "repeat" then st.block = st.block + 1
        elseif word == "end" or word == "until" then st.block = st.block - 1 end
        i = i + #word
      elseif c == "(" or c == "{" then st.bracket, i = st.bracket + 1, i + 1
      elseif c == ")" or c == "}" then st.bracket, i = st.bracket - 1, i + 1
      else i = i + 1 end
    end
  end
end

-- a line that continues the statement above it rather than starting one
local function continues(line)
  local s = line:match("^%s*(.-)%s*$")
  return s:match("^[%.:%(%[,]") or s:match("^%.%.") or s:match("^or%f[^%w_]") or s:match("^and%f[^%w_]")
    or s:match("^[%+%-%*/%%^=<>~]") and not s:match("^%-%-")
end

local function blank_or_comment(line) return line:match("^%s*$") or line:match("^%s*%-%-") end

-- the kind and name of a top-level statement, from its first code line
function M.classify(code)
  local s = code:match("^%s*(.-)%s*$")
  local name = s:match("^function%s+(post%.[%w_]+)") or s:match("^function%s+(get%.[%w_]+)")
  if name then return "action", name end
  name = s:match("^local%s+function%s+([%w_]+)") or s:match("^function%s+([%w_%.:]+)")
  if name then return "fn", name end
  name = s:match('^test%.step%(%s*"([^"]*)"') or s:match("^test%.step%(%s*'([^']*)'")
  if name then return "step", name end
  name = s:match("^local%s+([%w_]+)")
  if name then return "local", name end
  if s == "return" or s:match("^return[^%w_]") then return "stmt", "return" end
  name = s:match("^([%w_%.]+)%s*=") or s:match("^([%w_%.:]+)%s*%(")
  return "stmt", name or ""
end

-- top-level units of Lua text: { { kind, name, source } }, their sources concatenated being the text
function M.units(text)
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  if text:sub(-1) == "\n" or text == "" then lines[#lines] = nil end
  local out, cur, code_seen = {}, {}, nil
  local st = { block = 0, bracket = 0 }
  local function flush()
    if #cur == 0 then return end
    local kind, name = M.classify(code_seen or "")
    out[#out + 1] = { kind = code_seen and kind or "stmt", name = code_seen and name or "", source = table.concat(cur) }
    cur, code_seen = {}, nil
  end
  local pending = {}   -- blank and comment lines at the top level, given to the statement that follows them
  for idx, line in ipairs(lines) do
    local nl = (idx < #lines or text:sub(-1) == "\n") and "\n" or ""
    local top = st.block <= 0 and st.bracket <= 0 and not st.long
    if top and code_seen and blank_or_comment(line) then
      pending[#pending + 1] = line .. nl
    else
      -- a new statement starts at the top level, on a code line that does not continue the one above
      if top and code_seen and not continues(line) then
        flush()
      end
      for _, p in ipairs(pending) do cur[#cur + 1] = p end
      pending = {}
      cur[#cur + 1] = line .. nl
      if not code_seen and not blank_or_comment(line) then code_seen = line end
    end
    scan(line, st)
  end
  for _, p in ipairs(pending) do cur[#cur + 1] = p end
  flush()
  return out
end

-- Gherkin: the header, then each scenario with its step lines ----------------------------------------------------

local KEYWORDS = { Given = true, When = true, Then = true, And = true, But = true }

function M.scenarios(text)
  local head, out, cur = {}, {}, nil
  for line in text:gmatch("[^\n]*\n?") do
    if line == "" then break end
    local name = line:match("^%s*Scenario[ %w]*:%s*(.-)%s*$")
    if name then
      cur = { name = name, text = { line }, lines = {} }
      out[#out + 1] = cur
    elseif cur then
      cur.text[#cur.text + 1] = line
      local kw, rest = line:match("^%s*(%a+)%s+(.-)%s*$")
      if kw and KEYWORDS[kw] then cur.lines[#cur.lines + 1] = { keyword = kw, text = rest } end
    else
      head[#head + 1] = line
    end
  end
  for _, s in ipairs(out) do s.text = table.concat(s.text) end
  return table.concat(head), out
end

-- Sections ---------------------------------------------------------------------------------------------------------

local function section(kind, body, lang)
  if body ~= "" and body:sub(-1) ~= "\n" then body = body .. "\n" end
  local s = { kind = kind, body = body, lang = lang }
  if kind == "code" or kind == "steps" then
    s.units = M.lua(s) and M.units(body) or { { kind = "block", name = "", source = body } }
  end
  if kind == "feature" then s.head, s.scenarios = M.scenarios(body) end
  return s
end

-- the body a section's rows give back: its units, or its header and scenarios, joined
function M.body(s)
  if s.units then
    local parts = {}
    for i, u in ipairs(s.units) do parts[i] = u.source end
    return table.concat(parts)
  end
  if s.scenarios then
    local parts = { s.head or "" }
    for _, sc in ipairs(s.scenarios) do parts[#parts + 1] = sc.text end
    return table.concat(parts)
  end
  return s.body or ""
end

-- a .lui page's tagged sections (<notes>, <feature>, <steps>, <lua>, then markup) as rows
function M.from_lui(text)
  local sections, rest = {}, text
  for _, kind in ipairs(M.order) do
    local tag = TAG[kind]
    if tag then
      local open, body, close = rest:match("^%s*()<" .. tag .. ">\n?(.-)</" .. tag .. ">\n*()")
      if open then
        sections[#sections + 1] = section(kind, body)
        rest = rest:sub(close)
      end
    end
  end
  if rest ~= "" then sections[#sections + 1] = section("markup", rest, "lui") end
  return { sections = sections }
end

-- rows from an org file, or nil and why it is not one
function M.decode(text)
  local read, why = org.read(text)
  if not read then return nil, why end
  local sections = {}
  for i, r in ipairs(read) do sections[i] = section(r.kind, r.text, r.lang) end
  return { sections = sections }
end

-- the org file: sections in order, each row a heading of its own
function M.compile(rows)
  local by = {}
  for _, s in ipairs(rows.sections) do by[s.kind] = s end
  local out = {}
  for _, kind in ipairs(M.order) do
    local s = by[kind]
    if s then
      out[#out + 1] = { kind = kind, units = s.units, head = s.head, scenarios = s.scenarios, text = M.body(s),
        lang = s.lang or (kind == "markup" and "lui" or nil) }
    end
  end
  return org.write(out)
end

-- today's file kinds (a feature, a step file, a module or a page's code, its markup, notes) as rows; f.lang, the
-- language of its steps and code (Lua when none is given)
function M.from_files(f)
  local sections = {}
  for _, kind in ipairs(M.order) do
    if f[kind] and f[kind] ~= "" then
      local lang = kind == "markup" and "lui" or (kind == "code" or kind == "steps") and f.lang or nil
      sections[#sections + 1] = section(kind, f[kind], lang)
    end
  end
  return { sections = sections }
end

return M
