---
description: How Tablua keeps the app an agent builds as rows - sections, units, tests, keywords and the links between them - in one readable org file.
---

# The program as rows

The app an agent builds is rows too. Each file is cut into sections, and each section into units: a function, an action, a test, a keyword. The agent can change one unit at a time, the links between units are checked as data, and the file is always written back whole and readable.

## One file type: org

An app's file is written in **org**, a plain-text format that Emacs, GitHub and pandoc all read. Tablua uses a small part of it: headings, property drawers and source blocks. A file has up to five sections, always in this order:

| Section | Holds |
| --- | --- |
| `* Notes` | prose: what the app is for, decisions made |
| `* Tests` | the tests the app must pass, and their user keywords, in Robot Framework's syntax |
| `* Keywords` | the Lua keywords the tests call to check the app |
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

A **unit** is one top-level piece: a Lua statement (an action, a function, a local, a keyword), or a page. Each unit keeps the comments and blank lines above it, so cutting a file into units and joining them again never moves a comment away from its code.

The Tests section is cut the same way, by Robot's own structure: its head (settings and variables), then each test and each user keyword, under a `** Test:` or `** Keyword:` heading with its text in a `#+begin_src robot` block:

```org
* Tests
** Test: Add a plant
#+begin_src robot
,*** Test Cases ***
Add a plant
    Type    Plant name    Fern
    Press    Add
    See    Fern
#+end_src
```

A library keyword in the Keywords section is a Lua unit like any other, declared by name: `keyword("There is a plant ${name}", function(name) ... end)`.

Units are kept as `tablua_section` and `tablua_unit` rows; tests and user keywords as `tablua_test` and `tablua_keyword` rows, and every keyword call either makes as a `tablua_call` row (its path in the item, the keyword it names, its arguments).

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

## Change blocks

A **change block** is an edit written as a short script of operations, the way a database migration is. Each operation starts on a line beginning `%%`, with the text it needs under it:

```text
%% replace sum
local function sum(a, b) return (a or 0) + (b or 0) end
%% add difference after sum
local function difference(a, b) return a - b end
%% rename sum plus
%% test Subtracting
Subtracting
    I subtract 2 from 5
    See    3
```

| Operation | Does |
| --- | --- |
| `add <name> [after <unit> \| first]` | adds a unit; refused when the name is taken |
| `replace <name>` | replaces a unit's source |
| `delete <name>` | removes a unit |
| `rename <old> <new>` | renames a unit and every reference to it in the file's Lua, never a string or a comment |
| `test <name> [after <other> \| first]` | adds or replaces a test, or removes it when nothing is under it |
| `task <name> [after <other> \| first]` | the same for a task; a first task goes after the tests and before the keywords |
| `keyword <name> [after <other> \| first]` | adds or replaces a user keyword, or removes it when nothing is under it |

A block is applied all or nothing: if one operation names nothing, or leaves Lua that does not compile, none of them happens and the refusal names the operation by number. Every block comes back with the block that undoes it, so the build can always be walked back. `!` after a verb takes the text under it verbatim, which is how the undoing block is written.

Each operation is a `tablua_change` row in the log: what it did, to what kind of unit, how many code lines it added, how many units named what it touched, and how many it left naming something that no longer exists. A model learns from what an edit does, not from its text.

```lua
local change = require("tablua.change")
local done, why = change.apply(rows, block)   --> { rows, reverse, ops } or nil, "operation 2 names no unit ..."
```

## Page elements

A page written as Lua is one expression of nested calls, so cut only into top-level units it is a single unit, and the agent rewrites the whole page to move one button. Tablua cuts it further, as a tree. Every call through a dotted name given a table or a string (`ui.card{ ... }`, `ui.h2"Plants"`, `ui.button("Add")`) is an **element**, and its children are the elements in its arguments. The cut knows Lua's calls, not any host's `ui` module; Lua's own libraries (`string.format(...)`) are not elements.

An element is named by a path of its calls' last names, from the root down, with `[2]` for the second of a name among its siblings:

```lua
return ui.page{                                   -- page
  title = "Plants",
  ui.card{                                        -- page/card
    ui.form{ post = "add",                        -- page/card/form
      ui.input{ name = "name" },                  -- page/card/form/input
      ui.input{ name = "count" },                 -- page/card/form/input[2]
      ui.button("Add") },                         -- page/card/form/button
  },
}
```

A change block names elements as it names units:

| Operation | Does |
| --- | --- |
| `set <path> <prop>` | sets a prop to the value under it, adds it, or takes it away when nothing is under it |
| `put before\|after <path>`, `put in <path> [at <k>]`, `put first in <path>` | puts in the element under it |
| `drop <path>` | removes an element |
| `move <path> before\|after\|in <path>` | moves an element, its lines indented for where it lands |
| `wrap <path>` | wraps an element in the call under it, written with `...` where the element goes |
| `unwrap <path>` | replaces a wrapper that holds one element with that element |

The rest of the page stays byte for byte, and every element operation is undone exactly by its reverse. An element operation's `tablua_change` row has the element's call as its kind and its path as its name, and counts as breaks the posts and form reads it left with nothing at their end.

Each element is a `tablua_element` row in the build: its path, call, parent, depth, number of children, prop names and text.

## Links and breaks

Units refer to each other. A page's button posts to an action. An action reads a field the form sends. A test's call needs a keyword of that name: a Lua keyword, a user keyword, one of BuiltIn's or one the host's computer gives. Tablua records each of these as a `tablua_link` row.

A link with nothing at its end is a **break**, and breaks are a view over the links (`tablua_break`): a button that posts to an action nobody wrote, a field read that no form sends, a call no keyword answers, or an action no page can reach. Breaks can be found before any test runs, and they feed the agent's facts and TabPFN's columns like any other data.

## Why keep the program as rows

- **The agent works on the same units it is measured on.** A failing test points to the keyword it failed at; the keyword points to the code it calls.
- **Structure is data.** How many actions, how many breaks, which unit changed: all of it is columns a model can learn from.
- **The file stays a file.** It is still plain text a person can open, read and edit with any tool.

## Next

The agent's computer is where these files live. See [The agent's computer](/concepts/computer).
