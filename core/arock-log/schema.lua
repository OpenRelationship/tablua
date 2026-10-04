-- arock-log's schema, one SQLite file.
--
-- `log` is the truth and refuses every change: events and their args, and
-- blobs (content by id) with loads (a workspace's paths). An event's actor is
-- who did it: the agent, the user, or the host.
--
-- `state` is folded from the log and can be dropped and rebuilt at any time:
-- tasks, files (folders too, a file naming its blob), artifacts, undone, the
-- recall index (recall.lua), the newest snapshot, and the `entries` view a
-- host reads its files through. When `version` changes, open() drops the old
-- state and folds the log again; the log itself is never touched.
--
-- Version 3: recall is arock-log's own index in plain tables, so SQLite never
-- parses the agent's text; version 2's FTS5 tables (recall_log, which stood
-- beside the log, and recall_files) are dropped and the index built again.
--
-- Version 4: org on the log (arock-log.org_log): each org file's entries, in order, with their folded text, and its
-- header; archived entries stay, so an ID is never given twice.
local M = {}

M.version = 4

M.log = [[
create table if not exists events (
  seq     integer primary key,
  at      text not null,
  task    text not null,
  keyword text not null,
  actor   text not null default 'agent' check (actor in ('agent', 'user', 'host'))
);
create table if not exists args (
  seq   integer not null references events (seq),
  pos   integer not null,
  value text not null,
  primary key (seq, pos)
) without rowid;
create table if not exists blobs (
  id      text primary key,
  content text not null
) without rowid;
create table if not exists loads (
  seq  integer not null references events (seq),
  path text not null,
  blob text not null references blobs (id),
  primary key (seq, path)
) without rowid;
create trigger if not exists events_no_update before update on events
  begin select raise(abort, 'the log is append-only'); end;
create trigger if not exists events_no_delete before delete on events
  begin select raise(abort, 'the log is append-only'); end;
create trigger if not exists args_no_update before update on args
  begin select raise(abort, 'the log is append-only'); end;
create trigger if not exists args_no_delete before delete on args
  begin select raise(abort, 'the log is append-only'); end;
create trigger if not exists blobs_no_update before update on blobs
  begin select raise(abort, 'the log is append-only'); end;
create trigger if not exists blobs_no_delete before delete on blobs
  begin select raise(abort, 'the log is append-only'); end;
create trigger if not exists loads_no_update before update on loads
  begin select raise(abort, 'the log is append-only'); end;
create trigger if not exists loads_no_delete before delete on loads
  begin select raise(abort, 'the log is append-only'); end;
create table if not exists alog_state (version integer not null);
]]

-- Every state table and view, by kind, so drop can name them all.
M.drop = [[
drop view if exists entries;
drop table if exists tasks; drop table if exists files; drop table if exists artifacts;
drop table if exists undone; drop table if exists recall_files; drop table if exists snapshots;
drop table if exists snap_tasks; drop table if exists snap_files; drop table if exists snap_artifacts;
drop table if exists snap_undone; drop table if exists recall_log; drop table if exists recall_events;
drop table if exists recall_blobs; drop table if exists recall_paths; drop table if exists recall_pending;
drop table if exists recall_blocks;
drop table if exists org_entries; drop table if exists org_files; drop table if exists snap_org_entries;
drop table if exists snap_org_files;
]]

M.state = [[
create table tasks (
  task    text primary key,
  machine text,
  state   text,
  result  text,
  detail  text
);
create table files (
  path text primary key,
  dir  integer not null default 0,
  blob text,
  seq  integer not null
);
create table artifacts (
  name text primary key,
  seq  integer not null,
  task text not null
);
create table undone (seq integer primary key);

-- org on the log: an entry's text as last added or edited, where it sits, and whether it was archived
create table org_entries (
  id       text primary key,
  path     text not null,
  pos      integer not null,
  keyword  text,
  title    text,
  archived integer not null default 0,
  text     text not null,
  seq      integer not null
);
create table org_files (path text primary key, header text not null, seq integer not null);

-- recall (recall.lua): each event's and text blob's length, each text
-- file's path, and their postings, pending in doc order, then packed by term
create table recall_events (seq integer primary key, len integer not null);
create table recall_blobs (id integer primary key, blob text not null unique, len integer not null);
create table recall_paths (
  path text primary key, blob integer not null, len integer not null, terms text not null
) without rowid;
create table recall_pending (
  kind integer not null, doc integer not null, term text not null, tf integer not null, len integer not null,
  primary key (kind, doc, term)
) without rowid;
create table recall_blocks (
  kind integer not null, term text not null, first integer not null, postings text not null,
  primary key (kind, term, first)
) without rowid;

create table snapshots (seq integer primary key);
create table snap_tasks (seq integer not null, task text, machine text, state text, result text, detail text);
create table snap_files (seq integer not null, path text, dir integer, blob text, fseq integer);
create table snap_artifacts (seq integer not null, name text, aseq integer, task text);
create table snap_undone (seq integer not null, undone integer);
create table snap_org_entries (seq integer not null, id text, path text, pos integer, keyword text, title text,
  archived integer, text text, eseq integer);
create table snap_org_files (seq integer not null, path text, header text, fseq integer);

create view entries as
  select f.path, f.dir, b.content as data, length(cast(b.content as blob)) as size, e.at, f.seq
  from files f left join blobs b on b.id = f.blob join events e on e.seq = f.seq;
]]

-- What Litestream needs of a file it streams: WAL (it reads the WAL), fsync
-- only at checkpoints, no checkpoints but its own, and a wait rather than a
-- failure while it holds its lock.
M.litestream = {
  "pragma journal_mode = wal", "pragma synchronous = normal",
  "pragma wal_autocheckpoint = 0", "pragma busy_timeout = 5000",
}

return M
