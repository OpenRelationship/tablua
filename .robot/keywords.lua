-- The keywords our claims measure with: reading rows (a run's sheet, the ledger, or a fixture made for a red
-- proof), and the measures for each level (agreement with an oracle, a score against its shuffled self, a mean over
-- runs). Each one measures; none decides. The decision is the claim's own assertion, written before it ran. A measure
-- with too few rows skips, so a claim with no evidence is unknown rather than held or killed.
--
--   local keywords = require("keywords")
--   keywords.library(root) -> lib    root: the .robot folder, which sheet paths are read from
--
--   Use Sheet    path                    a tablua file (relative to .robot/), or the ledger itself
--   Use Sheets    pattern               every sheet matching (runs/*.sqlite) in one in-memory file, each todo named
--                                        sheet:todo, the columns they share: claims over many runs
--   Use Trials    label                 every trial fetched with the label (the ledger's trial rows), pooled as above
--   Use Fixture    sql    ...            a fresh in-memory tablua file, the statements run in it: a red proof's rows
--   Needs At Least    count    min    what    skips unless count reaches min: a column never exercised is unknown
--   Value Of    sql                      the first row's first column
--   Count Of    sql                      how many rows
--   Agreement Of    sql    min=10        rows (a, b): the share where a equals b (a cell and its oracle)
--   Disagreements Of    sql    most=5    the rows where a and b part, as text
--   AUROC Against Shuffled    sql    min=10    rows (score, label 0|1): [auc, its mean over shuffled labels, p]
--   Gap Against Shuffled    sql    min=10      rows (value, group 0|1): [group 1's mean less group 0's, null, p]
--   Mean Of    sql    min=10             the first column's mean
--   Bench Calls It Broken    message     1 if the bench's broken-test detector says so
local robot = require("robot")
local sqlite = require("ports.sqlite")
local tablua = require("tablua")
local stats = require("stats")
local ledger = require("ledger")

local M = {}

-- the bench, where claims about the terminal's harness code find it
M.bench = (os.getenv("TABLUA_LOCAL") or (os.getenv("HOME") .. "/tablua-local")) .. "/bench/terminal/"

-- the tables Use Sheets pools
M.pooled = { "tablua_term", "tablua_event", "tablua_file", "tablua_result", "tablua_decision", "tablua_candidate" }

local function skip(msg) error({ robot = true, skip = true, message = msg }, 0) end

local function min_of(arg, default)
  return tonumber(tostring(arg or ""):match("^min=(%d+)$") or "") or default
end

function M.library(root)
  local lib = robot.library()
  local db

  local function rows(sql)
    assert(db, "Use Sheet or Use Fixture first")
    return db:exec(sql)
  end
  -- the rows' two columns, by position as the query names them
  local function pairs_of(sql, want)
    local out = {}
    for _, r in ipairs(rows(sql)) do out[#out + 1] = { r[want[1]], r[want[2]] } end
    return out
  end

  lib:add("Use Sheet", function(path)
    local full = path:find("^/") and path or root .. "/" .. path
    local f = io.open(full, "rb")
    if not f then skip("no sheet at " .. path) end
    f:close()
    db = sqlite.open(full)
    if full:find("ledger%.sqlite$") then ledger.open(db) end
  end)

  -- the sheets at these paths in one in-memory file, each todo named sheet:todo, the columns they share
  local function pool(paths)
    db = tablua.open(sqlite.open(":memory:")).db
    for _, path in ipairs(paths) do
      local name = path:match("([^/]+)%.sqlite$") or path
      db:exec("attach database ? as s", { path })
      for _, tbl in ipairs(M.pooled) do
        local mine, cols = {}, {}
        for _, c in ipairs(db:exec("pragma main.table_info(" .. tbl .. ")")) do mine[c.name] = true end
        for _, c in ipairs(db:exec("pragma s.table_info(" .. tbl .. ")")) do
          if mine[c.name] then cols[#cols + 1] = c.name end
        end
        if #cols > 0 then
          local sel = {}
          for i, c in ipairs(cols) do sel[i] = c == "todo" and "? || ':' || todo" or c end
          db:exec(("insert or ignore into main.%s (%s) select %s from s.%s"):format(tbl, table.concat(cols, ", "),
            table.concat(sel, ", "), tbl), { name })
        end
      end
      db:exec("detach database s")
    end
  end

  lib:add("Use Sheets", function(pattern)
    local paths = {}
    local p = io.popen('ls ' .. root .. '/' .. pattern .. ' 2>/dev/null')
    for path in p:lines() do paths[#paths + 1] = path end
    p:close()
    if #paths == 0 then skip("no sheet matches " .. pattern) end
    pool(paths)
  end)

  lib:add("Use Trials", function(label)
    local l = sqlite.open(root .. "/ledger.sqlite")
    ledger.open(l)
    local paths = {}
    for _, r in ipairs(l:exec("select sheet from trial where label = ? order by job, trial", { label })) do
      local f = io.open(root .. "/" .. r.sheet, "rb")
      if f then f:close() paths[#paths + 1] = root .. "/" .. r.sheet end
    end
    if #paths == 0 then skip("no trial fetched with the label " .. label) end
    pool(paths)
  end)

  lib:add("Needs At Least", function(count, min, what)
    if (tonumber(count) or 0) < (tonumber(min) or 0) then
      skip(("%s: %s of %s needed"):format(what or "rows", tostring(count), tostring(min)))
    end
  end)

  lib:add("Use Fixture", function(...)
    db = tablua.open(sqlite.open(":memory:")).db
    ledger.open(db)
    for _, sql in ipairs({ ... }) do db:exec(sql) end
  end)

  lib:add("Value Of", function(sql)
    local row = rows(sql)[1]
    if not row then return nil end
    local _, v = next(row)
    return v
  end)

  lib:add("Count Of", function(sql) return #rows(sql) end)

  lib:add("Agreement Of", function(sql, min)
    local ps = pairs_of(sql, { "a", "b" })
    local need = min_of(min, 10)
    if #ps < need then skip(("%d rows to compare, %d needed"):format(#ps, need)) end
    local same = 0
    for _, p in ipairs(ps) do if p[1] == p[2] then same = same + 1 end end
    return same / #ps
  end)

  lib:add("Disagreements Of", function(sql, most)
    local k = tonumber(tostring(most or ""):match("(%d+)") or "") or 5
    local out = {}
    for _, p in ipairs(pairs_of(sql, { "a", "b" })) do
      if p[1] ~= p[2] and #out < k then out[#out + 1] = ("%s vs %s"):format(tostring(p[1]), tostring(p[2])) end
    end
    return table.concat(out, "; ")
  end)

  local function against(measure, cols)
    return function(sql, min)
      local xs, ys, ones = {}, {}, 0
      for _, p in ipairs(pairs_of(sql, cols)) do
        if tonumber(p[1]) and tonumber(p[2]) then
          xs[#xs + 1], ys[#ys + 1] = tonumber(p[1]), tonumber(p[2]) == 1 and 1 or 0
          ones = ones + ys[#ys]
        end
      end
      local need = min_of(min, 10)
      if ones < need or #ys - ones < need then
        skip(("%d of one kind and %d of the other, %d of each needed"):format(ones, #ys - ones, need))
      end
      local r = stats.shuffled(measure, xs, ys)
      return { r.observed, r.null, r.p }
    end
  end
  lib:add("AUROC Against Shuffled", against(stats.auroc, { "score", "label" }))
  lib:add("Gap Against Shuffled", against(stats.gap, { "value", "group" }))

  lib:add("Mean Of", function(sql, min)
    local sum, n = 0, 0
    for _, r in ipairs(rows(sql)) do
      local _, v = next(r)
      if tonumber(v) then sum, n = sum + tonumber(v), n + 1 end
    end
    local need = min_of(min, 10)
    if n < need then skip(("%d rows, %d needed"):format(n, need)) end
    return sum / n
  end)

  -- the bench's broken-test detector, on one failing test's message
  lib:add("Bench Calls It Broken", function(message)
    package.path = M.bench .. "?.lua;" .. package.path
    return require("tests").broken(message) and 1 or 0
  end)

  return lib
end

return M
