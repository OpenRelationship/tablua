---
description: Test whether one of the agent's rules still earns its place, by running with it switched off and comparing outcomes.
---

# Retire a gate with an A/B

A gate is a rule that holds a move back in some situation. This guide shows how to test whether a gate still earns its place: run the same tasks with it on and with it off, and compare.

## 1. Pick a gate

Start with a gate whose stated reason doesn't hold in the record (see [Policy as data](/concepts/policy-as-data)). A host keeps its gates and their reasons as Robot tests beside its moves; each test's `gate:` tag gives the name to switch off.

To see which gates the record says least about, count how often each gate's situation came up. Gates that are rarely tested, or that hide their own evidence, are also good candidates, because switching them off is the only way to learn what they do.

Fixed gates, which describe what a move can do at all (like `undo` needing a change to undo), can't be switched off.

## 2. Run both arms

Run the same tasks twice: once as usual (arm A) and once with the gate off (arm B). Use a fresh computer for each run so neither arm learns from the other.

```lua
for _, task in ipairs(tasks) do
  for seed = 1, 3 do
    run(task, { computer = "a-" .. task.id .. "-" .. seed })                         -- arm A: as usual
    run(task, { computer = "b-" .. task.id .. "-" .. seed, gates_off = { stuck_fix = true } })   -- arm B
  end
end
```

`run` is your host's: it drives the loop as [Run an agent in your host](/guides/run-agent) shows, on a fresh computer, with your world leaving the switched-off gate's move open.

Several tasks, several runs each. Agents vary from run to run, so one pair of runs tells you very little.

Record the gates each run ran under with `t:gate{ name, predicate, retired_by? }`. In arm B, give the switched-off gate's row `retired_by`.

## 3. Compare

Each run's rows are in its own file. Attach the files of one arm to a single SQLite session, or copy their `tablua_run` and `tablua_effect` rows into one file, to compare the arms side by side.

For each arm, look at the runs' endings:

```sql
select count(*) as runs,
       avg(shipped) as shipped, avg(works) as works, avg(steps) as steps
from tablua_run;
```

and at the effect the gate's reason names. If the reason was "`fix_failure` after 2 stalls leads to Same Keyword Failing", count that effect in each arm:

```sql
select count(*) from tablua_effect where keyword = 'Same Keyword Failing';
```

## 4. Decide

- **Arm B no worse**: same share shipped and working, no more steps. The gate isn't pulling its weight. Retire it.
- **Arm B worse**: keep the gate, and update its reason if the measurement showed a different cause.
- **Too close to call**: run more tasks before deciding.

Retire gates one at a time. Switching off several at once makes it impossible to tell which one mattered.
