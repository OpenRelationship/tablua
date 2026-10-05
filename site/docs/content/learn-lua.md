---
description: Module 4. Tablua is written in Lua and embeds in any Lua VM. What the agent writes can be any language its computer runs.
---

# 4. Lua: the harness's language

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

## Tablua is native Lua

The harness, meaning the code that runs the loop and writes the rows, is plain, portable Lua and nothing else. A host embeds it with whatever Lua VM it already has:

- **LuaJIT**
- standard **Lua 5.4 or 5.5**
- any other Lua VM a host runs, such as one inside a larger runtime

The harness never reaches the world directly. It goes through small **ports** the host supplies: one for SQLite, one for each model, and one for the computer that runs the agent's code. That is what makes it embeddable almost anywhere.

## What the agent writes is up to its computer

Lua is the harness's language. It is not a limit on what the agent writes. The agent writes an app as an org file (Module 5), and each code block in it says what language it is in:

```org
* Code
#+begin_src python
def add(a, b):
    return a + b
#+end_src
```

The rows keep that language as data. Whatever the agent's computer can run, the agent can write. Tablua reads Lua code more closely than other languages today: it cuts a Lua block into its top-level statements and finds which functions call which. A block in any other language is kept whole, as one unit. Adding the same close reading for another language means writing a small scanner for it.

## When the computer runs Lua

A host may give its agents a computer that runs Lua and nothing else. Then the agent writes its code, its keywords and its pages in Lua, and the harness reads all of it closely:

| What | Example |
| --- | --- |
| Code | `function post.add(req) ... end`, an action the page's form calls |
| Keywords | `keyword("There is a plant ${name}", function(name) ... end)` |
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

Why a host might keep its computer to one language:

- **Safe to run.** The agent has no shell on any machine. Its Lua runs inside its own computer, against its own files, with only the modules it was given.
- **A small, closed vocabulary.** The computer gives the agent a short list of modules (files, a database, HTTP, JSON, mail, the page kit, the test kit). A model that only ever sees this small world can get very good at it.
- **One reader for everything.** Code, keywords and pages are all Lua, so all of them are cut into the same kind of rows. The tests beside them are Robot, cut into rows of their own.

## Remember

- Tablua is native Lua and embeds in any Lua VM: LuaJIT, Lua 5.4/5.5, or another.
- It reaches SQLite, the models and the agent's computer only through ports the host supplies.
- What the agent writes can be any language its computer runs; each code block carries its language.
- On a computer that runs only Lua, the output is Lua, read as closely as the harness itself.

## Next

Code, keywords, pages and the tests belong together. Where do they live? [Module 5: Org](/learn/org)
