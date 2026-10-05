-- The program as rows (M6a): the rows are the program, and its file is real org (core/tablua/org.lua;
-- owner, 2026-10-04), a compile target with its sections in a fixed order: notes, tests, keywords, code, page
-- (markup). Keywords and code carry their language (lang; Lua when none is given): Lua is the harness's language,
-- not the output's (owner, 2026-10-05). A Lua section is cut into its top-level statements (units: an action, a
-- function, a local, a keyword, any other statement), each with the blank lines and comments above it; the tests,
-- in Robot Framework's syntax (core/robot; owner, 2026-10-05: Robot, not Gherkin, since it is the models that read
-- them), into their head (settings, variables) and their items, each test, task or user keyword, whose calls are
-- kept as rows too (a task is a test that does a job rather than checks one: Robot's *** Tasks ***); a section in any other language is one unit, its whole text. Every cut falls between lines, so nothing
-- is lost: compile(decode(org)) is org, byte for byte, for a compiled file, and each section's text comes back whole.
--
--   local src = require("tablua.source")
--   local rows = src.decode(org)        -> { sections = { { kind, body, units?, items? }, ... } }
--   local org = src.compile(rows)
--   local rows = src.from_files{ tests = t, keywords = k, code = c, markup = m, notes = n, lang? }
--   local rows = src.from_lui(text)     -- a .lui page in tagged sections
--   src.tests(text) -> head, items      items { { kind = "test" | "task" | "keyword", name, text } }
--   src.calls(item) -> { { path, keyword, args } }   an item's calls, FOR and IF bodies included ("2.1")
local org = require("tablua.org")
local robot = require("robot")

local M = {}

M.order = { "notes", "tests", "keywords", "code", "markup" }
-- a .lui page's tags, by section: its code is in <lua>
local TAG = { notes = "notes", tests = "tests", keywords = "keywords", code = "lua" }

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
  name = s:match('^keyword%(%s*"([^"]*)"') or s:match("^keyword%(%s*'([^']*)'")
    or s:match('^test%.keyword%(%s*"([^"]*)"') or s:match("^test%.keyword%(%s*'([^']*)'")
  if name then return "keyword", name end
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

-- Robot: the head, then each test and user keyword, with its calls ------------------------------------------------

function M.tests(text)
  return robot.parse.cut(text)
end

-- the calls an item makes, in order, with their place in its body: FOR and IF bodies one level down
function M.calls(item)
  local header = ({ keyword = "*** Keywords ***\n", task = "*** Tasks ***\n" })[item.kind] or "*** Test Cases ***\n"
  local suite = robot.parse(header .. item.text:gsub("^%*%*%*[^\n]*\n", ""))
  local it = suite.tests[1] or suite.tasks[1] or suite.keywords[1]
  local out = {}
  local function walk(body, prefix)
    for i, x in ipairs(body or {}) do
      local path = prefix == "" and tostring(i) or (prefix .. "." .. i)
      if x.kind == "call" then
        out[#out + 1] = { path = path, keyword = x.keyword, args = x.args }
      elseif x.kind == "for" then
        walk(x.body, path)
      elseif x.kind == "if" then
        for j, b in ipairs(x.branches) do walk(b.body, path .. "." .. j) end
        if x.otherwise then walk(x.otherwise, path .. ".e") end
      end
    end
  end
  if it then
    for _, f in ipairs({ it.setup, it.teardown }) do
      if f and f.keyword then out[#out + 1] = { path = f == it.setup and "s" or "t", keyword = f.keyword, args = f.args } end
    end
    walk(it.body, "")
  end
  return out
end

-- Sections ---------------------------------------------------------------------------------------------------------

local function section(kind, body, lang)
  if body ~= "" and body:sub(-1) ~= "\n" then body = body .. "\n" end
  local s = { kind = kind, body = body, lang = lang }
  if kind == "code" or kind == "keywords" then
    s.units = M.lua(s) and M.units(body) or { { kind = "block", name = "", source = body } }
  end
  if kind == "tests" then s.head, s.items = M.tests(body) end
  return s
end

-- the body a section's rows give back: its units, or its head and items, joined
function M.body(s)
  if s.units then
    local parts = {}
    for i, u in ipairs(s.units) do parts[i] = u.source end
    return table.concat(parts)
  end
  if s.items then
    local parts = { s.head or "" }
    for _, it in ipairs(s.items) do parts[#parts + 1] = it.text end
    return table.concat(parts)
  end
  return s.body or ""
end

-- a .lui page's tagged sections (<notes>, <tests>, <keywords>, <lua>, then markup) as rows
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
      out[#out + 1] = { kind = kind, units = s.units, head = s.head, items = s.items, text = M.body(s),
        lang = s.lang or (kind == "markup" and "lui" or nil) }
    end
  end
  return org.write(out)
end

-- today's file kinds (a tests file, a keyword file, a module or a page's code, its markup, notes) as rows; f.lang,
-- the language of its keywords and code (Lua when none is given)
function M.from_files(f)
  local sections = {}
  for _, kind in ipairs(M.order) do
    if f[kind] and f[kind] ~= "" then
      local lang = kind == "markup" and "lui" or (kind == "code" or kind == "keywords") and f.lang or nil
      sections[#sections + 1] = section(kind, f[kind], lang)
    end
  end
  return { sections = sections }
end

return M
