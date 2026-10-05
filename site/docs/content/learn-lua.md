---
description: Module 4. Why Tablua uses Lua for everything - the harness, the agent's code, its tests and its pages - and what that looks like.
---

# 4. Lua: the one language

## What Lua is

**Lua** is a small programming language made to be embedded inside other programs. Games, editors and databases use it so that their users can script them. The whole language fits in a short manual, and its interpreter is tiny.

If you know almost any language, Lua will look familiar:

```lua
local plants = {}                          -- a table (Lua's one data structure)

local function add(name)
  plants[#plants + 1] = { name = name }    -- #plants is the list's length
end

add("Fern")
print(plants[1].name)                      --> Fern
```

The only unusual thing is the **table**: Lua's single data structure, used for lists, records and objects alike.

## Lua shows up twice in Tablua

**1. The harness itself is Lua.** The code that runs the loop and writes the rows is portable Lua: the same files run on LuaJIT, on standard Lua 5.4 and 5.5, and on a Lua that runs inside Erlang's virtual machine (the BEAM). That's what lets the harness be embedded almost anywhere. It reaches the database and the models only through small "ports" the host program supplies.

**2. Everything the agent writes is Lua.** The app's code, its test steps and even its pages:

| What | Example |
| --- | --- |
| Code | `function post.add(req) ... end`, an action the page's form calls |
| Steps | `test.step("I see {string}", function(w, s) ... end)` |
| Pages | `return ui.main{ ui.h1"Plants", ui.form{ ... } }` |

A page is a Lua expression that builds the page out of `ui` calls:

```lua
return ui.main{
  ui.h1"House plants",
  ui.form{ post = "add", ui.input{ name = "name", placeholder = "Plant name" }, ui.button"Add" },
  ui.ul(items),
}
```

`post = "add"` means submitting the form calls the action `post.add`, which the Code part defines.

## Why one language

- **One parser understands everything.** Code, tests and pages can all be read into structured pieces the same way. That is what makes Module 5 possible.
- **A small, closed vocabulary.** The agent's computer gives it a short list of modules (files, a database, HTTP, JSON, mail, the page kit, the test kit). A model that only ever sees this small world can get very good at it, and a tabular model can learn from its patterns.
- **Safe to run.** The agent has no shell on any machine. Its Lua runs inside its own computer, against its own files, with only the modules it was given.

## The agent's computer

Each agent gets its own small computer, called **Moss**. Its disk is the same SQLite file its rows live in. Moss answers a short list of commands itself (`cat`, `test`, `check`, `publish`, and so on), runs the agent's Lua, serves its pages, and has a headless browser for using them. You don't need to know Moss to understand the harness. It's enough to know the agent's Lua runs there, in a box of its own.

## Remember

- Lua is a small language built for embedding; its one data structure is the table.
- The harness is portable Lua, so it can run inside many hosts.
- The agent writes its code, its test steps and its pages in Lua.
- One language and a small vocabulary make the agent's work easy to read as data, and easy to learn from.

## Next

Code, steps, pages and the feature belong together. Where do they live? [Module 5: Org](/learn/org)
