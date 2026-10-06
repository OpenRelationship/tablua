-- The ledger: every run of our claims and every claim's verdict, kept in ledger.sqlite beside the keyword trees
-- (tablua_result), committed to git so the record is shared and cannot quietly go.
--
-- A claim's verdict is read from its test and its red proof, the test of the same name with " (red)" after it, run
-- on rows known to be wrong:
--   holds     its check passed, and the same check failed at an assertion on its red proof
--   KILLED    its check failed
--   BLIND     its check passed, and so did its red proof: the check cannot fail, so it shows nothing
--   unproven  its check passed, with no red proof, or one that failed before reaching an assertion
--   unknown   it skipped: not measured yet, or too few rows to measure
-- A run counts only when its claims file is committed and unchanged (locked); one run with the file edited is a
-- draft. A claim whose text changed after a counted run killed it is flagged: the kill stays in the ledger.
--
--   local ledger = require("ledger")
--   ledger.open(db)                      the ledger's tables, in a tablua file
--   ledger.verdicts(res) -> { { name, verdict, status, message, tags, red } }
--   ledger.hashes(text) -> { [claim name] = hash }   each claim's text with its red proof and the keywords it names
--   ledger.record(db, todo, n, commit, draft, verdicts, hashes) -> flags   flags: { [name] = "edited after ..." }
--   ledger.invalid(db, todo, n, why)     ledger.history(db) -> rows
local robot = require("robot")

local M = {}

M.ddl = [[
create table if not exists claims_run (
  todo text not null, n integer not null, at text not null, commit_id text not null default '',
  draft integer not null default 0, invalid integer not null default 0, why text not null default '',
  primary key (todo, n));
create table if not exists claim (
  todo text not null, n integer not null, name text not null, verdict text not null, status text not null,
  message text not null default '', tags text not null default '', hash text not null default '',
  flag text not null default '', red text not null default '', primary key (todo, n, name));
create table if not exists trial (
  job text not null, trial text not null, task text not null default '', label text not null default '',
  reward real, green integer, steps integer, sheet text not null default '', at text not null default '',
  primary key (job, trial));
]]

function M.open(db) db:exec(M.ddl) end

local RED = " %(red%)$"

local function assertion(node)
  -- the deepest failing call: a red proof must fail at a check (a Should keyword), not on its way there
  for _, c in ipairs(node.children or node.body or {}) do
    if c.status == "FAIL" then return assertion(c) end
  end
  return node.name and node.name:lower():find("^should") ~= nil
end

function M.verdicts(res)
  local red, out = {}, {}
  for _, t in ipairs(res.tests) do
    if t.name:find(RED) then red[t.name:gsub(RED, "")] = t end
  end
  for _, t in ipairs(res.tests) do
    if not t.name:find(RED) then
      local r = red[t.name]
      local v
      if t.status == "SKIP" then v = "unknown"
      elseif t.status == "FAIL" then v = "KILLED"
      elseif not r then v = "unproven"
      elseif r.status == "PASS" then v = "BLIND"
      elseif r.status == "FAIL" and assertion(r) then v = "holds"
      else v = "unproven" end
      out[#out + 1] = { name = t.name, verdict = v, status = t.status, message = t.message or "", tags = t.tags or {},
        red = r and (r.status .. (r.message and (": " .. r.message) or "")) or "none" }
    end
  end
  return out
end

local function hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return ("%08x"):format(h)
end

function M.hashes(text)
  local _, items = robot.parse.cut(text)
  local tests, keywords, out = {}, {}, {}
  for _, it in ipairs(items) do
    if it.kind == "keyword" then keywords[#keywords + 1] = it
    elseif it.kind == "test" then tests[it.name] = it.text end
  end
  local vars = text:match("%*%*%* Variables %*%*%*\n(.-)\n%*%*%*") or ""
  for name, body in pairs(tests) do
    if not name:find(RED) then
      local parts = { body, tests[name .. " (red)"] or "", vars }
      local seen = body .. (tests[name .. " (red)"] or "")
      for _, k in ipairs(keywords) do
        if robot.norm(seen):find(robot.norm(k.name), 1, true) then parts[#parts + 1] = k.text end
      end
      out[name] = hash(table.concat(parts, "\0"))
    end
  end
  return out
end

function M.record(db, todo, n, commit, draft, verdicts, hashes)
  db:exec("insert or replace into claims_run (todo, n, at, commit_id, draft) values (?, ?, ?, ?, ?)",
    { todo, n, os.date("!%Y-%m-%dT%H:%M:%SZ"), commit or "", draft and 1 or 0 })
  local flags = {}
  for _, v in ipairs(verdicts) do
    local h = hashes[v.name] or ""
    -- the last counted run that killed this claim, with other text than now
    local k = db:exec("select c.n, c.hash from claim c join claims_run r on r.todo = c.todo and r.n = c.n"
      .. " where c.todo = ? and c.name = ? and c.verdict = 'KILLED' and r.draft = 0 and r.invalid = 0"
      .. " order by c.n desc limit 1", { todo, v.name })[1]
    if k and k.hash ~= h then flags[v.name] = ("edited after run %d killed it"):format(k.n) end
    db:exec("insert or replace into claim (todo, n, name, verdict, status, message, tags, hash, flag, red) values"
      .. " (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", { todo, n, v.name, v.verdict, v.status, v.message,
      table.concat(v.tags or {}, " "), h, flags[v.name] or "", v.red or "" })
  end
  return flags
end

function M.invalid(db, todo, n, why)
  local r = db:exec("select n from claims_run where todo = ? and n = ?", { todo, n })[1]
  if not r then error(("no run %d of %s"):format(n, todo), 0) end
  db:exec("update claims_run set invalid = 1, why = ? where todo = ? and n = ?", { why, todo, n })
end

function M.history(db)
  return db:exec("select c.todo, c.name, group_concat(c.n || ':' || c.verdict || case when r.draft = 1 then '(draft)'"
    .. " else '' end || case when r.invalid = 1 then '(invalid)' else '' end || case when c.flag != '' then '!' else '' end, ' ')"
    .. " as runs from (select rowid as rid, * from claim order by n) c join claims_run r on r.todo = c.todo and r.n = c.n"
    .. " group by c.todo, c.name order by c.todo, min(c.rid)")
end

return M
