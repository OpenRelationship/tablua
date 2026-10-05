-- The program's file (M6a; owner, 2026-10-04): real org syntax, in a written subset that Emacs, GitHub and
-- pandoc read as it is. A section is a top-level heading; each of its rows (a Lua unit, a test, a keyword) is a
-- heading under it, with a drawer for its columns and one source block for its text:
--
--   * Notes                 prose (its own headings one level down)
--   * Tests                 #+begin_src robot: the head (settings, variables), then a ** Test:, ** Task: or
--                           ** Keyword: heading per test, task and user keyword (Robot Framework's syntax, core/robot)
--   * Keywords / * Code     a ** heading per unit, :kind: and :name: in its drawer, #+begin_src <lang> (a Lua block
--                           cut into its top-level statements; a block in another language is one unit)
--   * Page                  #+begin_src lua (a page as Lua), or lui (a markup page in tagged sections)
--
-- The subset is headings, property drawers, source blocks and prose. Inside a block a line that org would read as
-- a heading or a keyword (* or #+ after its indent) carries a comma before it, as org itself escapes it. The
-- drawer is a view of the row: reading takes a section's text from its blocks alone, joined in order.
local M = {}

M.heading = { notes = "Notes", tests = "Tests", keywords = "Keywords", code = "Code", markup = "Page" }
local ITEM = { test = "Test", task = "Task", keyword = "Keyword" }
local KIND = {}
for kind, h in pairs(M.heading) do KIND[h] = kind end

local function lines(text)
  local out = {}
  for line in text:gmatch("([^\n]*)\n") do out[#out + 1] = line end
  local last = text:match("([^\n]+)$")
  if last then out[#out + 1] = last end
  return out
end

local function escape(line) return (line:gsub("^(%s*)(,*%*)", "%1,%2"):gsub("^(%s*)(,*#%+)", "%1,%2")) end
local function unescape(line) return (line:gsub("^(%s*),(,*%*)", "%1%2"):gsub("^(%s*),(,*#%+)", "%1%2")) end

local function block(lang, text)
  local out = { "#+begin_src " .. lang }
  for _, line in ipairs(lines(text)) do out[#out + 1] = escape(line) end
  out[#out + 1] = "#+end_src"
  return table.concat(out, "\n") .. "\n"
end

local function drawer(cols)
  local out = { ":PROPERTIES:" }
  for _, c in ipairs(cols) do
    if c[2] and c[2] ~= "" then out[#out + 1] = ":" .. c[1] .. ": " .. c[2] end
  end
  out[#out + 1] = ":END:"
  return table.concat(out, "\n") .. "\n"
end

-- one line of text for a heading
local function title(s) return (s:gsub("%s+", " "):match("^%s*(.-)%s*$")) end

-- sections: { { kind, text } or { kind, units = { {kind, name, source} } } or { kind, head, items } }
function M.write(sections)
  local out = {}
  for _, s in ipairs(sections) do
    out[#out + 1] = "* " .. M.heading[s.kind] .. "\n"
    if s.units then
      for _, u in ipairs(s.units) do
        out[#out + 1] = "** " .. (u.name ~= "" and title(u.name) or u.kind) .. "\n"
        out[#out + 1] = drawer({ { "kind", u.kind }, { "name", u.name } })
        out[#out + 1] = block(s.lang or "lua", u.source)
      end
    elseif s.items then
      if s.head ~= "" then out[#out + 1] = block("robot", s.head) end
      for _, it in ipairs(s.items) do
        out[#out + 1] = "** " .. (ITEM[it.kind] or "Test") .. ": " .. title(it.name) .. "\n"
        out[#out + 1] = block("robot", it.text)
      end
    elseif s.kind == "notes" then
      for _, line in ipairs(lines(s.text)) do
        out[#out + 1] = (line:match("^%*+%s") and "*" .. line or line) .. "\n"
      end
    else
      out[#out + 1] = block(s.lang or "lua", s.text)
    end
  end
  return table.concat(out)
end

-- { { kind, text, lang, at } } in the file's order: each section's text, its blocks (or its prose) joined, and at[i]
-- the line of the file its i-th line came from (for errors that name the file's own lines)
function M.read(text)
  local sections, cur, inblock, drawer_open = {}, nil, nil, false
  local function add(s, n)
    cur.parts[#cur.parts + 1] = s .. "\n"
    cur.at[#cur.at + 1] = n
  end
  for n, line in ipairs(lines(text)) do
    if inblock then
      if line == "#+end_src" then inblock = nil
      else add(unescape(line), n) end
    elseif line:match("^%* ") then
      local kind = KIND[title(line:sub(3))]
      if not kind then return nil, "an org section is one of Notes, Tests, Keywords, Code, Page: " .. line end
      cur = { kind = kind, parts = {}, at = {} }
      sections[#sections + 1] = cur
    elseif not cur then
      if not line:match("^%s*$") and not line:match("^#%+") then return nil, "text before the first section: " .. line end
    elseif cur.kind == "notes" then
      add(line:match("^%*%*+%s") and line:sub(2) or line, n)
    elseif line:match("^#%+begin_src") then
      inblock, cur.lang = true, cur.lang or line:match("^#%+begin_src%s+(%S+)")
    elseif line == ":PROPERTIES:" then drawer_open = true
    elseif line == ":END:" then drawer_open = false
    end
  end
  if inblock then return nil, "a source block is never closed with #+end_src" end
  if drawer_open then return nil, "a drawer is never closed with :END:" end
  for _, s in ipairs(sections) do s.text, s.parts = table.concat(s.parts), nil end
  return sections
end

return M
