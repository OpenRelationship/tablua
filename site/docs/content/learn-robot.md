---
description: Module 3. How the agent turns a person's ask into Gherkin scenarios before writing any code, and how those scenarios become the tests and the stages of the work.
---

# 3. Gherkin: saying what "done" means

## The problem

"A little app for my house plants" is vague. Before an agent writes a line of code, someone has to decide what "done" looks like. If nobody does, the agent can't check its own work, and the person can't tell whether they got what they asked for.

## Gherkin in one minute

**Gherkin** is a plain-language format for describing how software should behave. It was made so that people who don't program can read and agree to it. A **feature** has a few **scenarios**, and each scenario has steps that start with a keyword:

```gherkin
Feature: House plants

  Scenario: add a plant
    When I open the page
    And I type "Fern" into "Plant name"
    And I press "Add"
    Then I see "Fern"

  Scenario: water a plant
    Given the list holds 1 plant
    When I press "Water" for "Fern"
    Then I see "watered today" for "Fern"
```

- **Given** sets up the situation.
- **When** is what the person does.
- **Then** is what they should see.
- **And** continues the line before it.

That's nearly all of Gherkin. It reads like instructions to a careful tester.

## How the agent uses it

The agent's first move on any task is `write_feature`: it turns the person's words into a feature file like the one above. Then it **waits for the person to agree**. Only after they agree does building start.

From then on, the scenarios are the definition of done:

- Each scenario is a **test**. The harness runs them and counts how many pass.
- "1 of 3 scenarios pass" in the state row is exactly this count.
- The app can only be published when every scenario passes.

## Steps: connecting words to code

A line like `I see "Fern"` is just words. To run it as a test, something has to say what it means. That's a **step definition**: a small piece of Lua that matches the line's pattern and checks the app.

```lua
test.step("the list holds {int} plant", function(w, n)
  plants.add("Fern")
  test.eq(#plants.list(), n)
end)
```

`{int}` matches a number in the line and hands it to the function as `n`. When a scenario runs, each of its lines is matched to a step and the step is run.

Many common lines (`I open the page`, `I type "x" into "y"`, `I press "x"`, `I see "x"`, `I see "x" for "row"`) are already defined by the agent's computer. They use the real page in a real browser engine, so a passing scenario means a person could really do it.

## Gherkin sets the stages

Because the feature is so central, the stage of the work (a column in the state row) is worked out from it:

| Stage | Means |
| --- | --- |
| `no_feature` | No feature yet: write one |
| `awaiting_agreement` | Written, waiting for the person's yes |
| `building` | Agreed; some scenarios don't pass yet |
| `ready` | Every scenario passes and every page answers |
| `awaiting_yes` | Asked the person to publish |
| `shipped` | Published |

Each stage allows only certain moves. You can't publish while `building`, and you can't write code before there is an agreed feature.

## Why this matters for learning

Scenarios give every step an honest score that doesn't depend on any model's opinion: the count of passing scenarios before and after. That count is what tells Tablua whether a step made **progress**, which is the label it learns from (Module 7).

## Remember

- Gherkin describes behaviour in plain words: Given, When, Then.
- The agent writes the feature first; the person agrees before building starts.
- Each scenario is a test; step definitions in Lua connect its words to checks.
- Passing scenarios set the stage and score each step, with no model involved.

## Next

On a computer that runs Lua, step definitions are Lua, as is everything else the agent writes there. [Module 4: Lua](/learn/lua)
