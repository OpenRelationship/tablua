-- The program as rows (M6a): a program's rows (tablua.source) kept in tables of the agent's own file, and
-- its org compiled back from them. One row per section of a file (notes and a page keep their text; the tests
-- their head), per unit (a top-level Lua statement, or a whole block in another language), per test or task
-- (tablua_test, its kind test or task) and per user keyword (tablua_keyword), numbered together in the file's order,
-- and per call any of them makes (tablua_call), keyed as the org file's headings are. The calls are a view of their item's text, kept for what
-- learns from them; compiling reads the sections, units, tests and keywords.
--
--   t:put_program(file, rows)     the file's rows, replacing what was kept for it
--   t:program(file) -> rows | nil t:compile(file) -> org | nil      t:files() -> { file, ... }
--   t:breaks() -> { { file, kind, source, target } }   the links with nothing at their end (tablua_break)
--   t:change(task, n, ops)        a change's operation rows (tablua.change), as step n of task made them
--
-- Putting a file's rows also puts its links (tablua.links), and settles every call's link against every keyword
-- the program defines, in whichever file (a Lua keyword unit or a user keyword), and BuiltIn's and the host's
-- (links.host): a keyword written later mends a call written earlier.
-- It also puts each unit's columns (tablua_shape), and the elements of a page written in Lua (tablua_element).
local src = require("tablua.source")
local links = require("tablua.links")
local change = require("tablua.change")
local tree = require("tablua.tree")

return function(T, put)
  local function clear(db, file)
    for _, tbl in ipairs({ "tablua_section", "tablua_unit", "tablua_test", "tablua_keyword", "tablua_call",
      "tablua_link", "tablua_shape", "tablua_element" }) do
      db:exec("delete from " .. tbl .. " where file = ?", { file })
    end
  end

  function T:put_program(file, rows)
    local db = self.db
    db:exec("begin")
    clear(db, file)
    for n, s in ipairs(rows.sections) do
      local body = s.head or (not s.units and not s.items and src.body(s)) or ""
      put(db, "tablua_section", { "file", "n", "kind", "lang", "body" },
        { file = file, n = n, kind = s.kind, lang = s.lang or "", body = body })
      for i, u in ipairs(s.units or {}) do
        put(db, "tablua_unit", { "file", "section", "n", "kind", "name", "source" },
          { file = file, section = n, n = i, kind = u.kind, name = u.name, source = u.source })
      end
      for i, it in ipairs(s.items or {}) do
        if it.kind == "keyword" then
          put(db, "tablua_keyword", { "file", "n", "name", "text" }, { file = file, n = i, name = it.name, text = it.text })
        else
          put(db, "tablua_test", { "file", "n", "kind", "name", "text" },
            { file = file, n = i, kind = it.kind, name = it.name, text = it.text })
        end
        for _, c in ipairs(src.calls(it)) do
          put(db, "tablua_call", { "file", "item", "path", "keyword", "args" },
            { file = file, item = i, path = c.path, keyword = c.keyword, args = table.concat(c.args or {}, "\t") })
        end
      end
    end
    for _, c in ipairs(change.shape(rows)) do
      c.file = file
      put(db, "tablua_shape", { "file", "section", "n", "lines", "arity", "depth", "names" }, c)
    end
    local e = 0
    for _, s in ipairs(rows.sections) do
      if s.kind == "markup" and s.lang == "lua" then
        for _, r in ipairs(tree.rows(src.body(s))) do
          e = e + 1
          r.file, r.n = file, e
          put(db, "tablua_element", { "file", "n", "path", "call", "parent", "depth", "children", "props", "text" }, r)
        end
      end
    end
    for _, l in ipairs(links.scan(rows, file)) do
      put(db, "tablua_link", { "file", "kind", "source", "target" },
        { file = file, kind = l.kind, source = l.source, target = l.target })
    end
    local keywords, text = {}, {}
    for _, u in ipairs(db:exec("select kind, name, source from tablua_unit")) do
      if u.kind == "keyword" then keywords[#keywords + 1] = u.name end
      text[#text + 1] = u.source
    end
    for _, k in ipairs(db:exec("select name from tablua_keyword")) do keywords[#keywords + 1] = k.name end
    for _, r in ipairs(db:exec("select body from tablua_section where kind = 'markup'")) do text[#text + 1] = r.body end
    text = table.concat(text, "\n"):lower()
    for _, l in ipairs(db:exec("select file, kind, source, target from tablua_link "
      .. "where kind in ('call', 'press', 'field', 'see')")) do
      db:exec("update tablua_link set found = ? where file = ? and kind = ? and source = ? and target = ?",
        { links.found(l, text, keywords) and 1 or 0, l.file, l.kind, l.source, l.target })
    end
    db:exec("commit")
  end

  function T:change(task, n, ops)
    for i, o in ipairs(ops) do
      put(self.db, "tablua_change", { "task", "n", "i", "op", "kind", "name", "lines", "named_by", "breaks" },
        { task = task, n = n, i = i, op = o.op, kind = o.kind, name = o.name, lines = o.lines, named_by = o.named_by,
          breaks = o.breaks })
    end
  end

  function T:breaks()
    return self.db:exec("select file, kind, source, target from tablua_break order by file, kind, source, target")
  end

  function T:program(file)
    local db = self.db
    local secs = db:exec("select n, kind, lang, body from tablua_section where file = ? order by n", { file })
    if #secs == 0 then return nil end
    local sections = {}
    for _, r in ipairs(secs) do
      local s = { kind = r.kind, lang = r.lang ~= "" and r.lang or nil }
      if r.kind == "code" or r.kind == "keywords" then
        s.units = {}
        for _, u in ipairs(db:exec("select kind, name, source from tablua_unit where file = ? and section = ? order by n",
          { file, r.n })) do
          s.units[#s.units + 1] = { kind = u.kind, name = u.name, source = u.source }
        end
      elseif r.kind == "tests" then
        s.head, s.items = r.body, {}
        for _, it in ipairs(db:exec("select n, kind, name, text from tablua_test where file = ? "
          .. "union all select n, 'keyword', name, text from tablua_keyword where file = ? order by n", { file, file })) do
          s.items[#s.items + 1] = { kind = it.kind, name = it.name, text = it.text }
        end
      else
        s.body = r.body
      end
      s.body = s.body or src.body(s)
      sections[#sections + 1] = s
    end
    return { sections = sections }
  end

  function T:compile(file)
    local rows = self:program(file)
    return rows and src.compile(rows)
  end

  function T:files()
    local out = {}
    for _, r in ipairs(self.db:exec("select distinct file from tablua_section order by file")) do out[#out + 1] = r.file end
    return out
  end
end
