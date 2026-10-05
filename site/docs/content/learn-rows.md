---
description: Module 2. Why Tablua records each step as rows in tables instead of a transcript, and the five tables that describe one step.
---

# 2. Writing it down as rows

## The idea

Instead of a transcript, Tablua records each step as **rows in tables**, the way a spreadsheet or a database would. Each part of the loop from Module 1 gets its own table:

{{diagram:loop}}

All of these tables live in **one SQLite file per agent**. SQLite is a small database that is just a file: you can copy it, open it with many tools, and query it with SQL. An agent *is* its file. Move the file and you have moved the agent.

## One step, as rows

Here is step 3 from the plants example, written the way Tablua writes it. Every value is a column with a name and a type:

```text
tablua_state      task=plants n=3  stage=building  passed=1 total=3  stalls=0  cause=the_page
tablua_candidate  task=plants n=3  move=fix_failure   jev_p=0.71
tablua_candidate  task=plants n=3  move=write_page    jev_p=0.18
tablua_candidate  task=plants n=3  move=think         jev_p=0.11
tablua_decision   task=plants n=3  chosen=fix_failure  by=jev
tablua_action     task=plants n=3  i=1  op=write_file  target=ui/index.org  exit=0
tablua_outcome    task=plants n=3  outcome=complete  passed=3 total=3  progress=1
```

Read it top to bottom and it tells the story of the step:

- **state**: where the work stood. Building, 1 of 3 tests passing, and the failure seemed to be in the page.
- **candidate**: every move the agent could have made, one row each, with the model's probability for it.
- **decision**: the move it took, and who chose it.
- **action**: each thing the move actually did (here, it wrote one file).
- **outcome**: how it turned out. All 3 tests now pass, so this step made progress.

Two more tables close the picture: `tablua_run` holds one row per whole task (did it ship, how many steps, what it cost), and the `task` and `n` columns join everything together.

## Why rows beat a transcript

**You can ask questions.** Want to know what the agent does when it is stuck, and whether it works? That's one query:

```sql
select d.chosen, avg(o.progress)
from tablua_state s
join tablua_decision d using (task, n)
join tablua_outcome  o using (task, n)
where s.stalls >= 2
group by d.chosen;
```

**A model can learn from them.** Rows with columns are exactly what tabular machine learning models eat. Module 7 shows how Tablua uses this.

**Nothing is parsed from text.** The harness writes each column directly, at the moment it knows the value. No later step has to guess what the agent meant from a log line.

**It stays small.** A step is a handful of rows, not pages of chat.

## Who writes the rows

This matters: **the host writes the facts, not the model.** The state (which tests pass, what stage it is) and the outcome (did tests improve) come from programs that check the real files. The model's opinions are recorded too, but in their own columns (like `jev_p`), never mixed with the facts.

## Remember

- Each step is a few rows: state, candidates, decision, actions, outcome.
- All rows live in one SQLite file per agent, and that file is the agent.
- Facts come from checks the host runs; model opinions have their own columns.
- Because it's tables, you can query the agent's past and learn from it.

## Next

The state row said "1 of 3 tests passing". Where do those tests come from? [Module 3: Robot](/learn/robot)
