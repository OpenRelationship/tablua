-- Recall: arock-log's own full-text index, in plain tables, ranked by bm25 in Lua.
-- SQLite stores the tokens and compares them as bound values; it never reads
-- the agent's text itself (Arock's PROJECT.md §14.7, item 9).
--
-- Documents, each tokenized by arock-log.tokens; len is a document's token count,
-- tf a term's count in it:
--   an event  kind 0, doc = seq: keyword .. " " .. its arguments' recall text
--             joined by " " (a content argument's blobs.text, or "" when it
--             is binary). recall_events (seq, len). Undo and refold leave it.
--   a blob    kind 1, doc = recall_blobs.id: a text content's tokens, once per
--             content however many files hold it. recall_blobs (id, blob, len).
--   a file    its path's tokens and its blob's, while its content is text:
--             recall_paths (path, blob = recall_blobs.id, len, terms), terms
--             being the path's tokens joined by " ". The folds keep it, and a
--             move tokenizes only the new paths.
-- An event's or blob's postings go first to recall_pending (kind, doc, term,
-- tf, len), in doc order, so a commit writes a page or two at its end rather
-- than one per term (Litestream ships every page written). Once it holds
-- FLUSH rows, FLUSH_SQL packs them into recall_blocks (kind, term, first,
-- postings), one row per term: "doc tf len" triples joined by " ", each doc
-- less first. A search reads a term's blocks by key and scans the pending.
local tokens = require("arock-log.tokens")
local blobs = require("arock-log.blobs")
local kinds = require("arock-log.kinds")

local M = {}
M.tokens = tokens.tokens
M.K1, M.B = 1.2, 0.75 -- FTS5's bm25 defaults
M.QUERY_TERMS = 32    -- distinct words of a query that count
M.FLUSH = 50000       -- pending rows that are packed into blocks
M.EVENT, M.BLOB = 0, 1

M.FLUSH_SQL = [[
insert into recall_blocks (kind, term, first, postings)
  select kind, term, first, group_concat((doc - first) || ' ' || tf || ' ' || len, ' ')
  from (select kind, term, doc, tf, len, min(doc) over (partition by kind, term) as first from recall_pending)
  group by kind, term, first;
delete from recall_pending;
]]

local ROWS = 100 -- rows per insert statement

-- A document's distinct terms in order of first use, their counts, and its length.
local function count(text)
  local list, tf, order = M.tokens(text), {}, {}
  for _, t in ipairs(list) do
    if not tf[t] then tf[t] = 0; order[#order + 1] = t end
    tf[t] = tf[t] + 1
  end
  return order, tf, #list
end

-- A document's postings into recall_pending, at most ROWS rows a statement.
local function pend(db, kind, doc, order, tf, len)
  local one = "(?, ?, ?, ?, ?)"
  for i = 1, #order, ROWS do
    local params, rows = {}, math.min(ROWS, #order - i + 1)
    for j = 0, rows - 1 do
      local t = order[i + j]
      for _, v in ipairs({ kind, doc, t, tf[t], len }) do params[#params + 1] = v end
    end
    db:exec("insert into recall_pending (kind, doc, term, tf, len) values " .. (one .. ", "):rep(rows - 1) .. one, params)
  end
end

-- Packs the pending postings once there are FLUSH of them; at the end of each append.
function M.settle(db, force)
  local r = db:exec("select count(*) as n from recall_pending")[1]
  if r.n > 0 and (force or r.n >= M.FLUSH) then db:exec(M.FLUSH_SQL) end
end

-- One event, as it is logged; words are its arguments' recall text.
function M.index_event(db, seq, keyword, words)
  local order, tf, len = count(keyword .. " " .. table.concat(words, " "))
  db:exec("insert into recall_events (seq, len) values (?, ?)", { seq, len })
  pend(db, M.EVENT, seq, order, tf, len)
end

-- An event's arguments as recall reads them: content by its text.
function M.words(db, keyword, args)
  local spec, words = kinds.spec[keyword] or {}, {}
  for i, v in ipairs(args) do
    if spec[i] and spec[i].blob then words[i] = blobs.text(blobs.get(db, v) or "") or "" else words[i] = v end
  end
  return words
end

-- The whole log again, when the index is new (open, at a new version).
function M.index_log(s)
  for _, e in ipairs(s:events()) do
    M.index_event(s.db, e.seq, e.keyword, M.words(s.db, e.keyword, e.args))
    M.settle(s.db)
  end
end

-- path itself, or anything under it as a folder (fold.lua's UNDER)
local UNDER = "(path = ?1 or (path >= ?1 || '/' and path < ?1 || '0'))"

-- Forgets a file's path, or with under, everything under it too.
function M.forget(db, path, under)
  db:exec("delete from recall_paths where " .. (under and UNDER or "path = ?1"), { path })
end

-- A blob's recall id, indexing its content the first time; nil when binary.
local function blob_id(db, blob)
  local r = db:exec("select id from recall_blobs where blob = ?", { blob })[1]
  if r then return r.id end
  local text = blobs.text(blobs.get(db, blob) or "")
  if not text then return nil end
  local order, tf, len = count(text)
  db:exec("insert into recall_blobs (blob, len) values (?, ?)", { blob, len })
  local id = db:exec("select last_insert_rowid() as id")[1].id
  pend(db, M.BLOB, id, order, tf, len)
  return id
end

-- A file at path now holds blob (a content's id in the log).
function M.index_file(db, path, blob)
  M.forget(db, path)
  local id = blob and blob_id(db, blob)
  if not id then return end
  local list = M.tokens(path)
  db:exec("insert into recall_paths (path, blob, len, terms) values (?, ?, ?, ?)",
    { path, id, #list, table.concat(list, " ") })
end

-- A move: a file at `to` is replaced, and every path under `from` is
-- tokenized again where it went.
function M.move(db, from, to)
  M.forget(db, to)
  local moved = db:exec("select path, blob, len from recall_paths where " .. UNDER, { from })
  M.forget(db, from, true)
  for _, r in ipairs(moved) do
    local list = M.tokens(to .. r.path:sub(#from + 1))
    db:exec("insert into recall_paths (path, blob, len, terms) values (?, ?, ?, ?)",
      { to .. r.path:sub(#from + 1), r.blob, #list, table.concat(list, " ") })
  end
end

-- The postings of one kind for each term of list, pending (in one pass over
-- them) and packed: fn(i, doc, tf, len) each, i the term's place in list.
local function postings(db, kind, list, fn)
  local at, params = {}, { kind }
  for i, t in ipairs(list) do at[t] = i; params[i + 1] = t end
  local sql = "select doc, term, tf, len from recall_pending where kind = ? and term in ("
    .. ("?, "):rep(#list - 1) .. "?)"
  for _, r in ipairs(db:exec(sql, params)) do fn(at[r.term], r.doc, r.tf, r.len) end
  for i, t in ipairs(list) do
    for _, r in ipairs(db:exec("select first, postings from recall_blocks where kind = ? and term = ?", { kind, t })) do
      for doc, tf, len in r.postings:gmatch("(%d+) (%d+) (%d+)") do fn(i, r.first + doc, tonumber(tf), tonumber(len)) end
    end
  end
end

-- A query's distinct tokens, in order, at most QUERY_TERMS.
local function terms(q)
  local out, seen = {}, {}
  for _, t in ipairs(M.tokens(q)) do
    if not seen[t] and #out < M.QUERY_TERMS then seen[t] = true; out[#out + 1] = t end
  end
  return out
end

-- FTS5's bm25 over hits, one { key = tf } per query term in query order and
-- the length of each key: for each term, idf * f * (k1 + 1) / (f + k1 * (1 -
-- b + b * len / avgdl)) with idf = ln((N - n + 0.5) / (n + 0.5)), 1e-6 when
-- that is not above 0. The best n, then by key: { [name] = key, score }.
local function rank(hits, lens, N, total, n, name)
  local avgdl, score = total / N, {}
  for _, hit in ipairs(hits) do
    local df = 0
    for _ in pairs(hit) do df = df + 1 end
    local idf = math.log((N - df + 0.5) / (df + 0.5))
    if idf <= 0 then idf = 1e-6 end
    for key, f in pairs(hit) do
      score[key] = (score[key] or 0) + idf * (f * (M.K1 + 1)) / (f + M.K1 * (1 - M.B + M.B * lens[key] / avgdl))
    end
  end
  local top = {} -- the best n so far, best first
  for key, sc in pairs(score) do
    local i = #top
    while i > 0 and (top[i].score < sc or top[i].score == sc and top[i][name] > key) do i = i - 1 end
    if i < n then
      table.insert(top, i + 1, { [name] = key, score = sc })
      top[n + 1] = nil
    end
  end
  return top
end

-- Events holding any word of q, best first: { seq, score }.
function M.events(db, q, n)
  local list, hits, lens, any = terms(q), {}, {}, false
  if #list == 0 then return {} end
  for i = 1, #list do hits[i] = {} end
  postings(db, M.EVENT, list, function(i, seq, tf, len) hits[i][seq], lens[seq], any = tf, len, true end)
  if not any then return {} end
  local stats = db:exec("select count(*) as n, sum(len) as total from recall_events")[1]
  return rank(hits, lens, stats.n, stats.total, n or 10, "seq")
end

-- Files whose path or content holds any word of q, best first: { path, score }.
-- It reads every text file's path row: a computer's files, not its log.
function M.files(db, q, n)
  local list = terms(q)
  if #list == 0 then return {} end
  local files, by, lens, total = db:exec("select p.path, p.blob, p.len + b.len as len, p.terms from recall_paths p"
    .. " join recall_blobs b on b.id = p.blob"), {}, {}, 0
  for _, f in ipairs(files) do
    total, lens[f.path] = total + f.len, f.len
    by[f.blob] = by[f.blob] or {}
    table.insert(by[f.blob], f.path)
  end
  local hits, at, any = {}, {}, false
  for i, t in ipairs(list) do hits[i], at[t] = {}, i end
  for _, f in ipairs(files) do
    for w in f.terms:gmatch("%S+") do
      local hit = at[w] and hits[at[w]]
      if hit then hit[f.path], any = (hit[f.path] or 0) + 1, true end
    end
  end
  postings(db, M.BLOB, list, function(i, id, tf)
    for _, path in ipairs(by[id] or {}) do hits[i][path], any = (hits[i][path] or 0) + tf, true end
  end)
  if not any then return {} end
  return rank(hits, lens, #files, total, n or 10, "path")
end

-- The index as sorted lines, the same however its postings were packed: the
-- log's, then the files' (blobs only while a path holds them, named by id in
-- the log, since a blob's postings outlive its files).
function M.dump(db)
  local out, name, held = {}, {}, {}
  for _, r in ipairs(db:exec("select seq, len from recall_events order by seq")) do
    out[#out + 1] = ("event %d %d"):format(r.seq, r.len)
  end
  for _, r in ipairs(db:exec("select b.id, b.blob, b.len, p.path, p.len as plen, p.terms from recall_paths p"
    .. " join recall_blobs b on b.id = p.blob order by p.path")) do
    name[r.id], held[r.id] = r.blob, true
    out[#out + 1] = ("path %q %q %d %q %d"):format(r.path, r.blob, r.plen, r.terms, r.len)
  end
  local posts = {}
  local function post(kind, term, doc, tf, len)
    if kind == M.EVENT then posts[#posts + 1] = ("e %q %d %d %d"):format(term, doc, tf, len)
    elseif held[doc] then posts[#posts + 1] = ("b %q %q %d %d"):format(term, name[doc], tf, len) end
  end
  for _, r in ipairs(db:exec("select kind, term, doc, tf, len from recall_pending")) do post(r.kind, r.term, r.doc, r.tf, r.len) end
  for _, r in ipairs(db:exec("select kind, term, first, postings from recall_blocks")) do
    for doc, tf, len in r.postings:gmatch("(%d+) (%d+) (%d+)") do
      post(r.kind, r.term, r.first + doc, tonumber(tf), tonumber(len))
    end
  end
  table.sort(posts)
  for _, p in ipairs(posts) do out[#out + 1] = p end
  return table.concat(out, "\n")
end

return M
