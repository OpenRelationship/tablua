-- .lui's scanner (shroomi.lui): the page read as tokens, each with its line, and the refusals that teach. Lua inside
-- {{ }}, {% %} and attribute values is skipped by its brackets and strings, so a table or a string holding "}}"
-- does not end it early.
--
--   scan.new(text, name) -> st;  st:lua_block() -> { code, line } or nil;  st:next(keep_space) -> token or nil
--   tokens: text{text, blank (only space across lines)} expr{code} raw{code} stmt{code} open{tag, attrs, closed} close{tag}, each with line;
--   an attribute is { name, code, line, words (a class's literal names), literal (a value with no Lua in it) }
--   st:fail(line, why) raises { why = "name:line: why" }
local scan = {}

local ST = {}
ST.__index = ST

function scan.new(text, name)
  return setmetatable({ s = text, i = 1, line = 1, name = name }, ST)
end

function ST:fail(line, why) error({ why = self.name .. ":" .. line .. ": " .. why }, 0) end

-- move to j, counting the lines passed
function ST:to(j)
  local _, n = string.gsub(string.sub(self.s, self.i, j - 1), "\n", "")
  self.line, self.i = self.line + n, j
end

-- where Lua starting at i ends: the first `close` outside brackets, strings and comments
local function lua_end(s, i, close)
  local depth, n, w = 0, #s, #close
  while i <= n do
    local c = string.sub(s, i, i)
    if c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = string.sub(s, j, j)
        if d == "\\" then j = j + 2 elseif d == c then break else j = j + 1 end
      end
      i = j + 1
    elseif string.match(s, "^%[=*%[", i) or string.match(s, "^%-%-%[=*%[", i) then
      local eq = string.match(s, "^%-?%-?%[(=*)%[", i)
      local _, e = string.find(s, "]" .. eq .. "]", i, true)
      if not e then return nil end
      i = e + 1
    elseif string.sub(s, i, i + 1) == "--" then
      i = (string.find(s, "\n", i, true) or n) + 1
    elseif depth <= 0 and string.sub(s, i, i + w - 1) == close then
      return i
    elseif c == "{" or c == "(" or c == "[" then
      depth, i = depth + 1, i + 1
    elseif c == "}" or c == ")" or c == "]" then
      depth, i = depth - 1, i + 1
    else
      i = i + 1
    end
  end
  return nil
end

function ST:lua_block()
  local at = string.match(self.s, "^%s*()<lua>")
  if not at then return nil end
  self:to(at + 5)
  local line = self.line
  local e = string.find(self.s, "</lua>", self.i, true)
  if not e then self:fail(line, "the <lua> block is never closed with </lua>") end
  local code = string.sub(self.s, self.i, e - 1)
  self:to(e + 6)
  return { code = code, line = line }
end

local ENTITY = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = "\194\160" }

local function decode(t)
  return (string.gsub(t, "&(#?%w+);", function(e)
    local n = string.match(e, "^#(%d+)$")
    if n and tonumber(n) < 128 then return string.char(tonumber(n)) end
    return ENTITY[e]
  end))
end

-- the habits of other template languages, each answered with the Lua it should be
local function teach(st, line, code)
  local c = string.match(code, "^%s*(.-)%s*$")
  local word = string.match(c, "^end(%a+)$")
  if word then st:fail(line, "{% end" .. word .. " %} is Jinja's; a Lua block ends with {% end %}") end
  if string.match(c, "^elif[%s%(]") then st:fail(line, "Lua says {% elseif cond then %}, not elif") end
  if string.match(c, "^for%s") and not string.match(c, "%sdo$") and not string.match(c, "%sdo%s") then
    st:fail(line, "a Lua loop opens with do: {% for _, p in ipairs(list) do %} ... {% end %}")
  end
  if string.match(c, "^while%s") and not string.match(c, "%sdo$") and not string.match(c, "%sdo%s") then st:fail(line, "a Lua loop opens with do") end
  if (string.match(c, "^if[%s%(]") or string.match(c, "^elseif[%s%(]")) and not string.match(c, "%sthen$") and not string.match(c, "%sthen%s") then
    st:fail(line, "a Lua if opens with then: {% if cond then %} ... {% end %}")
  end
end

function ST:lua(from, close, what, line)
  local e = lua_end(self.s, from, close)
  if not e then self:fail(line, what .. " is never closed with " .. close) end
  local code = string.sub(self.s, from, e - 1)
  if string.match(code, "^%s*$") then self:fail(line, what .. " is empty") end
  self:to(e + #close)
  return code
end

-- one attribute's value: a quoted string with {{ }} in it, or {{ e }} alone
function ST:value(line)
  local s = self.s
  if string.sub(s, self.i, self.i + 2) == "{{{" then
    self:fail(line, "{{{ }}} is for text, never an attribute")
  elseif string.sub(s, self.i, self.i + 1) == "{{" then
    return { { expr = self:lua(self.i + 2, "}}", "{{", line) } }
  end
  local quote = string.sub(s, self.i, self.i)
  if quote ~= '"' and quote ~= "'" then self:fail(line, "an attribute's value is quoted, or {{ e }}") end
  self:to(self.i + 1)
  local segs, lit = {}, {}
  while true do
    local c = string.sub(s, self.i, self.i)
    if c == "" then self:fail(line, "an attribute's value is never closed with " .. quote) end
    if c == quote then self:to(self.i + 1); break end
    if string.sub(s, self.i, self.i + 1) == "{{" then
      if #lit > 0 then segs[#segs + 1] = { text = decode(table.concat(lit)) }; lit = {} end
      if string.sub(s, self.i, self.i + 2) == "{{{" then self:fail(self.line, "{{{ }}} is for text, never an attribute") end
      segs[#segs + 1] = { expr = self:lua(self.i + 2, "}}", "{{", self.line) }
    else
      lit[#lit + 1] = c
      self:to(self.i + 1)
    end
  end
  if #lit > 0 then segs[#segs + 1] = { text = decode(table.concat(lit)) } end
  return segs
end

local function quote(s)
  return '"' .. string.gsub(s, '[%c"\\]', function(c)
    if c == "\n" then return "\\n" end
    if c == '"' or c == "\\" then return "\\" .. c end
    return string.format("\\%03d", string.byte(c))
  end) .. '"'
end

-- an attribute's code, the class names that stand on their own, and its value when it holds no Lua
local function attribute(name, line, segs)
  local a = { name = name, line = line, words = {} }
  if not segs then a.code = "true"; return a end
  if #segs == 0 then a.code, a.literal = '""', ""; return a end
  if #segs == 1 and segs[1].expr then a.code = "(" .. segs[1].expr .. ")"; return a end
  local parts = {}
  for k, seg in ipairs(segs) do
    if seg.expr then
      parts[#parts + 1] = "(" .. seg.expr .. ")"
    else
      parts[#parts + 1] = quote(seg.text)
      local t = seg.text
      if k > 1 then t = string.gsub(t, "^%S+", "") end
      if k < #segs then t = string.gsub(t, "%S+$", "") end
      for w in string.gmatch(t, "%S+") do a.words[#a.words + 1] = w end
    end
  end
  if #segs == 1 then a.code, a.literal = parts[1], segs[1].text return a end
  a.code = "__s(" .. table.concat(parts, ", ") .. ")"
  return a
end

function ST:tag(line)
  local s = self.s
  local tag = string.match(s, "^<([%a_][%w_%-]*)", self.i)
  self:to(self.i + 1 + #tag)
  local attrs, seen, closed = {}, {}, false
  while true do
    self:to(string.match(s, "^%s*()", self.i))
    if string.sub(s, self.i, self.i + 1) == "/>" then self:to(self.i + 2); closed = true; break end
    if string.sub(s, self.i, self.i) == ">" then self:to(self.i + 1); break end
    if self.i > #s then self:fail(line, "<" .. tag .. " is never ended with > or />") end
    local name = string.match(s, "^[%a_@:][%w_%-:%.@]*", self.i)
    if not name then self:fail(self.line, "<" .. tag .. "> has something that is no attribute: " ..
      string.sub(s, self.i, self.i + 10)) end
    local aline = self.line
    if string.match(name, "^on") then self:fail(aline, name .. ": a page's own script never runs; use htmx (post, get)") end
    if seen[name] then self:fail(aline, "<" .. tag .. "> has " .. name .. " twice") end
    seen[name] = true
    self:to(self.i + #name)
    local segs
    local eq = string.match(s, "^%s*=%s*()", self.i)
    if eq then self:to(eq); segs = self:value(aline) end
    attrs[#attrs + 1] = attribute(name, aline, segs)
  end
  return { kind = "open", tag = tag, attrs = attrs, closed = closed, line = line }
end

function ST:next(keep)
  local s = self.s
  while self.i <= #s do
    local line, i = self.line, self.i
    if string.sub(s, i, i + 3) == "<!--" then
      local e = string.find(s, "-->", i + 4, true)
      if not e then self:fail(line, "a comment is never closed with -->") end
      self:to(e + 3)
    elseif string.sub(s, i, i + 2) == "{{{" then
      return { kind = "raw", code = self:lua(i + 3, "}}}", "{{{", line), line = line }
    elseif string.sub(s, i, i + 1) == "{{" then
      return { kind = "expr", code = self:lua(i + 2, "}}", "{{", line), line = line }
    elseif string.sub(s, i, i + 1) == "{%" then
      local code = self:lua(i + 2, "%}", "{%", line)
      teach(self, line, code)
      return { kind = "stmt", code = code, line = line }
    elseif string.match(s, "^</", i) then
      local tag, e = string.match(s, "^</([%a_][%w_%-]*)%s*>()", i)
      if not tag then self:fail(line, "a closing tag is </name>") end
      self:to(e)
      return { kind = "close", tag = tag, line = line }
    elseif string.match(s, "^<[%a_]", i) then
      return self:tag(line)
    else
      local j = i + 1
      while j <= #s do
        local at = string.find(s, "[<{]", j)
        if not at then j = #s + 1; break end
        if string.match(s, "^<[%a_/!]", at) or string.match(s, "^{[{%%]", at) then j = at; break end
        j = at + 1
      end
      local text = string.sub(s, i, j - 1)
      self:to(j)
      if keep then return { kind = "text", text = decode(text), line = line } end
      local blank = string.match(text, "^%s*$") and string.find(text, "\n", 1, true) and true
      return { kind = "text", text = decode((string.gsub(text, "%s*\n%s*", " "))), line = line, blank = blank }
    end
  end
  return nil
end

return scan
