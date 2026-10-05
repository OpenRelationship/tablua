---
description: Test whether one of the agent's rules still earns its place, by running with it switched off and comparing outcomes.
---

# Retire a gate with an A/B

A gate is a rule that holds a move back in some situation. This guide shows how to test whether a gate still earns its place: run the same tasks with it on and with it off, and compare.

## 1. Pick a gate

Start with a gate whose stated reason doesn't hold in the record (see [Policy as data](/concepts/policy-as-data)). The gates and their reasons are in `priv/gates.org`; each scenario's `# gate:` line gives the name to switch off.

To see which gates the record says least about, count how often each gate's situation came up. Gates that are rarely tested, or that hide their own evidence, are also good candidates, because switching them off is the only way to learn what they do.

Fixed gates, which describe what a move can do at all (like `undo` needing a change to undo), can't be switched off.

## 2. Run both arms

Run the same tasks twice: once as usual (arm A) and once with the gate off (arm B). Use a fresh computer for each run so neither arm learns from the other.

```elixir
for {task, ask} <- tasks, seed <- 1..3 do
  Moss.Computer.Agent.run("a-#{task}-#{seed}", ask, between: &person/1)
  Moss.Computer.Agent.run("b-#{task}-#{seed}", ask, between: &person/1, gates_off: "stuck_fix")
end
```

Several tasks, several runs each. Agents vary from run to run, so one pair of runs tells you very little.

Each run records the gates it ran under as `tablua_gate` rows. In arm B, the switched-off gate's row has `retired_by` set.

## 3. Compare

Each run's rows are in its own computer's file (`priv/work/computers/<id>.sqlite` locally). Attach the files of one arm to a single SQLite session, or copy their `tablua_run` and `tablua_effect` rows into one file, to compare the arms side by side.

For each arm, look at the runs' endings:

```sql
select count(*) as runs,
       avg(shipped) as shipped, avg(works) as works, avg(steps) as steps
from tablua_run;
```

and at the effect the gate's reason names. If the reason was "`fix_failure` after 2 stalls leads to Same Line Failing", count that effect in each arm:

```sql
select count(*) from tablua_effect where keyword = 'Same Line Failing';
```

## 4. Decide

- **Arm B no worse**: same share shipped and working, no more steps. The gate isn't pulling its weight. Retire it.
- **Arm B worse**: keep the gate, and update its reason if the measurement showed a different cause.
- **Too close to call**: run more tasks before deciding.

Retire gates one at a time. Switching off several at once makes it impossible to tell which one mattered.
