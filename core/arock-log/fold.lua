-- How the log becomes the state: one fold per keyword that changes it, the
-- undos that cancel events, refolding from the newest snapshot the log still
-- agrees with, and taking a snapshot.
local blobs = require("arock-log.blobs")
local recall = require("arock-log.recall")
local org = require("arock-log.org")

local M = {}

-- path itself, or anything under it as a folder: the paths from "p/" up to
-- "p0" ('0' is the byte after '/'), compared byte for byte, so SQLite reads no
-- path as text
local UNDER = "(path = ?1 or (path >= ?1 || '/' and path < ?1 || '0'))"

local function index(s, path, blob) recall.index_file(s.db, path, blob) end

local fold
fold = {
  ["Start Task"] = function(s, task, a)
    s.db:exec("insert or replace into tasks (task, machine) values (?, ?)", { task, a[1] })
  end,
  ["Enter State"] = function(s, task, a)
    s.db:exec("update tasks set state = ? where task = ?", { a[1], task })
  end,
  ["Test Result"] = function(s, task, a)
    s.db:exec("update tasks set result = ?, detail = ? where task = ?", { a[1], a[2] or false, task })
  end,
  -- a[2] is the blob's id: append kept the content
  ["Write File"] = function(s, _, a, seq)
    s.db:exec("insert or replace into files (path, dir, blob, seq) values (?, 0, ?, ?)", { a[1], a[2], seq })
    index(s, a[1], a[2])
  end,
  ["Make Folder"] = function(s, _, a, seq)
    s.db:exec("insert or ignore into files (path, dir, blob, seq) values (?, 1, null, ?)", { a[1], seq })
  end,
  ["Delete File"] = function(s, _, a)
    s.db:exec("delete from files where " .. UNDER, { a[1] })
    recall.forget(s.db, a[1], true)
  end,
  -- a file at the destination is replaced; a folder moves with all under it
  ["Move File"] = function(s, _, a, seq)
    local from, to = a[1], a[2]
    s.db:exec("delete from files where path = ? and dir = 0", { to })
    for _, r in ipairs(s.db:exec("select path from files where " .. UNDER .. " order by path", { from })) do
      s.db:exec("update files set path = ?, seq = ? where path = ?", { to .. r.path:sub(#from + 1), seq, r.path })
    end
    recall.move(s.db, from, to)
  end,
  -- a repository brought in once: its files, from the load's rows
  ["Load Workspace"] = function(s, _, _, seq)
    for _, r in ipairs(s.db:exec("select path, blob from loads where seq = ?", { seq })) do
      fold["Write File"](s, nil, { r.path, r.blob }, seq)
    end
  end,
  ["Publish Artifact"] = function(s, task, a, seq)
    s.db:exec("insert or replace into artifacts (name, seq, task) values (?, ?, ?)", { a[1], seq, task })
  end,
  -- org on the log (arock-log.org_log); a[3] and a[2] below are blob ids: append kept the text
  ["Add Entry"] = function(s, _, a, seq)
    local text = blobs.get(s.db, a[3])
    local e = org.parse(text).entries[1] or {}
    local pos = s.db:exec("select coalesce(max(pos), 0) + 1 as pos from org_entries where path = ?", { a[1] })[1].pos
    s.db:exec("insert into org_entries (id, path, pos, keyword, title, text, seq) values (?, ?, ?, ?, ?, ?, ?)",
      { a[2], a[1], pos, e.keyword or false, e.title or false, text, seq })
  end,
  ["Edit Entry"] = function(s, _, a, seq)
    local text = blobs.get(s.db, a[2])
    local e = org.parse(text).entries[1] or {}
    s.db:exec("update org_entries set text = ?, keyword = ?, title = ?, seq = ? where id = ?",
      { text, e.keyword or false, e.title or false, seq, a[1] })
  end,
  ["Archive Entry"] = function(s, _, a, seq)
    s.db:exec("update org_entries set archived = 1, seq = ? where id = ?", { seq, a[1] })
  end,
  ["Move Entry"] = function(s, _, a)
    local i = 0
    for id in a[2]:gmatch("%S+") do
      i = i + 1
      s.db:exec("update org_entries set pos = ? where id = ? and path = ?", { i, id, a[1] })
    end
  end,
  ["Set Header"] = function(s, _, a, seq)
    s.db:exec("insert or replace into org_files (path, header, seq) values (?, ?, ?)", { a[1], blobs.get(s.db, a[2]), seq })
  end,
}
M.fold = fold

-- The seqs an Undo cancels. An Undo cancels its target unless the Undo is
-- itself undone, so walking backwards settles every chain of undos.
function M.cancelled(events)
  local out = {}
  for i = #events, 1, -1 do
    local e = events[i]
    if not out[e.seq] and e.keyword == "Undo" then out[tonumber(e.args[1])] = true end
  end
  return out
end

-- The newest snapshot no later Undo reaches behind, and the events after it.
local function base(s)
  local snap = s.db:exec("select max(seq) as seq from snapshots")[1]
  local at = snap and snap.seq
  if at then
    local after = s:events(at)
    for _, e in ipairs(after) do
      if e.keyword == "Undo" and tonumber(e.args[1]) <= at then return nil, s:events() end
    end
    return at, after
  end
  return nil, s:events()
end

-- The postings of the log and of the blobs are not here: undo and refold
-- never change them.
local TABLES = { "tasks", "files", "artifacts", "undone", "recall_paths", "org_entries", "org_files" }

-- The state from the log alone (from a snapshot when one still holds).
function M.refold(s)
  local db = s.db
  for _, t in ipairs(TABLES) do db:exec("delete from " .. t) end
  local at, events = base(s)
  if at then
    db:exec("insert into tasks select task, machine, state, result, detail from snap_tasks where seq = ?", { at })
    db:exec("insert into files select path, dir, blob, fseq from snap_files where seq = ?", { at })
    db:exec("insert into artifacts select name, aseq, task from snap_artifacts where seq = ?", { at })
    db:exec("insert into undone select undone from snap_undone where seq = ?", { at })
    db:exec("insert into org_entries select id, path, pos, keyword, title, archived, text, eseq from snap_org_entries"
      .. " where seq = ?", { at })
    db:exec("insert into org_files select path, header, fseq from snap_org_files where seq = ?", { at })
    for _, r in ipairs(db:exec("select path, blob from files where dir = 0")) do index(s, r.path, r.blob) end
  end
  local gone = M.cancelled(events)
  for _, e in ipairs(events) do
    if gone[e.seq] then
      db:exec("insert into undone (seq) values (?)", { e.seq })
    elseif fold[e.keyword] then
      fold[e.keyword](s, e.task, e.args, e.seq)
    end
  end
end

-- The state as of the newest event, kept beside the log; older snapshots go.
function M.snapshot(s)
  local db = s.db
  local at = db:exec("select max(seq) as seq from events")[1].seq
  if not at then return nil end
  for _, t in ipairs({ "snapshots", "snap_tasks", "snap_files", "snap_artifacts", "snap_undone", "snap_org_entries",
    "snap_org_files" }) do
    db:exec("delete from " .. t)
  end
  db:exec("insert into snapshots (seq) values (?)", { at })
  db:exec("insert into snap_tasks select ?, task, machine, state, result, detail from tasks", { at })
  db:exec("insert into snap_files select ?, path, dir, blob, seq from files", { at })
  db:exec("insert into snap_artifacts select ?, name, seq, task from artifacts", { at })
  db:exec("insert into snap_undone select ?, seq from undone", { at })
  db:exec("insert into snap_org_entries select ?, id, path, pos, keyword, title, archived, text, seq from org_entries", { at })
  db:exec("insert into snap_org_files select ?, path, header, seq from org_files", { at })
  return at
end

-- The files as the log stood at event seq, { path = content }: undos made
-- later do not reach back, so a published version never changes.
function M.files_at(s, events)
  local gone, at = M.cancelled(events), {}
  local function under(p, root) return p == root or p:sub(1, #root + 1) == root .. "/" end
  for _, e in ipairs(events) do
    local a = e.args
    if gone[e.seq] then
      -- cancelled
    elseif e.keyword == "Load Workspace" then
      for _, r in ipairs(s.db:exec("select path, blob from loads where seq = ?", { e.seq })) do at[r.path] = r.blob end
    elseif e.keyword == "Write File" then
      at[a[1]] = a[2]
    elseif e.keyword == "Delete File" then
      for p in pairs(at) do if under(p, a[1]) then at[p] = nil end end
    elseif e.keyword == "Move File" then
      local moved = {}
      for p, id in pairs(at) do
        if under(p, a[1]) then moved[a[2] .. p:sub(#a[1] + 1)] = id; at[p] = nil end
      end
      for p, id in pairs(moved) do at[p] = id end
    end
  end
  local files = {}
  for p, id in pairs(at) do files[p] = blobs.get(s.db, id) end
  return files
end

return M
