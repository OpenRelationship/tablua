-- Robot Framework's test data, read in portable Lua: the subset an agent's tests need. A file has sections
-- (*** Settings ***, *** Variables ***, *** Test Cases *** or *** Tasks ***, *** Keywords ***, *** Comments ***);
-- cells are split by a tab or two or more spaces; a line starting with ... continues the one above; # starts a
-- comment. A test or keyword is a line at the left edge, its body the indented lines under it.
--
--   local parse = require("robot.parse")
--   parse.suite(text) -> { settings, variables, tests, keywords }
--     settings  { setup, teardown, test_setup, test_teardown, tags, libraries, documentation }
--     variables { [name] = value | list }                  ${x} as written, @{x} as a list
--     tests     { { name, line, doc, tags, setup, teardown, body } }
--     keywords  { { name, line, doc, args, returns, teardown, body } }
--   a body is a list of items:
--     { kind = "call", keyword, args, assign = { "${x}" }?, line }
--     { kind = "for", var(s), flavor = "in" | "range", values, body, line }
--     { kind = "if", branches = { { cond, body } }, otherwise = body?, line }
--     { kind = "return", values, line }   { kind = "break" | "continue", line }
--   parse.cut(text) -> head, { { kind = "test" | "keyword", name, text } }   head .. every item's text is the text,
--     byte for byte; a section's header line goes with the item after it
--   parse.cells(line) -> the line's cells, its indent as an empty first cell
local M = {}

local SECTIONS = { ["settings"] = "settings", ["setting"] = "settings", ["variables"] = "variables",
  ["variable"] = "variables", ["test cases"] = "tests", ["test case"] = "tests", ["tasks"] = "tests",
  ["task"] = "tests", ["keywords"] = "keywords", ["keyword"] = "keywords", ["comments"] = "comments",
  ["comment"] = "comments" }

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- the section a header line opens, or nil when the line is not a header
function M.header(line)
  local name = line:match("^%*+%s*(.-)%s*%**%s*$")
  if not name or not line:match("^%*") then return nil end
  return SECTIONS[name:lower()] or "unknown"
end

function M.cells(line)
  line = line:gsub("\r$", "")
  local out = {}
  if line:match("^[ \t]") then out[1] = "" end
  local rest = trim(line)
  while rest ~= "" do
    local s, e = rest:find("\t+")
    local s2, e2 = rest:find("  +")
    if s2 and (not s or s2 < s) then s, e = s2, e2 end
    local cell = s and rest:sub(1, s - 1) or rest
    if cell:sub(1, 1) == "#" then break end
    out[#out + 1] = cell == "\\" and "" or cell
    rest = s and rest:sub(e + 1) or ""
  end
  return out
end

-- logical rows: { cells, line, indented }, with ... continuations joined to the row above
local function rows(text)
  local out, section = {}, nil
  local n = 0
  for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    local h = M.header(raw)
    if h then
      section = h
      out[#out + 1] = { header = h, line = n }
    elseif section ~= "comments" then
      local cells = M.cells(raw)
      local first = cells[1] == "" and 2 or 1
      if cells[first] == "..." and #out > 0 and not out[#out].header then
        for i = first + 1, #cells do out[#out].cells[#out[#out].cells + 1] = cells[i] end
      elseif #cells > (cells[1] == "" and 1 or 0) then
        out[#out + 1] = { cells = cells, line = n, indented = cells[1] == "", section = section }
      end
    end
  end
  return out
end

local function is_var(cell) return cell:match("^[%$@&]{.+}%s*=?$") ~= nil end

local function setting(cell) return cell:match("^%[(.-)%]$") end

-- a body built from rows of cells (indent stripped), with FOR and IF blocks closed by END
local function body_of(list)
  local root = {}
  local stack = { { items = root } }
  local function top() return stack[#stack] end
  for _, r in ipairs(list) do
    local c, line = r.cells, r.line
    local head = c[1]
    local items = top().items
    if head == "FOR" then
      local vars, i = {}, 2
      while c[i] and c[i]:match("^%${.+}$") do vars[#vars + 1] = c[i]; i = i + 1 end
      local flavor = (c[i] or ""):upper() == "IN RANGE" and "range" or "in"
      local values = {}
      for j = i + 1, #c do values[#values + 1] = c[j] end
      local block = { kind = "for", vars = vars, flavor = flavor, values = values, body = {}, line = line }
      items[#items + 1] = block
      stack[#stack + 1] = { items = block.body, block = block }
    elseif head == "IF" then
      local block = { kind = "if", branches = { { cond = c[2] or "", body = {} } }, line = line }
      items[#items + 1] = block
      stack[#stack + 1] = { items = block.branches[1].body, block = block }
    elseif head == "ELSE IF" and top().block and top().block.kind == "if" then
      local b = { cond = c[2] or "", body = {} }
      local blk = top().block
      blk.branches[#blk.branches + 1] = b
      top().items = b.body
    elseif head == "ELSE" and top().block and top().block.kind == "if" then
      top().block.otherwise = {}
      top().items = top().block.otherwise
    elseif head == "END" and #stack > 1 then
      stack[#stack] = nil
    elseif head == "RETURN" then
      local values = {}
      for j = 2, #c do values[#values + 1] = c[j] end
      items[#items + 1] = { kind = "return", values = values, line = line }
    elseif head == "BREAK" or head == "CONTINUE" then
      items[#items + 1] = { kind = head:lower(), line = line }
    else
      local assign, i = {}, 1
      while c[i] and is_var(c[i]) do assign[#assign + 1] = c[i]:gsub("%s*=$", ""); i = i + 1 end
      if c[i] then
        local args = {}
        for j = i + 1, #c do args[#args + 1] = c[j] end
        items[#items + 1] = { kind = "call", keyword = c[i], args = args, assign = #assign > 0 and assign or nil,
          line = line }
      end
    end
  end
  return root
end

local function rest(c, from)
  local out = {}
  for i = from or 2, #c do out[#out + 1] = c[i] end
  return out
end

-- one test or keyword from its rows: its own [Settings], then its body
local function item(kind, name, list, line)
  local it = { name = name, line = line, tags = {}, args = {}, body = {} }
  local steps = {}
  for _, r in ipairs(list) do
    local s = setting(r.cells[1])
    if s then
      local key = s:lower()
      if key == "documentation" then it.doc = table.concat(rest(r.cells), " ")
      elseif key == "tags" then it.tags = rest(r.cells)
      elseif key == "arguments" then it.args = rest(r.cells)
      elseif key == "return" then it.returns = rest(r.cells)
      elseif key == "setup" then it.setup = { keyword = r.cells[2], args = rest(r.cells, 3) }
      elseif key == "teardown" then it.teardown = { keyword = r.cells[2], args = rest(r.cells, 3) } end
    else
      steps[#steps + 1] = r
    end
  end
  it.body = body_of(steps)
  it.kind = kind
  return it
end

function M.suite(text)
  local suite = { settings = { tags = {}, libraries = {} }, variables = {}, tests = {}, keywords = {} }
  local cur, list = nil, nil
  local function close()
    if cur then
      local it = item(cur.kind, cur.name, list, cur.line)
      local into = cur.kind == "test" and suite.tests or suite.keywords
      into[#into + 1] = it
    end
    cur, list = nil, nil
  end
  for _, r in ipairs(rows(text)) do
    if r.header then
      close()
    elseif r.section == "tests" or r.section == "keywords" then
      if not r.indented then
        close()
        cur = { kind = r.section == "tests" and "test" or "keyword", name = r.cells[1], line = r.line }
        list = {}
        if #r.cells > 1 then list[1] = { cells = rest(r.cells), line = r.line } end
      elseif cur then
        list[#list + 1] = { cells = rest(r.cells), line = r.line }
      end
    elseif r.section == "settings" and not r.indented then
      local k, c = r.cells[1]:lower(), r.cells
      local s = suite.settings
      if k == "suite setup" then s.setup = { keyword = c[2], args = rest(c, 3) }
      elseif k == "suite teardown" then s.teardown = { keyword = c[2], args = rest(c, 3) }
      elseif k == "test setup" or k == "task setup" then s.test_setup = { keyword = c[2], args = rest(c, 3) }
      elseif k == "test teardown" or k == "task teardown" then s.test_teardown = { keyword = c[2], args = rest(c, 3) }
      elseif k == "test tags" or k == "force tags" or k == "task tags" then s.tags = rest(c)
      elseif k == "library" or k == "resource" then s.libraries[#s.libraries + 1] = c[2]
      elseif k == "documentation" then s.documentation = table.concat(rest(c), " ") end
    elseif r.section == "variables" and not r.indented then
      local name = r.cells[1]:gsub("%s*=$", "")
      local values = rest(r.cells)
      if name:sub(1, 1) == "@" then suite.variables[name] = values
      else suite.variables[name] = table.concat(values, " ") end
    end
  end
  close()
  return suite
end

function M.cut(text)
  local head, items, pending, section, cur = {}, {}, {}, nil, nil
  local lines = {}
  for line in text:gmatch("[^\n]*\n?") do
    if line == "" then break end
    lines[#lines + 1] = line
  end
  for _, line in ipairs(lines) do
    local h = M.header(line)
    if h then
      section = h
      cur = nil
      pending[#pending + 1] = line
    elseif (section == "tests" or section == "keywords") and line:match("^[^%s#]") and not line:match("^%.%.%.") then
      cur = { kind = section == "tests" and "test" or "keyword", name = M.cells(line)[1], parts = pending }
      pending = {}
      cur.parts[#cur.parts + 1] = line
      items[#items + 1] = cur
    elseif cur then
      cur.parts[#cur.parts + 1] = line
    elseif #items == 0 then
      -- before the first test or keyword: settings, variables and the headers that open them
      for _, p in ipairs(pending) do head[#head + 1] = p end
      pending = {}
      head[#head + 1] = line
    else
      pending[#pending + 1] = line
    end
  end
  if #pending > 0 then
    local into = #items > 0 and items[#items].parts or head
    for _, p in ipairs(pending) do into[#into + 1] = p end
  end
  for _, it in ipairs(items) do it.text, it.parts = table.concat(it.parts), nil end
  return table.concat(head), items
end

return M
