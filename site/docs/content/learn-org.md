---
description: Module 5. How an app lives in one readable org file - notes, feature, steps, code and page - and how that file is cut into rows the harness can check and edit.
---

# 5. Org: one file holds it all

## What org is

**Org** is a plain-text format, best known from Emacs's org mode. It's like Markdown with a little more structure: headings start with stars, and blocks of code sit between `#+begin_src` and `#+end_src`. GitHub, pandoc and many editors can read it.

```org
* A heading
Some prose under it.
** A smaller heading
#+begin_src lua
print("hello")
#+end_src
```

That's the part of org Tablua uses: headings, prose, property drawers (a small list of key-value pairs under a heading) and source blocks.

## One app, one file

An app the agent builds is an org file with up to five sections, always in this order:

```org
* Notes
A little app for house plants: list them, add one, mark one watered.

* Feature
#+begin_src feature
Feature: House plants
  Scenario: add a plant
    When I open the page
    And I type "Fern" into "Plant name"
    And I press "Add"
    Then I see "Fern"
#+end_src

* Steps
#+begin_src lua
test.step("the list holds {int} plant", function(w, n) ... end)
#+end_src

* Code
#+begin_src lua
function post.add(req) db.insert("plants", { name = req.form.name }) end
#+end_src

* Page
#+begin_src lua
return ui.main{ ui.h1"House plants", ui.form{ post = "add", ... } }
#+end_src
```

Everything from the earlier modules is here in one place: the person's intent (Notes), what done means (Feature, Gherkin), how it's checked (Steps, Lua), what it does (Code, Lua) and what the person sees (Page, Lua).

A person can open this file and read it top to bottom. That matters: the agent's work is never hidden in a format only a machine can read.

## From file to rows

Here is where the tables come back. Tablua cuts the file into pieces and keeps each piece as a row:

| Table | One row per | Example |
| --- | --- | --- |
| `tablua_section` | section of a file | the `* Code` section |
| `tablua_unit` | top-level piece of a section | the action `post.add` |
| `tablua_scenario` | scenario in the feature | "add a plant" |
| `tablua_line` | line of a scenario | `And I press "Add"` |
| `tablua_link` | reference between pieces | the form's `post = "add"` points at `post.add` |

A **unit** is one complete piece you could edit on its own: a function, an action, a test step, a scenario. Reading a file into rows and writing it back gives exactly the same file, byte for byte.

## Why cut it up

**The agent edits one unit at a time.** Instead of rewriting a whole file to change one function, it names the unit and gives its new text. The harness swaps it in and writes the file back. A small edit can't break things far away.

**Broken links show up before any test runs.** Every reference is a `tablua_link` row. A link that points at nothing is a **break**: a form that posts to an action nobody wrote, a page calling a function its module never defined, a scenario line no step matches. Tablua finds breaks with a query (the `tablua_break` view) and tells the agent at once.

**Structure becomes data.** How many units changed, how many breaks there are, which unit a failing line touches: all of it is columns a model can learn from.

## Remember

- Org is plain text with headings and code blocks; people and tools can read it.
- An app is one org file: Notes, Feature, Steps, Code, Page.
- Tablua cuts the file into sections, units, scenarios, lines and links, all rows.
- The agent edits one unit at a time, and broken links are found with a query.

## Next

So far we have facts, tests and the program, all as rows. Now: who decides what to do? [Module 6: Three models](/learn/models)
