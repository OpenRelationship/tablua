---
description: Useful SQL queries for reading a Tablua agent's file - a run step by step, which moves help where, who decided, how sure Jev was, and what is broken.
---

# Read an agent's file with SQL

An agent's whole history is in one SQLite file, so the plainest way to understand what it did is to ask the file. This guide collects queries that answer common questions. They work in `sqlite3`, DB Browser for SQLite, Datasette, or any SQLite client.

Open a file with:

```sh
sqlite3 agent.sqlite
```

Then, for readable output:

```sql
.mode box
```

## A run, step by step

```sql
select s.n, s.stage, s.passed || '/' || s.total as passing, d.chosen, d.by, o.outcome, o.progress
from tablua_state s
join tablua_decision d using (task, n)
join tablua_outcome o using (task, n)
where s.task = 'plants'
order by s.n;
```

Replace `'plants'` with a task from `select distinct task from tablua_state;`.

## How each run ended

```sql
select task, shipped, works, steps, round(cost, 4) as cost_usd from tablua_run order by at;
```

## Which moves help, in which stage

```sql
select s.stage, d.chosen as move, count(*) as times,
       round(avg(o.progress), 2) as helped
from tablua_state s
join tablua_decision d using (task, n)
join tablua_outcome o using (task, n)
group by s.stage, d.chosen
having count(*) >= 5
order by s.stage, helped desc;
```

This is the simplest version of what TabPFN learns, and often worth a look by itself.

## Who decided

```sql
select d.by, count(*) as steps, round(avg(o.progress), 2) as helped
from tablua_decision d join tablua_outcome o using (task, n)
group by d.by;
```

In rank mode, compare steps decided by `jev` with steps decided by `tabpfn`.

## Where Jev and TabPFN disagreed

```sql
select c.task, c.n, d.chosen, c.move, round(c.jev_p, 2) as jev, round(c.p_progress, 2) as tabpfn
from tablua_candidate c
join tablua_decision d using (task, n)
where c.p_progress is not null and c.jev_p is not null
  and abs(c.jev_p - c.p_progress) > 0.4
order by c.task, c.n;
```

## How sure Jev was, and how often it was right

```sql
select round(c.jev_p, 1) as jev_said, count(*) as steps,
       round(avg(o.outcome = 'complete'), 2) as worked
from tablua_decision d
join tablua_candidate c on c.task = d.task and c.n = d.n and c.move = d.chosen
join tablua_outcome o on o.task = d.task and o.n = d.n
where c.jev_p is not null and o.outcome <> 'denied'
group by 1 order by 1;
```

If Jev were perfectly calibrated, `worked` would match `jev_said` in every row.

## What each step changed

```sql
select n, group_concat(keyword || case when arg <> '' then ' ' || arg else '' end, ', ') as effects
from tablua_effect where task = 'plants' group by n order by n;
```

## What is broken in the program

```sql
select file, kind, source, target from tablua_break;
```

Each row is a link with nothing at its end: a button posting to an action nobody wrote, a test's call no keyword answers, an action no page reaches.

## Which rules a run ran under

```sql
select name, retired_by from tablua_gate;
```

A gate with `retired_by` set was switched off for that run.

## Writing your own

Most questions join on `(task, n)`: a task and its step number identify one step in every table. [Tables](/reference/tables) lists every column.

> [!NOTE]
> Treat an agent's file as read-only while the agent is running. Reading is safe; writing to Tablua's tables changes what the agent learns from.
