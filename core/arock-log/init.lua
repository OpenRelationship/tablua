-- arock-log: an append-only log of events, the state folded from it, and
-- recall over both, in one SQLite file behind a database port.
--
--   local s = alog.open(db, opts)              -- db:exec(sql, params) -> rows
--     opts.clock()      -> the event's time (default UTC ISO 8601)
--     opts.hash(bytes)  -> a blob id (default a portable 64-bit hash)
--     opts.replicated   -> apply alog.LITESTREAM's settings first
--   s:append(task, keyword, { args... }, actor) -- -> seq; actor defaults to "agent"
--   s:batch(fn)                                -- appends inside fn are one transaction: all kept, or none
--   s:undo(seq, actor)                         -- an Undo event; the fold skips seq
--   s:load(task, source, entries, actor)       -- one Load Workspace event -> seq;
--                                              -- entries { path, blob, content }
--   s:rebuild()                                -- state from the log (and the snapshot)
--   s:snapshot()                               -- the state kept at the newest seq -> seq
--   s:events(after?), s:history(task)          -- { seq, task, keyword, actor, args }; after a seq
--   s:blob(id)                                 -- a content argument's bytes
--   s:files_at(seq)                            -- { path = content } as of event seq
--   s:artifact(name)                           -- { name, seq, task } of its last Publish Artifact
--   s:artifact_at(name, seq)                   -- the same, as the log stood just before seq
--   s:file(path), s:paths(), s:search_files(q, n), s:task(task), s:count(), s:dump()
--   s:recall(query, n)                         -- { events = {...}, files = {...} }, best first
--   alog.tokens(text)                          -- the words recall indexes and searches by
--   s:robot()                                  -- the log as Robot rows
--   s:settings()                               -- the SQLite settings Litestream depends on
--   alog.fields(event)                         -- its arguments by name (arock-log.kinds)
--
-- An event is a Robot keyword call: the keyword names what happened and the
-- arguments are strings. arock-log.kinds declares the keywords arock-log knows; those
-- with a fold change the state, and any other keyword is recorded and
-- recalled but changes nothing.
local schema = require("arock-log.schema")
local kinds = require("arock-log.kinds")
local blobs = require("arock-log.blobs")
local folds = require("arock-log.fold")
local robot = require("arock-log.robot")
local recall = require("arock-log.recall")
local tokens = require("arock-log.tokens")

local M = {}
M.LITESTREAM = schema.litestream
M.kinds = kinds.args
M.fields = kinds.fields
M.tokens = tokens.tokens
M.TOKEN_BYTES = tokens.TOKEN_BYTES
M.TOKENS = tokens.TOKENS

local Store = {}
Store.__index = Store

-- The state matches this version of arock-log, or is dropped and folded again.
local function current(db)
  if not db:exec("select 1 as x from sqlite_master where name = 'alog_state'")[1] then return false end
  local r = db:exec("select version from alog_state")[1]
  return r and r.version == schema.version
end

function M.open(db, opts)
  opts = opts or {}
  if opts.replicated then
    for _, pragma in ipairs(M.LITESTREAM) do db:exec(pragma) end
  end
  local clock = opts.clock or function() return os.date("!%Y-%m-%dT%H:%M:%SZ") end
  local s = setmetatable({ db = db, clock = clock, hash = opts.hash or blobs.hash }, Store)
  if not current(db) then
    s:atomic(function()
      db:exec(schema.log)
      db:exec(schema.drop)
      db:exec(schema.state)
      db:exec("delete from alog_state")
      db:exec("insert into alog_state (version) values (?)", { schema.version })
      folds.refold(s)
      recall.index_log(s)
    end)
  end
  return s
end

local actors = { agent = true, user = true, host = true }

local function check(task, keyword, args, actor)
  assert(actors[actor], "actor must be agent, user or host: " .. tostring(actor))
  assert(type(task) == "string" and task:match("^[%w_.:-]+$"), "task must be a plain name: " .. tostring(task))
  local words = type(keyword) == "string"
    and (keyword:match("^%u$") or keyword:match("^%u[%w ]*%w$") and not keyword:find("  ", 1, true))
  assert(words, "keyword must be capitalised words with single spaces: " .. tostring(keyword))
  for i, v in ipairs(args) do
    assert(type(v) == "string", keyword .. " argument " .. i .. " is not a string")
  end
  kinds.check(keyword, args)
end

-- One transaction, taken for writing at once so a second writer waits on
-- busy_timeout instead of failing; on error it rolls back and the error goes on.
function Store:atomic(fn)
  self.db:exec("begin immediate")
  local ok, res = pcall(fn)
  if not ok then
    self.db:exec("rollback")
    error(res, 0)
  end
  self.db:exec("commit")
  return res
end

-- Logs one event: content arguments go to blobs and their ids to args; recall
-- indexes the arguments with the text of their content.
local function record(self, task, keyword, args, actor)
  local spec, kept, words = kinds.spec[keyword] or {}, {}, {}
  for i, v in ipairs(args) do
    if spec[i] and spec[i].blob then
      kept[i] = blobs.put(self.db, self.hash, v)
      words[i] = blobs.text(v) or ""
    else
      kept[i], words[i] = v, v
    end
  end
  self.db:exec("insert into events (at, task, keyword, actor) values (?, ?, ?, ?)",
    { self.clock(), task, keyword, actor })
  local seq = self.db:exec("select last_insert_rowid() as seq")[1].seq
  for i, v in ipairs(kept) do
    self.db:exec("insert into args (seq, pos, value) values (?, ?, ?)", { seq, i, v })
  end
  recall.index_event(self.db, seq, keyword, words)
  return seq, kept
end

function Store:append(task, keyword, args, actor)
  args, actor = args or {}, actor or "agent"
  check(task, keyword, args, actor)
  assert(keyword ~= "Undo", "use alog:undo to undo")
  assert(keyword ~= "Load Workspace", "use alog:load to load a workspace")
  local function go()
    local seq, kept = record(self, task, keyword, args, actor)
    if folds.fold[keyword] then folds.fold[keyword](self, task, kept, seq) end
    recall.settle(self.db)
    return seq
  end
  if self.batching then return go() end
  return self:atomic(go)
end

-- Several appends as one transaction: all of them are kept, or none.
function Store:batch(fn)
  return self:atomic(function()
    self.batching = true
    local ok, res = pcall(fn)
    self.batching = false
    if not ok then error(res, 0) end
    return res
  end)
end

function Store:load(task, source, entries, actor)
  actor = actor or "host"
  local args = { tostring(source), tostring(#entries) }
  check(task, "Load Workspace", args, actor)
  return self:atomic(function()
    local seq = record(self, task, "Load Workspace", args, actor)
    for _, e in ipairs(entries) do
      assert(type(e.path) == "string" and type(e.blob) == "string" and type(e.content) == "string",
        "a load entry needs path, blob and content strings")
      self.db:exec("insert or ignore into blobs (id, content) values (?, ?)", { e.blob, e.content })
      self.db:exec("insert into loads (seq, path, blob) values (?, ?, ?)", { seq, e.path, e.blob })
    end
    folds.fold["Load Workspace"](self, task, args, seq)
    recall.settle(self.db)
    return seq
  end)
end

function Store:undo(seq, actor)
  actor = actor or "agent"
  assert(actors[actor], "actor must be agent, user or host: " .. tostring(actor))
  local target = self.db:exec("select task from events where seq = ?", { seq })[1]
  assert(target, "no event " .. tostring(seq) .. " to undo")
  return self:atomic(function()
    local undo = record(self, target.task, "Undo", { tostring(seq) }, actor)
    folds.refold(self)
    recall.settle(self.db)
    return undo
  end)
end

function Store:refold() folds.refold(self) end

function Store:rebuild()
  self:atomic(function() folds.refold(self) end)
end

function Store:snapshot()
  return self:atomic(function() return folds.snapshot(self) end)
end

-- Events with their arguments in log order, read in one query: all of them,
-- or one task's, or those up to a seq.
local function read(self, where, params)
  local rows = self.db:exec("select e.seq, e.task, e.keyword, e.actor, a.value from events e"
    .. " left join args a on a.seq = e.seq " .. where .. " order by e.seq, a.pos", params)
  local out, last = {}, nil
  for _, r in ipairs(rows) do
    if not last or last.seq ~= r.seq then
      last = { seq = r.seq, task = r.task, keyword = r.keyword, actor = r.actor, args = {} }
      out[#out + 1] = last
    end
    if r.value ~= nil then last.args[#last.args + 1] = r.value end
  end
  return out
end

function Store:events(after)
  if after then return read(self, "where e.seq > ?", { after }) end
  return read(self, "", {})
end

function Store:history(task)
  return read(self, "where e.task = ?", { task })
end

function Store:blob(id)
  return blobs.get(self.db, id)
end

function Store:files_at(seq)
  return folds.files_at(self, read(self, "where e.seq <= ?", { seq }))
end

function Store:artifact_at(name, seq)
  local events = read(self, "where e.seq < ?", { seq })
  local gone, found = folds.cancelled(events), nil
  for _, e in ipairs(events) do
    if not gone[e.seq] and e.keyword == "Publish Artifact" and e.args[1] == name then
      found = { name = name, seq = e.seq, task = e.task }
    end
  end
  return found
end

function Store:artifact(name)
  return self.db:exec("select name, seq, task from artifacts where name = ?", { name })[1]
end

function Store:count()
  return self.db:exec("select count(*) as n from events")[1].n
end

function Store:file(path)
  local r = self.db:exec("select b.content from files f join blobs b on b.id = f.blob where f.path = ? and f.dir = 0",
    { path })[1]
  return r and r.content
end

-- Every path, folders too.
function Store:paths()
  local out = {}
  for i, r in ipairs(self.db:exec("select path from files order by path")) do out[i] = r.path end
  return out
end

-- Paths whose path or content holds any of the words of q, best first.
function Store:search_files(q, n)
  local out = {}
  for i, r in ipairs(recall.files(self.db, q, n or 10)) do out[i] = r.path end
  return out
end

function Store:task(task)
  return self.db:exec("select * from tasks where task = ?", { task })[1]
end

-- The whole state as text, for comparing two states exactly.
function Store:dump()
  local out = {}
  local function add(sql, cols)
    for _, r in ipairs(self.db:exec(sql)) do
      local cells = {}
      for i, c in ipairs(cols) do cells[i] = ("%q"):format(tostring(r[c])) end
      out[#out + 1] = table.concat(cells, " ")
    end
  end
  add("select * from tasks order by task", { "task", "machine", "state", "result", "detail" })
  add("select * from files order by path", { "path", "dir", "blob", "seq" })
  add("select * from artifacts order by name", { "name", "seq", "task" })
  add("select * from undone order by seq", { "seq" })
  out[#out + 1] = recall.dump(self.db)
  return table.concat(out, "\n")
end

-- The settings a streamed file depends on, as SQLite reports them now.
function Store:settings()
  local function one(name)
    local r = self.db:exec("pragma " .. name)[1] or {}
    local _, v = next(r)
    return v
  end
  return {
    journal_mode = one("journal_mode"), synchronous = one("synchronous"),
    wal_autocheckpoint = one("wal_autocheckpoint"), busy_timeout = one("busy_timeout"),
  }
end

-- Events and files holding any word of q (arock-log.tokens, so no query text is
-- syntax), ranked by bm25: those that hold more of them, and rarer ones, first.
function Store:recall(q, n)
  n = n or 10
  local found = { events = {}, files = {} }
  for _, h in ipairs(recall.events(self.db, q, n)) do
    local e = read(self, "where e.seq = ?", { h.seq })[1]
    e.undone = self.db:exec("select 1 as x from undone where seq = ?", { e.seq })[1] ~= nil
    found.events[#found.events + 1] = e
  end
  for i, f in ipairs(recall.files(self.db, q, n)) do found.files[i] = { path = f.path } end
  return found
end

-- The log as Robot rows: one test per task, in order of first appearance.
function Store:robot()
  local tests, by = {}, {}
  for _, e in ipairs(self:events()) do
    if not by[e.task] then
      by[e.task] = { name = e.task, rows = {} }
      tests[#tests + 1] = by[e.task]
    end
    local rows = by[e.task].rows
    rows[#rows + 1] = { keyword = e.keyword, args = e.args }
  end
  return robot.render(tests)
end

return M
