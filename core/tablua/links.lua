-- The links between a program's rows (issue #1 M6c): what one row names that another must hold. A page names the
-- actions its forms and buttons post to (post = "add" -> function post.add); an action reads the fields a form
-- sends (req.form.name -> a field name = "name", or vals = { id = ... }); a scenario's line in the app's own words
-- needs a step whose pattern matches it (test.step), and one in the page's words a label, a field or text the page
-- holds. Kept as rows (tablua_link), so a link with nothing at its end
-- is a view (tablua_break), as is an action no page posts to (an orphan: nothing can reach it), and the harness's facts, gates and TabPFN's columns read the breaks as data.
--
--   links.scan(rows, file?) -> { { kind, source, target } }   kinds: post (page -> action), defines (page -> action it
--     holds), sends (page -> field), reads (action -> field), and from a scenario's line "i.j": line (its text,
--     needing a step), press (a label the page must show), field (a field it must have), see (text it must show,
--     unless the scenario typed it or it holds a number); with the file's name, calls (a module's function the
--     file calls: local m = require("mod") ... m.fn(), as "mod.fn"), module (code/<mod>.lua is module mod) and
--     exports (each function the module returns, "mod.fn")
--   links.found(link, text, steps) -> whether the program's text (lowercased) or its steps answer a line's link
--   links.pattern(step) -> the Lua pattern a step's text compiles to (test.step in the computer's test library)
--   links.step(text, patterns) -> the step pattern a line's text matches, or nil
--
-- The code links (posts, sends, reads, calls, modules, exports) are read from Lua alone: a section in another
-- language (its lang) gives none, and with step definitions in another language a scenario's own words are not
-- checked against them (owner, 2026-10-05: Lua is the harness's language, not the output's).
local effects = require("tablua.effects")

local M = {}

local HOLES = { ["{int}"] = "%-?%d+", ["{number}"] = "%-?%d+%.?%d*", ["{string}"] = '"[^"]*"',
  ["{word}"] = '[^%s"]+', ["{}"] = ".-" }

function M.pattern(step)
  local out, at = { "^" }, 1
  while at <= #step do
    local s, e = step:find("{%a*}", at)
    out[#out + 1] = (step:sub(at, (s or #step + 1) - 1):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
    if not s then break end
    out[#out + 1] = HOLES[step:sub(s, e)] or ".-"
    at = e + 1
  end
  out[#out + 1] = "$"
  return table.concat(out)
end

function M.step(text, patterns)
  for _, p in ipairs(patterns) do
    if text:find(M.pattern(p)) then return p end
  end
  return nil
end

local function add(out, seen, kind, source, target)
  local k = kind .. "\0" .. source .. "\0" .. target
  if not seen[k] then seen[k] = true; out[#out + 1] = { kind = kind, source = source, target = target } end
end

-- what a page's text (Lua that builds it, or markup) posts to and sends
local function page(out, seen, text, where)
  for _, verb in ipairs({ "post", "get" }) do
    for name in text:gmatch("[%s{,]" .. verb .. "%s*=%s*[\"']([%w_]+)[\"']") do
      add(out, seen, "post", where, verb .. "." .. name)
    end
  end
  -- a page may call an action itself to read what it shows (get.view())
  for verb, name in text:gmatch("[^%w_.]([pg][oe][st]t?)%.([%a_][%w_]*)%s*%(") do
    if verb == "post" or verb == "get" then add(out, seen, "post", where, verb .. "." .. name) end
  end
  -- a markup page may hold its own code: the actions it defines there
  for name in text:gmatch("function%s+(post%.[%w_]+)") do add(out, seen, "defines", where, name) end
  for name in text:gmatch("function%s+(get%.[%w_]+)") do add(out, seen, "defines", where, name) end
  for name in text:gmatch("[%s{,]name%s*=%s*[\"']([%w_]+)[\"']") do add(out, seen, "sends", where, name) end
  for vals in text:gmatch("vals%s*=%s*(%b{})") do
    for name in vals:gmatch("([%a_][%w_]*)%s*=") do add(out, seen, "sends", where, name) end
  end
end

-- a section whose text is Lua (or a Lua or .lui page): its lang, Lua when none is given
local function lua(s)
  return s.lang == nil or s.lang == "" or s.lang == "lua" or (s.kind == "markup" and s.lang == "lui")
end

-- the whole of a file's Lua: its Lua units' sources and its pages' bodies
local function lua_of(rows)
  local parts = {}
  for _, s in ipairs(rows.sections or {}) do
    if lua(s) then
      for _, u in ipairs(s.units or {}) do parts[#parts + 1] = u.source end
      if s.kind == "markup" then parts[#parts + 1] = s.body or s.text or "" end
    end
  end
  return "\n" .. table.concat(parts, "\n")
end

-- what a file calls of the app's modules, and, for a module (code/<mod>.lua), what it is and returns
local function modules(out, seen, text, file)
  for alias, mod in text:gmatch("local%s+([%a_][%w_]*)%s*=%s*require%s*%(?%s*[\"']([%w_]+)[\"']") do
    for fn in text:gmatch("[^%w_.]" .. alias .. "[.:]([%a_][%w_]*)%s*%(") do
      add(out, seen, "calls", file or "", mod .. "." .. fn)
    end
  end
  local mod = file and file:match("code/([%w_]+)%.lua$")
  if not mod or not text:find("%S") then return end   -- a module only with code in it (a file gone has none)
  add(out, seen, "module", file, mod)
  -- a module that returns a table literal names what it exports there: return { add = add, list = list }
  local literal = text:match("\nreturn%s*(%b{})%s*$")
  if literal then
    for fn in literal:gmatch("([%a_][%w_]*)%s*=") do add(out, seen, "exports", mod, mod .. "." .. fn) end
    return
  end
  local t = text:match("\nreturn%s+([%a_][%w_]*)%s*$") or text:match("\nreturn%s+([%a_][%w_]*)%s*\n")
  if not t then return end
  for fn in text:gmatch("function%s+" .. t .. "[.:]([%a_][%w_]*)") do add(out, seen, "exports", mod, mod .. "." .. fn) end
  for fn in text:gmatch("[^%w_.]" .. t .. "%.([%a_][%w_]*)%s*=%s*function") do add(out, seen, "exports", mod, mod .. "." .. fn) end
end

function M.scan(rows, file)
  local out, seen, steps_lua = {}, {}, true
  for _, s in ipairs(rows.sections or {}) do if s.kind == "steps" and not lua(s) then steps_lua = false end end
  modules(out, seen, lua_of(rows), file)
  for n, s in ipairs(rows.sections or {}) do
    if s.kind == "markup" and lua(s) then page(out, seen, s.body or s.text or "", "page " .. n) end
    for _, u in ipairs(s.units or {}) do
      if s.kind == "code" and lua(s) then
        if u.kind == "action" then
          for name in u.source:gmatch("req%.form%.([%a_][%w_]*)") do add(out, seen, "reads", u.name, name) end
          for name in u.source:gmatch("req%.form%[[\"']([%w_]+)[\"']%]") do add(out, seen, "reads", u.name, name) end
        end
      end
    end
    for i, sc in ipairs(s.scenarios or {}) do
      local data = {}   -- what the scenario's earlier lines put in: a page shows it without naming it
      for j, l in ipairs(sc.lines or {}) do
        local at, kind = ("%d.%d"):format(i, j), effects.line_kind(l.keyword .. " " .. l.text)
        local quoted = {}
        for q in l.text:gmatch('"([^"]*)"') do quoted[#quoted + 1] = q end
        -- only the app's own words need a step of its own; the page's step shapes are the computer's
        if kind == "own" then if steps_lua then add(out, seen, "line", at, l.text) end
        elseif kind == "press" or kind == "press_for" then add(out, seen, "press", at, quoted[1] or "")
        elseif kind == "type" and quoted[2] then add(out, seen, "field", at, quoted[2])
        elseif kind == "see" or kind == "see_for" or kind == "see_before" then
          for _, q in ipairs(quoted) do
            -- a number is worked out by the code, and what the scenario typed is the person's
            if q ~= "" and not q:find("%d") and not data[q:lower()] then add(out, seen, "see", at, q) end
          end
        end
        for _, q in ipairs(quoted) do data[q:lower()] = true end
      end
    end
  end
  return out
end

-- whether a link a page must answer is answered by the program's pages and code (their text, lowercased: what a
-- page shows or names is written in it) or, for a scenario line, by one of its steps
function M.found(l, text, steps)
  if l.kind == "line" then return M.step(l.target, steps) ~= nil end
  return text:find(l.target:lower(), 1, true) ~= nil
end

return M
