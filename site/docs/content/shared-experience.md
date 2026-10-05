---
description: How agents on one node learn from each other's finished runs through a shared file of Tablua rows.
---

# Shared experience

A new agent has no record of its own, so it has nothing to learn from. Shared experience fixes that: when an agent finishes a run, its rows join a file that every other agent on the same machine reads beside its own.

{{diagram:share}}

## How it works

1. **An agent works as usual**, writing its rows into its own file.
2. **When the run ends**, its Tablua rows are copied into the node's shared experience file. Each todo is renamed `<computer>|<todo>`, so one agent's todos can never be mistaken for another's.
3. **Every agent attaches the shared file** when it starts a run. When TabPFN is fitted, it reads the shared rows first, then the agent's own.

The copy happens only at the end of a run. An agent never reads its own run back from the shared file, so nothing is counted twice, and no agent learns from a run that hasn't finished.

## Why rows make this easy

Sharing works because every agent's rows have the same columns. A step taken by one agent building a plants app and a step taken by another building a chores app line up exactly: same stages, same moves, same labels. There is nothing to translate, summarise or embed. The shared file is just more rows.

This is also why the agent's vocabulary is kept small and fixed. A few dozen moves and stages, the same on every computer, make one agent's experience useful to the next.

## Turning it on

Shared experience is a file path. Attach any file of Tablua rows to an agent's file before it learns; without one, each agent learns from its own rows alone:

```lua
t:attach("shared", "/var/lib/tablua/experience.sqlite")
local train, labels = t:training("progress", { before = true })   -- shared rows first, then this file's
```

## Measuring whether it helps

Sharing should help, but that is a claim to measure, not assume. Tablua's evaluation compares two ways of running the same ordered list of todos:

- **stream**: each run reads the shared experience left by the runs before it;
- **reset**: each run learns from its own steps alone.

The difference in outcomes between the two is the *gain* from experience, reported with a confidence interval over several seeds and rephrasings of each todo. Todos are run as dependent streams (variations of one kind of app) and independent ones, to check both that experience helps where it should and that it does no harm where it shouldn't.

## Next

The rules that hold moves back are rows too. See [Policy as data](/concepts/policy-as-data).
