---
description: How Tablua keeps the app an agent builds as rows - sections, units, scenarios and the links between them - in one readable org file.
---

# The program as rows

The app an agent builds is rows too. Each file is cut into sections, and each section into units: a function, an action, a test scenario. The agent can change one unit at a time, the links between units are checked as data, and the file is always written back whole and readable.

## One file type: org

An app's file is written in **org**, a plain-text format that Emacs, GitHub and pandoc all read. Tablua uses a small part of it: headings, property drawers and source blocks. A file has up to five sections, always in this order:

| Section | Holds |
| --- | --- |
| `* Notes` | prose: what the app is for, decisions made |
| `* Feature` | the Gherkin scenarios the app must pass |
| `* Steps` | the Lua that checks each scenario against the app |
| `* Code` | the app's Lua |
| `* Page` | what the person sees, as Lua |

Each unit is a heading of its own, with its kind and name in a drawer and its text in a source block. This is what Tablua writes for one action:

```org
* Code
** post.add
:PROPERTIES:
:kind: action
:name: post.add
:END:
#+begin_src lua
function post.add(req)
  db.insert("plants", { name = req.form.name })
end
#+end_src
```

Reading a file into rows and writing it back gives the same file, byte for byte. Nothing is lost in either direction.

## Units

A **unit** is one top-level piece: a Lua statement (an action, a function, a local, a test step), a scenario, or a page. Each unit keeps the comments and blank lines above it, so cutting a file into units and joining them again never moves a comment away from its code.

Units are kept as `tablua_section`, `tablua_unit`, `tablua_scenario` and `tablua_line` rows.

## Editing one unit at a time

Instead of rewriting a whole file to change one function, the agent can name the file, the unit and the unit's new text. The harness replaces that unit in the file's rows and writes the file back whole:

```lua
local edit = require("tablua.edit")
edit.index("code/plants.lua", text)              --> { "plants", "add", "water" }
local new = edit.apply("code/plants.lua", text, "add", [[
function add(name)
  if name == "" then return nil, "a plant needs a name" end
  plants[#plants + 1] = { name = name }
end
]])
```

The new unit must compile, or the edit is refused with the reason, and nothing is written. Each edit is an `action` row naming the file, the unit and the bytes written.

Small edits mean smaller mistakes. A rewrite of a whole file can break things far from what it meant to change; an edit to one unit can't.

## Links and breaks

Units refer to each other. A page's button posts to an action. An action reads a field the form sends. A scenario's line needs a test step whose pattern matches it. Tablua records each of these as a `tablua_link` row.

A link with nothing at its end is a **break**, and breaks are a view over the links (`tablua_break`): a button that posts to an action nobody wrote, a field read that no form sends, a scenario line with no step, or an action no page can reach. Breaks can be found before any test runs, and they feed the agent's facts and TabPFN's columns like any other data.

## Why keep the program as rows

- **The agent works on the same units it is measured on.** A failing scenario points to a line; the line points to a step; the step to the code it calls.
- **Structure is data.** How many actions, how many breaks, which unit changed: all of it is columns a model can learn from.
- **The file stays a file.** It is still plain text a person can open, read and edit with any tool.

## Next

The agent's computer is where these files live. See [The agent's computer](/concepts/computer).
