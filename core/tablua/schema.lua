-- Three parts, told apart by their key (site/docs/content/log-and-build.md): the log, what the agent did, keyed by
-- (task, n) and only ever added to (state, candidate, decision, action, change, outcome, effect, feature, label,
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
local M = {}

M.version = 13

M.ddl = [[
create table if not exists tablua_meta (key text primary key, value text);
create table if not exists tablua_state (
  task text not null, n integer not null,
  stage text not null default '', passed integer, total integer, pass real,
  stalls integer not null default 0, last_verb text not null default '', last_outcome text not null default '',
  cause text not null default '', pages_ok integer, own_checks integer not null default 0,
  ask text not null default '', versions text not null default '{}', at text,
  primary key (task, n));
create table if not exists tablua_candidate (
  task text not null, n integer not null, move text not null,
  jev_p real, jev_conf real, jev_margin real, jev_form text not null default 'choice',
  p_progress real, p_ship real, cost_q50 real, cost_q90 real, explored integer not null default 0,
  primary key (task, n, move));
create table if not exists tablua_decision (
  task text not null, n integer not null, chosen text not null, by text not null,
  propensity real, policy text not null default '', at text,
  primary key (task, n));
create table if not exists tablua_action (
  task text not null, n integer not null, i integer not null,
  cmd text not null default '', file_kind text not null default '', op text not null default '',
  target text not null default '', bytes integer, exit integer, duration_ms real,
  primary key (task, n, i));
create table if not exists tablua_outcome (
  task text not null, n integer not null, verb text not null, outcome text not null,
  progress integer not null, regressed integer not null default 0, same_failure integer not null default 0,
  passed integer, total integer, failing text not null default '[]', note text not null default '',
  primary key (task, n));
create table if not exists tablua_run (
  task text primary key, shipped integer, answered integer, works integer, right integer,
  changed integer, steps integer, cost real, at text);
create table if not exists tablua_fit (
  head text not null, schema text not null, id text not null, rows integer not null, at text,
  primary key (head, schema));
create table if not exists tablua_prediction (
  task text not null, n integer not null, head text not null, move text not null, p real not null,
  primary key (task, n, head, move));
create table if not exists tablua_feature (
  task text not null, n integer not null, name text not null, value real, form text not null default '',
  primary key (task, n, name));
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
  task text not null, n integer not null, run integer not null, file text not null default '', test text not null,
  path text not null, parent text not null default '', depth integer not null default 0, type text not null,
  keyword text not null default '', args text not null default '', status text not null,
  message text not null default '', ms real, line integer,
  primary key (task, n, run, file, test, path));
drop view if exists tablua_task_record;
create view if not exists tablua_task_record as select r.test as name, count(*) as runs,
  sum(r.status = 'PASS') as passed,
  (select f.keyword from tablua_result f join tablua_result o on o.task = f.task and o.n = f.n and o.run = f.run
      and o.file = f.file and o.test = f.test and o.path = '' and o.type = 'task'
    where f.test = r.test and f.type = 'keyword' and f.status = 'FAIL'
    group by f.keyword order by count(*) desc, max(f.depth) desc, f.keyword limit 1) as fails_at
  from tablua_result r where r.type = 'task' and r.path = '' group by r.test;
create table if not exists tablua_label (
  task text not null, n integer not null, head text not null, value real not null, source text not null,
  at text, primary key (task, n, head, source));
create table if not exists tablua_effect (
  task text not null, n integer not null, keyword text not null, arg text not null default '',
  primary key (task, n, keyword, arg));
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
  task text not null, n integer not null, i integer not null, id text not null, app text not null default '',
  verb text not null default '', role text not null default '', label text not null default '', ord integer,
  chosen integer not null default 0, primary key (task, n, i));
create table if not exists tablua_ranking (
  task text not null, head text not null, key text not null, n integer, ps text not null,
  primary key (task, head, key));
create table if not exists tablua_change (
  task text not null, n integer not null, i integer not null, op text not null, kind text not null default '',
  name text not null default '', lines integer not null default 0, named_by integer not null default 0,
  breaks integer not null default 0, primary key (task, n, i));
create table if not exists tablua_shape (
  file text not null, section integer not null, n integer not null, lines integer not null default 0,
  arity integer not null default 0, depth integer not null default 0, names integer not null default 0,
  primary key (file, section, n));
create table if not exists tablua_element (
  file text not null, n integer not null, path text not null, call text not null, parent text not null default '',
  depth integer not null default 1, children integer not null default 0, props text not null default '',
  text text not null default '', primary key (file, n));
create table if not exists tablua_gate (
  name text primary key, predicate text not null, version integer not null default 1,
  retired_by text);
]]

-- what a file kept before this schema needs that create table if not exists does not give it
function M.migrate(db)
  local has = false
  for _, c in ipairs(db:exec("pragma table_info(tablua_test)")) do if c.name == "kind" then has = true end end
  if not has then db:exec("alter table tablua_test add column kind text not null default 'test'") end
end

return M
