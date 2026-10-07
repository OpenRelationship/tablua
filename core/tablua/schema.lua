-- Three parts, told apart by their key (site/docs/content/log-and-build.md): the log, what the agent did, keyed by
-- (todo, n) and only ever added to (state, candidate, decision, action, change, outcome, effect, feature, label,
-- prediction, control, run, result); the build, what it is making, keyed by file and replaced as files change
-- (section, unit, shape, element, test, keyword, call, link, the break view); and the policy, keyed by neither
-- (gate, fit, ranking).
--
-- Tablua's tables: the agent's work as typed rows in its own SQLite file, beside the host's own tables and
-- never in them. One row per state decided in, per move that could have been made (with what Jev and TabPFN said
-- of it), per decision, per call a move made, per step's outcome and per run's ending; TabPFN's fits and
-- predictions; and the hand-written gates still live. Every name starts tablua_, so a host can let the
-- agent's harness write those tables and no others. Schema 3 adds the program as rows: each file's
-- sections, its top-level Lua statements, its scenarios and their step lines (tablua.program). Schema 4 adds
-- labels given after the fact (tablua_label): Jev's hindsight on each step, never an input at decision time.
-- Schema 5 adds the harness's behaviour model (tablua_effect): each step's effects, keywords from the harness's
-- telemetry (tablua.effects), each a label TabPFN predicts. Schema 6 adds the links between program rows
-- (tablua_link, tablua.links) and the view of those with nothing at their end (tablua_break), and of actions no
-- page posts to (kind orphan). Schema 7 adds the controls a step chose among on a screen (tablua_control,
-- tablua.control): a desktop world's "control" checkpoint, which one the request means. Schema 8 adds the rankings a run
-- paid TabPFN for (tablua_ranking), so a stateless stepper keeps a run's budget and reuses a ranking across steps,
-- and calls into the app's own modules that nothing defines to tablua_break (dropped and made again at open).
-- Schema 9: a code section is kind code with its language in lang (owner, 2026-10-05: Lua is the harness, not the
-- output); a file kept before it has its Lua sections renamed at open.
-- Schema 10 adds change blocks (tablua.change): each operation of a change a step made (tablua_change), and each
-- unit's columns (tablua_shape: code lines, parameters, deepest block, the file's units it names).
-- Schema 11 adds a page's elements (tablua_element, tablua.tree): each nested call of a page written in Lua, by its
-- path, so a change names one (tablua.element) and TabPFN reads what a page holds.
-- Schema 12 (owner, 2026-10-05): the tests are Robot Framework's, not Gherkin (core/robot). The build keeps each
-- test and user keyword (tablua_test, tablua_keyword) and every call either makes (tablua_call), and a call no
-- keyword answers is a break (kind call); the log keeps every keyword each test run ran, as a tree of rows
-- (tablua_result): what ran, with what, whether it passed, failed or never ran, and why. tablua_scenario and
-- tablua_line are dropped.
-- Schema 13 (owner, 2026-10-05): tasks are Tablua's own. A task is a test that does a job rather than checks one
-- (Robot's *** Tasks ***): tablua_test keeps both, told apart by kind, and its runs are kept in tablua_result as a
-- test's are, its own row typed task. tablua_task_record is each task's record over every run, by its name (a
-- task's name is what Robot knows it by): how often it ran and passed, and the keyword it fails at most (the
-- deepest, when a user keyword fails with the one inside it).
-- A file kept before it has the kind column added at open (M.migrate).
-- Schema 14 (owner, 2026-10-05): what the agent is asked to do is a todo, org's word for a thing to be done, so
-- that task means one thing, a Robot task. Every log table's key is (todo, n), not (task, n); a file kept before it
-- has the column renamed at open (M.migrate).
-- Schema 15 (owner, 2026-10-06): the terminal is Tablua's own (core/term). tablua_term keeps every action a step
-- sent to its terminal and the screen it left, and tablua_event what each screen says went wrong (term.read), each
-- from a source: the computer (real) or a world model that foresaw it (world). tablua_surprise is where the two part.
-- Schema 16 (owner, 2026-10-06): the terminal's every column filled. tablua_term gains what was typed (its program,
-- all its programs, whether it only reads, the files its redirections write: term.command), what the raw bytes showed
-- (how many, lines in red, yellow and green, redraws, the alternate screen: term.pty), when its first output came,
-- how many files it wrote, and where the acceptance tests stood when it ran; tablua_file keeps each file written,
-- and tablua_vector a world model's hidden state for the action (ports.agentworld's encode), as JSON numbers.
-- A file kept before it has the columns added at open (M.migrate).
-- Schema 17 (owner, 2026-10-06): tablua_term keeps what bash itself ran for each action (term's trace, its DEBUG
-- trap): the commands as the shell read them (trace) and the program each started (ran), an oracle for the columns
-- read from what was typed, measured another way.
-- Schema 18 (owner, 2026-10-06): a decision keeps what the decision model said where another policy chose
-- (said) and the text it read (state); each candidate keeps the parts its probability was made of (the decision
-- model's own prior, the tabular model's p that the move completes, the nearest states' rate), so where the parts
-- disagree, and whether the wording moved the pick, are queries.
-- Schema 19 (owner, 2026-10-06: Tablua is outfitted for Moonsplice): the comp a step left, as Moonsplice's rows
-- (msr/1, Moonsplice's .robot/docs/rows.robot), one snapshot per step (tablua_msr_*, keyed by (todo, n) then the row's own key: n = 0 is
-- the comp before any step), what lint and check found in it (tablua_msr_finding, by the node and prop each is about)
-- and how a judge scored it (tablua_score: the critic's dims, or the oracle's). A value cell holds a number or a
-- string as itself and a boolean, array or object as canonical JSON text, its type column saying which (n, s, b, j),
-- as rows.robot says. A step joins to what it changed through the snapshots.
-- Schema 20 (owner, 2026-10-06): an asset may be a solid, built by Manifold from a tree of plain values
-- (tablua_msr_asset.solid, canonical JSON; Moonsplice's .robot/docs/solids.robot), and what the engine measured of each solid is kept
-- beside the snapshot, outside its tables as derived facts are (tablua_msr_solid: parts, genus, watertight, size).
-- Schema 21 (owner, 2026-10-06): what the ask requires, as predicates lint checks (tablua_msr_expect; rows.robot,
-- "Expectations"): written once at treat by the harness, never by a move, so deleting what an ask names is an error.
-- Schema 22 (owner, 2026-10-06): every model call of a step (tablua_prompt): who was asked (writer, eye, judge,
-- director), the bytes of each part of what it read (the card, the brief, the history...), the request as sent (images
-- replaced by their size) and the reply, so what a model saw at a step is a query rather than a reconstruction.
-- Schema 23 (owner, 2026-10-07: the harness works the way pi does): the transcript a run's model reads, a row per
-- message as it joined (tablua_message: role, text, tool calls, the tool call a result answers, an image's bytes, the
-- step n it belongs to, usage and provider), as pi keeps a session; what a model saw is the rows up to its turn.
-- Schema 24 (2026-10-07): a finding's detail is part of its key: two failed expectations on one node differ only there,
-- and studio pi-s5 kept one of each such pair. A file kept before it has the table rebuilt at open, its rows kept.
-- Schema 25 (2026-10-07): an expectation the model wrote and withdrew, with its reason (tablua_withdrawal): what the
-- ask was said to require and why it no longer does, for the judge to read and a claim to count. A seed's never is.
local M = {}

M.version = 25

-- the columns schema 18 adds, each with its type, to a file kept before it
M.added = {
  tablua_prompt = { { "seconds", "real" }, { "tries", "integer" }, { "provider", "text" } },
  tablua_msr_asset = { { "solid", "text" } },
  tablua_decision = { { "said", "text" }, { "state", "text" } },
  tablua_candidate = { { "prior", "real" }, { "p_complete", "real" }, { "knn", "real" } },
}

-- the columns schemas 16 and 17 add to tablua_term, each with its type and default
M.term_columns = {
  { "program", "text not null default ''" }, { "programs", "text not null default ''" },
  { "reads", "integer not null default 0" }, { "writes", "integer not null default 0" },
  { "files", "integer not null default 0" }, { "first_ms", "real" }, { "bytes", "integer" },
  { "red", "integer" }, { "yellow", "integer" }, { "green", "integer" }, { "redraws", "integer" },
  { "alt_screen", "integer" }, { "passed", "integer" }, { "total", "integer" },
  { "trace", "text" }, { "ran", "text" },
}

M.ddl = [[
create table if not exists tablua_meta (key text primary key, value text);
create table if not exists tablua_state (
  todo text not null, n integer not null,
  stage text not null default '', passed integer, total integer, pass real,
  stalls integer not null default 0, last_verb text not null default '', last_outcome text not null default '',
  cause text not null default '', pages_ok integer, own_checks integer not null default 0,
  ask text not null default '', versions text not null default '{}', at text,
  primary key (todo, n));
create table if not exists tablua_candidate (
  todo text not null, n integer not null, move text not null,
  jev_p real, jev_conf real, jev_margin real, jev_form text not null default 'choice',
  p_progress real, p_ship real, cost_q50 real, cost_q90 real, explored integer not null default 0,
  prior real, p_complete real, knn real, primary key (todo, n, move));
create table if not exists tablua_decision (
  todo text not null, n integer not null, chosen text not null, by text not null,
  propensity real, policy text not null default '', at text, said text, state text,
  primary key (todo, n));
create table if not exists tablua_action (
  todo text not null, n integer not null, i integer not null,
  cmd text not null default '', file_kind text not null default '', op text not null default '',
  target text not null default '', bytes integer, exit integer, duration_ms real,
  primary key (todo, n, i));
create table if not exists tablua_outcome (
  todo text not null, n integer not null, verb text not null, outcome text not null,
  progress integer not null, regressed integer not null default 0, same_failure integer not null default 0,
  passed integer, total integer, failing text not null default '[]', note text not null default '',
  primary key (todo, n));
create table if not exists tablua_run (
  todo text primary key, shipped integer, answered integer, works integer, right integer,
  changed integer, steps integer, cost real, at text);
create table if not exists tablua_fit (
  head text not null, schema text not null, id text not null, rows integer not null, at text,
  primary key (head, schema));
create table if not exists tablua_prediction (
  todo text not null, n integer not null, head text not null, move text not null, p real not null,
  primary key (todo, n, head, move));
create table if not exists tablua_feature (
  todo text not null, n integer not null, name text not null, value real, form text not null default '',
  primary key (todo, n, name));
create table if not exists tablua_section (
  file text not null, n integer not null, kind text not null, lang text not null default '',
  body text not null default '', primary key (file, n));
update tablua_section set kind = 'code', lang = case lang when '' then 'lua' else lang end where kind = 'lua';
create table if not exists tablua_unit (
  file text not null, section integer not null, n integer not null, kind text not null,
  name text not null default '', source text not null, primary key (file, section, n));
drop table if exists tablua_scenario;
drop table if exists tablua_line;
create table if not exists tablua_test (
  file text not null, n integer not null, kind text not null default 'test', name text not null, text text not null,
  primary key (file, n));
create table if not exists tablua_keyword (
  file text not null, n integer not null, name text not null, text text not null, primary key (file, n));
create table if not exists tablua_call (
  file text not null, item integer not null, path text not null, keyword text not null,
  args text not null default '', primary key (file, item, path));
create table if not exists tablua_result (
  todo text not null, n integer not null, run integer not null, file text not null default '', test text not null,
  path text not null, parent text not null default '', depth integer not null default 0, type text not null,
  keyword text not null default '', args text not null default '', status text not null,
  message text not null default '', ms real, line integer,
  primary key (todo, n, run, file, test, path));
drop view if exists tablua_task_record;
create view if not exists tablua_task_record as select r.test as name, count(*) as runs,
  sum(r.status = 'PASS') as passed,
  (select f.keyword from tablua_result f join tablua_result o on o.todo = f.todo and o.n = f.n and o.run = f.run
      and o.file = f.file and o.test = f.test and o.path = '' and o.type = 'task'
    where f.test = r.test and f.type = 'keyword' and f.status = 'FAIL'
    group by f.keyword order by count(*) desc, max(f.depth) desc, f.keyword limit 1) as fails_at
  from tablua_result r where r.type = 'task' and r.path = '' group by r.test;
create table if not exists tablua_label (
  todo text not null, n integer not null, head text not null, value real not null, source text not null,
  at text, primary key (todo, n, head, source));
create table if not exists tablua_effect (
  todo text not null, n integer not null, keyword text not null, arg text not null default '',
  primary key (todo, n, keyword, arg));
create table if not exists tablua_link (
  file text not null, kind text not null, source text not null, target text not null,
  found integer not null default 0, primary key (file, kind, source, target));
drop view if exists tablua_break;
create view if not exists tablua_break as select file, kind, source, target from tablua_link l where
  (kind = 'post' and not exists (select 1 from tablua_unit u where u.kind = 'action' and u.name = l.target)
    and not exists (select 1 from tablua_link d where d.kind = 'defines' and d.target = l.target))
  or (kind = 'reads' and not exists (select 1 from tablua_link w where w.kind = 'sends' and w.target = l.target))
  or (kind in ('call', 'press', 'field', 'see') and found = 0)
  or (kind = 'calls' and exists (select 1 from tablua_link m where m.kind = 'module'
      and m.target = substr(l.target, 1, instr(l.target, '.') - 1))
    and not exists (select 1 from tablua_link e where e.kind = 'exports' and e.target = l.target))
union all select file, 'orphan', name, name from tablua_unit u where kind = 'action'
  and not exists (select 1 from tablua_link p where p.kind = 'post' and p.target = u.name)
union all select file, 'orphan', target, target from tablua_link d where kind = 'defines'
  and not exists (select 1 from tablua_link p where p.kind = 'post' and p.target = d.target);
create table if not exists tablua_control (
  todo text not null, n integer not null, i integer not null, id text not null, app text not null default '',
  verb text not null default '', role text not null default '', label text not null default '', ord integer,
  chosen integer not null default 0, primary key (todo, n, i));
create table if not exists tablua_ranking (
  todo text not null, head text not null, key text not null, n integer, ps text not null,
  primary key (todo, head, key));
create table if not exists tablua_change (
  todo text not null, n integer not null, i integer not null, op text not null, kind text not null default '',
  name text not null default '', lines integer not null default 0, named_by integer not null default 0,
  breaks integer not null default 0, primary key (todo, n, i));
create table if not exists tablua_shape (
  file text not null, section integer not null, n integer not null, lines integer not null default 0,
  arity integer not null default 0, depth integer not null default 0, names integer not null default 0,
  primary key (file, section, n));
create table if not exists tablua_element (
  file text not null, n integer not null, path text not null, call text not null, parent text not null default '',
  depth integer not null default 1, children integer not null default 0, props text not null default '',
  text text not null default '', primary key (file, n));
create table if not exists tablua_term (
  todo text not null, n integer not null, i integer not null, source text not null default 'real',
  keys text not null default '', wait real, exit integer, done integer not null default 1, failed integer, ms real,
  lines integer not null default 0, screen text not null default '',
  program text not null default '', programs text not null default '', reads integer not null default 0,
  writes integer not null default 0, files integer not null default 0, first_ms real, bytes integer, red integer,
  yellow integer, green integer, redraws integer, alt_screen integer, passed integer, total integer, trace text,
  ran text, primary key (todo, n, i, source));
create table if not exists tablua_vector (
  todo text not null, n integer not null, i integer not null, source text not null default 'world',
  model text not null default '', dims integer not null, v text not null, primary key (todo, n, i, source));
create table if not exists tablua_file (
  todo text not null, n integer not null, i integer not null, path text not null, size integer,
  primary key (todo, n, i, path));
create table if not exists tablua_event (
  todo text not null, n integer not null, i integer not null, source text not null default 'real', k integer not null,
  kind text not null, name text not null default '', file text not null default '', line integer,
  sig text not null, count integer not null default 1, text text not null default '',
  primary key (todo, n, i, source, k));
drop view if exists tablua_surprise;
create view if not exists tablua_surprise as select r.todo, r.n, r.i,
  (select count(*) from tablua_event e where e.todo = r.todo and e.n = r.n and e.i = r.i and e.source = 'real'
    and not exists (select 1 from tablua_event x where x.todo = e.todo and x.n = e.n and x.i = e.i
      and x.source = 'world' and x.kind = e.kind)) as unforeseen,
  (select count(*) from tablua_event e where e.todo = r.todo and e.n = r.n and e.i = r.i and e.source = 'world'
    and not exists (select 1 from tablua_event x where x.todo = e.todo and x.n = e.n and x.i = e.i
      and x.source = 'real' and x.kind = e.kind)) as unfulfilled,
  (r.failed is not null and r.failed != w.failed) as failed_differs
  from tablua_term r join tablua_term w on w.todo = r.todo and w.n = r.n and w.i = r.i and w.source = 'world'
  where r.source = 'real';
create table if not exists tablua_msr_comp (
  todo text not null, n integer not null, key text not null, value, type text not null default 's',
  primary key (todo, n, key));
create table if not exists tablua_msr_node (
  todo text not null, n integer not null, id text not null, kind text not null, parent text, ord real,
  primary key (todo, n, id));
create table if not exists tablua_msr_prop (
  todo text not null, n integer not null, id text not null, name text not null, value,
  type text not null default 's', primary key (todo, n, id, name));
create table if not exists tablua_msr_key (
  todo text not null, n integer not null, id text not null, name text not null, t not null, value,
  type text not null default 's', ease text, primary key (todo, n, id, name, t));
create table if not exists tablua_msr_motion (
  todo text not null, n integer not null, id text not null, name text not null, t0 real not null, t1 real,
  curve text not null, params text not null default '{}', primary key (todo, n, id, name, t0));
create table if not exists tablua_msr_system (
  todo text not null, n integer not null, name text not null, ord real, source text not null default '',
  primary key (todo, n, name));
create table if not exists tablua_msr_asset (
  todo text not null, n integer not null, id text not null, src text not null default '', derive text not null default '',
  solid text, primary key (todo, n, id));
create table if not exists tablua_msr_expect (
  todo text not null, n integer not null, id text not null, says text not null default '', node text, prop text,
  op text, value, type text not null default 's', at, t0, t1, holds text, primary key (todo, n, id));
create table if not exists tablua_message (
  todo text not null, i integer not null, n integer, role text not null, name text, content text not null default '',
  tool_calls text, tool_call_id text, is_error integer, image integer, reasoning text, usage text, provider text,
  model text, primary key (todo, i));
create table if not exists tablua_prompt (
  todo text not null, n integer not null, i integer not null, role text not null, parts text not null default '{}',
  bytes integer, text text not null default '', reply text not null default '', seconds real, tries integer,
  provider text, primary key (todo, n, i));
create table if not exists tablua_msr_solid (
  todo text not null, n integer not null, id text not null, parts integer, genus integer, watertight integer,
  empty integer, volume real, area real, triangles integer, size text, primary key (todo, n, id));
create table if not exists tablua_msr_fact (
  todo text not null, n integer not null, pred text not null, args text not null, t0 real not null, t1 real,
  src text not null default '', conf real, derived integer not null default 0, asset text,
  primary key (todo, n, pred, args, t0));
create table if not exists tablua_withdrawal (
  todo text not null, n integer not null, id text not null, says text not null default '', why text not null default '',
  primary key (todo, n, id));
create table if not exists tablua_msr_finding (
  todo text not null, n integer not null, tier text not null, id text not null default '', name text not null default '',
  code text not null, severity text not null, t0 real not null default -1, t1 real, measured, threshold,
  detail text not null default '', primary key (todo, n, tier, id, name, code, t0, detail));
create table if not exists tablua_score (
  todo text not null, n integer not null, judge text not null, dim text not null, value real,
  primary key (todo, n, judge, dim));
create table if not exists tablua_gate (
  name text primary key, predicate text not null, version integer not null default 1,
  retired_by text);
]]

-- the log's tables, each keyed by the todo (schema 14 renamed its column from task)
M.log = { "state", "candidate", "decision", "action", "outcome", "run", "prediction", "feature", "result", "label",
  "effect", "control", "ranking", "change", "term", "event", "file", "vector", "msr_comp", "msr_node", "msr_prop",
  "msr_key", "msr_motion", "msr_system", "msr_asset", "msr_fact", "msr_finding", "score",
  "msr_solid", "msr_expect", "prompt", "message", "withdrawal" }

local function columns(db, tbl)
  local out = {}
  for _, c in ipairs(db:exec("pragma table_info(" .. tbl .. ")")) do out[c.name] = true end
  return out
end

-- what a file kept before this schema needs that create table if not exists does not give it; run before the ddl,
-- on whichever tables the file already has
function M.migrate(db)
  db:exec("drop view if exists tablua_task_record")
  db:exec("drop view if exists tablua_surprise")
  for _, name in ipairs(M.log) do
    local cols = columns(db, "tablua_" .. name)
    if cols.task and not cols.todo then db:exec("alter table tablua_" .. name .. " rename column task to todo") end
  end
  local term = columns(db, "tablua_term")
  if next(term) then
    for _, c in ipairs(M.term_columns) do
      if not term[c[1]] then db:exec("alter table tablua_term add column " .. c[1] .. " " .. c[2]) end
    end
  end
  for tbl, cs in pairs(M.added) do
    local have = columns(db, tbl)
    if next(have) then
      for _, c in ipairs(cs) do
        if not have[c[1]] then db:exec("alter table " .. tbl .. " add column " .. c[1] .. " " .. c[2]) end
      end
    end
  end
  local finding = db:exec("pragma table_info(tablua_msr_finding)")
  local keyed = false
  for _, c in ipairs(finding) do if c.name == "detail" and c.pk > 0 then keyed = true end end
  if #finding > 0 and not keyed then
    -- the ddl that follows makes the table with its new key; M.after puts the old rows back into it
    db:exec("alter table tablua_msr_finding rename to tablua_msr_finding_23")
  end
  local test = columns(db, "tablua_test")
  if next(test) and not test.kind then db:exec("alter table tablua_test add column kind text not null default 'test'") end
end

-- what migrate set aside, put back once the ddl has made the new tables
function M.after(db)
  if #db:exec("select 1 from sqlite_master where type = 'table' and name = 'tablua_msr_finding_23'") > 0 then
    db:exec("insert or ignore into tablua_msr_finding select todo, n, tier, id, name, code, severity, t0, t1, measured, "
      .. "threshold, detail from tablua_msr_finding_23")
    db:exec("drop table tablua_msr_finding_23")
  end
end

return M
