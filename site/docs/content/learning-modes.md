---
description: Set up TabPFN for a Tablua agent and move it from evidence, to shadow, to rank mode - measuring before it decides anything.
---

# Turn learning on

This guide sets up TabPFN for an agent and moves it through the three ways its estimates can be used: as evidence, in shadow, and deciding. The order matters: measure first, then act on what you measured.

## 1. Get a key

TabPFN runs as an API from Prior Labs. Create an account at [priorlabs.ai](https://priorlabs.ai), make an API key, and give it to the agent:

```sh
export PRIORLABS_API_KEY=...
```

On Moss, that is all. When you embed the harness, pass the key to `ports.tabpfn` yourself (see [Embed the harness in Lua](/guides/embed)).

> [!NOTE]
> The free tier allows 5 million tokens a day per account. Tablua stays under 4 million, prices every prediction before making it, and carries on without TabPFN when the day's budget is spent.

## 2. Evidence mode: the default

With a key set and nothing else, the agent is in evidence mode. After two failed steps in a row, TabPFN ranks the moves and Jev sees the ranking, with TabPFN's track record, as evidence on its card. Every option stays open.

TabPFN needs at least 12 labelled steps (and 3 of each label) before it is asked. Until then the card says there are no past outcomes to learn from yet. [Shared experience](/concepts/shared-experience) gives new agents rows from the start.

## 3. Shadow mode: measure

In shadow mode, TabPFN ranks the moves at every decision in the `building` stage, and its estimate is written to each candidate as `p_progress`. Jev never sees it. Nothing about the agent's behaviour changes; you only gain a measurement.

```elixir
Moss.Computer.Agent.run("plants", ask, learn: "shadow")
```

After enough runs, compare TabPFN's estimates with what happened:

```sql
select round(c.p_progress, 1) as tabpfn_said, count(*) as steps, round(avg(o.progress), 2) as helped
from tablua_candidate c
join tablua_decision d on d.task = c.task and d.n = c.n and d.chosen = c.move
join tablua_outcome o on o.task = c.task and o.n = c.n
where c.p_progress is not null
group by 1 order by 1;
```

Run the same query with `c.jev_p` in place of `c.p_progress` to put Jev's confidence beside it. Whichever predicts `helped` better, on tasks it hasn't seen, deserves more weight.

## 4. Rank mode: let it decide

In rank mode, TabPFN ranks the moves at every `building` decision, as in shadow mode. When its best move leads Jev's pick by a clear margin, and Jev gave its own pick less than a set confidence, TabPFN's move is taken. The decision row records `by=tabpfn`.

```elixir
Moss.Computer.Agent.run("plants", ask, learn: "rank")
```

Rank mode only overrides Jev where Jev is unsure and TabPFN is clearly ahead. Everywhere else, Jev decides as before.

## 5. Check it is working

```sql
select d.by, count(*) as steps, round(avg(o.progress), 2) as helped
from tablua_decision d join tablua_outcome o using (task, n)
group by d.by;
```

And compare whole runs with and without rank mode: did as many ship and work, in fewer steps? A single run says little. Compare several runs per task, and tasks the agent hasn't seen before.

## Next

- [How Tablua learns](/concepts/learning): what TabPFN reads and predicts
- [Retire a gate with an A/B](/guides/gate-ab): the same kind of comparison, for rules
