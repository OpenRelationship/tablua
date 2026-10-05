-- The program as rows (M6a): a program's rows (tablua.source) kept in tables of the agent's own file, and
-- its org compiled back from them. One row per section of a file (notes and a page keep their text; a feature its
-- header), per unit (a top-level Lua statement, or a whole block in another language), per scenario, and per
-- scenario's step line, keyed as the org file's headings are. The step lines are a view of their scenario's
-- text, kept for what learns from them; compiling reads the sections, units and scenarios.
--
--   t:put_program(file, rows)     the file's rows, replacing what was kept for it
--   t:program(file) -> rows | nil t:compile(file) -> org | nil      t:files() -> { file, ... }
--   t:breaks() -> { { file, kind, source, target } }   the links with nothing at their end (tablua_break)
--   t:change(task, n, ops)        a change's operation rows (tablua.change), as step n of task made them
--
-- Putting a file's rows also puts its links (tablua.links), and settles every scenario line's link against every
-- step the program defines, in whichever file: a step written later mends a line written earlier.
-- It also puts each unit's columns (tablua_shape).
local src = require("tablua.source")
local links = require("tablua.links")
local change = require("tablua.change")

return function(T, put)
  local function clear(db, file)
    for _, tbl in ipairs({ "tablua_section", "tablua_unit", "tablua_scenario", "tablua_line", "tablua_link",
      "tablua_shape" }) do
      db:exec("delete from " .. tbl .. " where file = ?", { file })
    end
  end

  function T:put_program(file, rows)
    local db = self.db
    db:exec("begin")
    clear(db, file)
    for n, s in ipairs(rows.sections) do
      local body = s.head or (not s.units and not s.scenarios and src.body(s)) or ""
      put(db, "tablua_section", { "file", "n", "kind", "lang", "body" },
        { file = file, n = n, kind = s.kind, lang = s.lang or "", body = body })
      for i, u in ipairs(s.units or {}) do
        put(db, "tablua_unit", { "file", "section", "n", "kind", "name", "source" },
          { file = file, section = n, n = i, kind = u.kind, name = u.name, source = u.source })
      end
      for i, sc in ipairs(s.scenarios or {}) do
        put(db, "tablua_scenario", { "file", "n", "name", "text" }, { file = file, n = i, name = sc.name, text = sc.text })
        for j, l in ipairs(sc.lines) do
          put(db, "tablua_line", { "file", "scenario", "n", "keyword", "text" },
            { file = file, scenario = i, n = j, keyword = l.keyword, text = l.text })
        end
      end
    end
    for _, c in ipairs(change.shape(rows)) do
      c.file = file
      put(db, "tablua_shape", { "file", "section", "n", "lines", "arity", "depth", "names" }, c)
    end
    for _, l in ipairs(links.scan(rows, file)) do
      put(db, "tablua_link", { "file", "kind", "source", "target" },
        { file = file, kind = l.kind, source = l.source, target = l.target })
    end
    local steps, text = {}, {}
    for _, u in ipairs(db:exec("select kind, name, source from tablua_unit")) do
      if u.kind == "step" then steps[#steps + 1] = u.name end
      text[#text + 1] = u.source
    end
    for _, r in ipairs(db:exec("select body from tablua_section where kind = 'markup'")) do text[#text + 1] = r.body end
    text = table.concat(text, "\n"):lower()
    for _, l in ipairs(db:exec("select file, kind, source, target from tablua_link "
      .. "where kind in ('line', 'press', 'field', 'see')")) do
      db:exec("update tablua_link set found = ? where file = ? and kind = ? and source = ? and target = ?",
        { links.found(l, text, steps) and 1 or 0, l.file, l.kind, l.source, l.target })
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
      if r.kind == "code" or r.kind == "steps" then
        s.units = {}
        for _, u in ipairs(db:exec("select kind, name, source from tablua_unit where file = ? and section = ? order by n",
          { file, r.n })) do
          s.units[#s.units + 1] = { kind = u.kind, name = u.name, source = u.source }
        end
      elseif r.kind == "feature" then
        s.head, s.scenarios = r.body, {}
        for _, sc in ipairs(db:exec("select n, name, text from tablua_scenario where file = ? order by n", { file })) do
          local lines = {}
          for _, l in ipairs(db:exec("select keyword, text from tablua_line where file = ? and scenario = ? order by n",
            { file, sc.n })) do
            lines[#lines + 1] = { keyword = l.keyword, text = l.text }
          end
          s.scenarios[#s.scenarios + 1] = { name = sc.name, text = sc.text, lines = lines }
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
