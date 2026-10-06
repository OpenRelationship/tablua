---
description: Test a belief before building on it — claim, red proof, prediction, commit, measure (.robot/)
argument-hint: what you believe, e.g. "the decider reads the state"
---

Turn this into a claim and measure it, the way `.robot/README.md` says: $ARGUMENTS

1. **Write the claim** in the fitting `.robot/claims/*.robot` (or a new file):
   - `[Documentation]` says what is believed and names the **oracle**, the independent thing that checks it. If the
     only check is our own code against our own rule, say so and tag it `level:consistent`.
   - Its assertion carries the **kill number**, a `Should` keyword with a threshold set now.
   - Its measure has a floor (`min=`, `Needs At Least`), so thin data makes it unknown, not held or killed.
   - Tag `level:` (consistent, correct, informative or useful) and `predict:<verdict>@<p>`, an honest probability.
     Predicting only sure things scores nothing; log loss punishes confident misses.
2. **Write its red proof**, `<name> (red)`: the same check on fixture rows known to be wrong. Run
   `luajit .robot/run.lua reds <file>` and fix every BAD before going on.
3. **Commit** the claims file. A run counts only when the file is committed unchanged.
4. **Measure:** build or fetch the rows (`run.lua refresh <label>` after a bench run), then `luajit .robot/run.lua`.
   Commit the ledger.
5. **Report** the verdict, the level and the number behind it, against the kill line. Say which predictions missed.

Before trusting what the claim reads:

- **A replay or rebuilt sheet is checked first.** Its first claim reproduces what was logged (fidelity). If that
  dies, nothing else read from it counts, so mark the run `invalid` with the reason. A model's cache once kept the
  first label order a process saw and made a reorder test blind.
- **A pass that looks too good is a bug until shown otherwise.** Four claims "held" because `Should Be True` could
  not fail. Check the checker.
- **"First" and "never" are queries.** "The first pass on overfull-hbox" was wrong: ten earlier runs had passed.
- **New tests must fail once.** Add their rules to `.robot/mutations/` and run `luajit .robot/mutate.lua`. CRASHED is
  not red: a broken edit, or output piped away from the runner, shows nothing.
- **Changing what a killed claim reads is an edit after a kill.** Do it in the open; the ledger flags it.

Don't write a claim for a refactor or for behaviour a `_test.lua` already pins. A claim tests a belief about what
the code does in the world.
