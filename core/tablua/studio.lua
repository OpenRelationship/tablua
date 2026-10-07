-- Moonsplice's comp as Tablua's rows (schema 19, owner 2026-10-06; the contract is cadence/docs/ROWS.md, msr/1): the
-- comp each step left, kept whole per step (tablua_msr_*, (todo, n) first; n = 0 before any step), what lint and check
-- found in it (tablua_msr_finding), how a judge scored it (tablua_score), and a step's outcome from its findings.
--
--   t:comp(todo, n, rows)          rows = { schema = "msr/1", tables = { comp, node, prop, key, motion, system, asset,
--                                  fact } } as `bin/moonsplice rows --json` prints them; replaces step n's snapshot
--   t:comp_rows(todo, n) -> rows   the same shape back, each table in its key order
--   t:touched(todo, n) -> { { id, name }, ... }   where snapshot n differs from n - 1, sorted: a node added, removed
--                                  or changed is { id, "" }, a prop, key or motion { id, name }, a system
--                                  { "system:<name>", "source" }, an asset { "asset:<id>", "" }, a comp setting
--                                  { "comp", key }
--   t:findings(todo, n, list)  t:findings_of(todo, n) -> list    list = { { tier, id, name, code, severity, t0?, t1?,
--                                  measured?, threshold?, detail? } }, the full list after step n
--   t:scores(todo, n, judge, { dim = value })                    judge "critic" | "oracle"
--   studio.outcome(before, after, touched) -> "complete" | "no_effect" | "broken"
--   studio.canon(v) -> text         canonical JSON: keys sorted, numbers %.17g (integers as integers)
local json = require("ports.json")

local M = {}

-- each table: its columns in order, its key columns, and the columns whose value is typed (n, s, b, j)
M.tables = {
  { name = "comp", cols = { "key", "value" }, key = { "key" }, typed = "value" },
  { name = "node", cols = { "id", "kind", "parent", "z" }, key = { "id" } },
  { name = "prop", cols = { "id", "name", "value" }, key = { "id", "name" }, typed = "value" },
  { name = "key", cols = { "id", "name", "t", "value", "ease" }, key = { "id", "name", "t" }, typed = "value" },
  { name = "motion", cols = { "id", "name", "t0", "t1", "curve", "params" }, key = { "id", "name", "t0" },
    json = { params = true } },
  { name = "system", cols = { "name", "order", "source" }, key = { "name" }, rename = { order = "ord" } },
  { name = "asset", cols = { "id", "src", "derive" }, key = { "id" }, json = { derive = true } },
  { name = "fact", cols = { "pred", "args", "t0", "t1", "src", "conf" }, key = { "pred", "args", "t0" },
    json = { args = true } },
}

local function is_array(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do if t[i] == nil then return false end end
  return true
end

local function number(v)
  if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return ("%d"):format(v) end
  return ("%.17g"):format(v)
end

function M.canon(v)
  local kind = type(v)
  if kind == "number" then return number(v) end
  if kind == "string" or kind == "boolean" or v == nil then return json.encode(v) end
  local parts = {}
  if next(v) ~= nil and is_array(v) then
    for i, x in ipairs(v) do parts[i] = M.canon(x) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for i, k in ipairs(keys) do parts[i] = json.encode(k) .. ":" .. M.canon(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- a value as a cell and its type, and back
local function cell(v)
  local kind = type(v)
  if kind == "number" then return v, "n" end
  if kind == "string" then return v, "s" end
  if kind == "boolean" then return M.canon(v), "b" end
  return M.canon(v), "j"
end

local function uncell(v, kind)
  if kind == "b" or kind == "j" then return json.decode(v) end
  return v
end

local function column(spec, c) return spec.rename and spec.rename[c] or c end

-- A step's outcome from the findings before and after it and what it touched (ROWS.md, level 6): nothing touched is
-- no_effect; a new error is broken; a new finding of any other kind, or one on what it touched still there, helped
-- nothing (no_effect); otherwise complete. A finding is about what a step touched when it names the same node and
-- either the same prop or none, or the step touched the node itself (added, removed or changed it).
local function fkey(f) return table.concat({ f.tier or "", f.id or "", f.name or "", f.code or "" }, "\0") end

local function about(f, touched)
  for _, t in ipairs(touched) do
    local name = t.name or ""
    if (f.id or "") == t.id and (name == "" or (f.name or "") == "" or f.name == name) then return true end
  end
  return false
end

function M.outcome(before, after, touched)
  if #touched == 0 then return "no_effect" end
  local had, has = {}, {}
  for _, f in ipairs(before) do had[fkey(f)] = true end
  for _, f in ipairs(after) do has[fkey(f)] = true end
  local new = false
  for _, f in ipairs(after) do
    if not had[fkey(f)] then
      if (f.severity or "error") == "error" then return "broken" end
      new = true
    end
  end
  if new then return "no_effect" end
  for _, f in ipairs(before) do
    if has[fkey(f)] and about(f, touched) then return "no_effect" end
  end
  return "complete"
end

return setmetatable(M, { __call = function(_, T, put)
  function T:comp(todo, n, rows)
    local tables = rows and rows.tables or {}
    for _, spec in ipairs(M.tables) do
      local tbl = "tablua_msr_" .. spec.name
      self.db:exec("delete from " .. tbl .. " where todo = ? and n = ?", { todo, n })
      local cols = { "todo", "n" }
      for _, c in ipairs(spec.cols) do cols[#cols + 1] = column(spec, c) end
      if spec.typed then cols[#cols + 1] = "type" end
      for _, r in ipairs(tables[spec.name] or {}) do
        local row = { todo = todo, n = n }
        for _, c in ipairs(spec.cols) do
          local v = r[c]
          if spec.typed == c then v, row.type = cell(v)
          elseif spec.json and spec.json[c] and v ~= nil then v = M.canon(v) end
          row[column(spec, c)] = v
        end
        put(self.db, tbl, cols, row)
      end
    end
  end

  function T:comp_rows(todo, n)
    local out = { schema = "msr/1", tables = {} }
    for _, spec in ipairs(M.tables) do
      local order = {}
      for i, c in ipairs(spec.key) do order[i] = column(spec, c) end
      local got = self.db:exec(("select * from tablua_msr_%s where todo = ? and n = ? order by %s"):format(spec.name,
        table.concat(order, ", ")), { todo, n })
      if #got > 0 then
        local list = {}
        for i, r in ipairs(got) do
          local row = {}
          for _, c in ipairs(spec.cols) do
            local v = r[column(spec, c)]
            if spec.typed == c then v = uncell(v, r.type)
            elseif spec.json and spec.json[c] and v ~= nil then v = json.decode(v) end
            row[c] = v
          end
          list[i] = row
        end
        out.tables[spec.name] = list
      end
    end
    return out
  end

  function T:touched(todo, n)
    local seen, out = {}, {}
    local function add(id, name)
      local k = id .. "\0" .. name
      if not seen[k] then seen[k] = true; out[#out + 1] = { id = id, name = name } end
    end
    local function differ(tbl, keycols, where)
      local on = {}
      for i, c in ipairs(keycols) do on[i] = ("a.%s is b.%s"):format(c, c) end
      local sql = ("select %s from tablua_msr_%s a where a.todo = ? and a.n = ? and not exists (select 1 from "
        .. "tablua_msr_%s b where b.todo = a.todo and b.n = ? and %s)"):format(where, tbl, tbl, table.concat(on, " and "))
      local rows = {}
      for _, r in ipairs(self.db:exec(sql, { todo, n, n - 1 })) do rows[#rows + 1] = r end
      for _, r in ipairs(self.db:exec(sql, { todo, n - 1, n })) do rows[#rows + 1] = r end
      return rows
    end
    for _, spec in ipairs(M.tables) do
      local cols = {}
      for _, c in ipairs(spec.cols) do cols[#cols + 1] = column(spec, c) end
      if spec.typed then cols[#cols + 1] = "type" end
      for _, r in ipairs(differ(spec.name, cols, "a.*")) do
        if spec.name == "node" then add(r.id, "")
        elseif spec.name == "system" then add("system:" .. r.name, "source")
        elseif spec.name == "asset" then add("asset:" .. r.id, "")
        elseif spec.name == "comp" then add("comp", r.key)
        elseif spec.name == "fact" then add("fact:" .. r.pred, "")
        else add(r.id, r.name) end
      end
    end
    table.sort(out, function(a, b) if a.id ~= b.id then return a.id < b.id end return a.name < b.name end)
    return out
  end

  local FCOLS = { "todo", "n", "tier", "id", "name", "code", "severity", "t0", "t1", "measured", "threshold", "detail" }

  function T:findings(todo, n, list)
    self.db:exec("delete from tablua_msr_finding where todo = ? and n = ?", { todo, n })
    for _, f in ipairs(list or {}) do
      put(self.db, "tablua_msr_finding", FCOLS, { todo = todo, n = n, tier = f.tier or "lint", id = f.id or "",
        name = f.name or "", code = f.code, severity = f.severity or "error", t0 = f.t0 or -1, t1 = f.t1,
        measured = type(f.measured) == "table" and M.canon(f.measured) or f.measured,
        threshold = type(f.threshold) == "table" and M.canon(f.threshold) or f.threshold, detail = f.detail or "" })
    end
  end

  function T:findings_of(todo, n)
    local out = self.db:exec("select tier, id, name, code, severity, t0, t1, measured, threshold, detail from "
      .. "tablua_msr_finding where todo = ? and n = ? order by tier, id, name, code, t0", { todo, n })
    for _, f in ipairs(out) do if f.t0 == -1 then f.t0 = nil end end
    return out
  end

  function T:scores(todo, n, judge, dims)
    local names = {}
    for d in pairs(dims or {}) do names[#names + 1] = d end
    table.sort(names)
    for _, d in ipairs(names) do
      put(self.db, "tablua_score", { "todo", "n", "judge", "dim", "value" },
        { todo = todo, n = n, judge = judge, dim = d, value = tonumber(dims[d]) })
    end
  end
end })
