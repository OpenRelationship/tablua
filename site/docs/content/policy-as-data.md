---
description: How Tablua writes the rules that steer its agent as named gates with stated reasons, measures each reason against the record, and retires rules one A/B at a time.
---

# Policy as data

Every agent has rules: don't publish before the tests pass, don't try the same fix five times. In most agents they live inside a prompt, mixed with everything else. In Tablua each rule is a named **gate** with a stated reason, recorded as a row, and each can be measured and switched off on its own.

## What a gate is

A gate holds one move back in one situation. For example:

- **stuck_fix**: fixing the same failure again waits until the agent has thought it through.
- **publish_looked**: publishing waits until the app has been used since it last changed.
- **think_twice**: thinking twice in a row changes nothing, so it isn't offered.
- **dead_end**: past a dead end, neither fixing nor thinking is offered.

Some gates aren't policy at all but facts about what a move can do: `undo` only exists after a change broke something. Those are marked *fixed* and are never switched off.

When a run starts, the gates in force are written as `tablua_gate` rows, so every run records which rules it ran under.

## Each gate states its reason

Gates are also written as test scenarios in `priv/gates.org`, in plain language, with a machine-readable reason:

```gherkin
Scenario: fixing the same failure again waits on thinking it through
  # gate: stuck_fix
  Given Same Failure after 2 changes running
  When the last move was not think
  Then fix_failure is not offered
  # because: fix_failure | 2+ stalls | Same Line Failing | more
```

The `because` line says what the gate assumes: *taking `fix_failure` after two or more stalls leads to `Same Line Failing` more often than usual.* That is a claim about the record, so it can be checked against the record.

## Measuring a reason

Tablua checks each reason against every recorded step: in the stated situation, after the stated move, how often did the stated effect follow, compared with steps in general?

A first measurement over eight gates found:

- **Holds**: undo after a regression.
- **Does not hold**: thinking before fixing again after two stalls. The effect it guards against followed 44% of the time, against a 38% base rate. That is not far enough apart to justify the rule.
- **Too few steps to tell**: several gates, because a gate in force hides its own evidence. If a move is never allowed in a situation, the record can't show what it would have done.
- **Not measurable yet**: gates whose reason no recorded effect speaks to.

## Retiring a gate

A gate whose reason doesn't hold is the first candidate to go. But a reason not holding isn't proof the gate does no good, so every gate is retired the same way: through an A/B. Some runs go with the gate switched off, some with it on, and the outcomes are compared. If the runs without it do no worse, it goes.

That is also the only way to learn about the gates that hide their own evidence: switch them off for some runs and let the record fill in.

[Retire a gate with an A/B](/guides/gate-ab) shows how.

## Why this matters

Rules written into a prompt tend to pile up. Each fixes something once, and nobody can tell later which ones still pull their weight. Gates as data keep the rule set small and accountable: each has a name, a reason, a measurement and a way out. Over time, behaviour that was hand-written can move to what the agent learned from its record.

## Next

The app the agent builds is rows too. See [The program as rows](/concepts/program-as-rows).
