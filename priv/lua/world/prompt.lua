-- What the computer's agent shows its two minds (world/world.lua; Arock's library/agent). Jev reads a small state: the task, the
-- stage and facts, the parts, the newest steps; only what bears on the choice (TypeSafe: accuracy falls as state
-- fills). Mercury fills Jev's move with tool calls on the computer, laid out as Inception's Mercury 2.5 guide says:
-- a fixed system prompt in its order (persona, knowledge base, procedures, examples with negatives, critical rules
-- last, since Mercury weights recent context most), the same on every call of a run so Inception's prefix cache
-- holds; then the turn: the task, the current state, the work so far and the move, with Jev's sureness. Strict tool
-- schema, tool_choice required, temperature 0.6, medium reasoning.
--
--   prompt.state(a, req, for_jev, facts) -> text      prompt.fill(a, req, move, what, run) -> calls | nil, why
--   prompt.system(run) -> text                         prompt.arbiter(...), prompt.think(...) -> Mercury requests
local json = require("ports.json")

local M = {}

M.mercury_chars = 60000   -- the work so far as Mercury reads it; older steps' results are cut first
M.close_note = 0.6        -- below this, Mercury is told which other move Jev weighed

M.tool = { type = "function", ["function"] = { name = "computer", strict = true,
  description = "Runs one command line in /home on your computer and returns its status, stdout and stderr. The"
    .. " files are written first, each whole, so a call can write a file and run what checks it.",
  parameters = { type = "object", required = { "cmd" }, properties = {
    cmd = { type = "string", description = "One command line, as help lists them: test, check, open app, mail send"
      .. " rock-1 -m '...', cat code/plants.lua. To write files and only check them, check." },
    files = { type = "object", additionalProperties = { type = "string" },
      description = "Files to write before the command runs: path (relative to /home) to the whole new text." } } } } }

M.examples = [[
Where the app lives. Right: everything in /home: features/plants.feature, code/plants.lua, code/steps/plants.lua,
ui/index.lui (served at /, opened with open app), data/plants.dbl. Wrong: apps/plants/... or a manifest.org: the
home is the app and needs neither, and the computer refuses files under apps/.

Writing a file. Right: {"cmd": "test", "files": {"code/steps/plants.lua": "<the whole file>"}}, the file whole,
and the command that checks it in the same call. Wrong: {"cmd": "echo 'end)' >> code/steps/plants.lua"}, a file
built a line at a time.

A step. Right:
  test.step("the person adds a plant named {string}", function(w, name) plants.add(name) end)
  test.step("the list holds {int} plants", function(w, n) test.eq(#plants.list(), n) end)
each step calls the app's own code and checks what it did. Wrong:
  test.step("the person adds a plant named {string}", function(w, name) end)
an empty step passes and checks nothing; the computer counts them, and the app cannot ship with one.
A step's holes match the feature's words as written: {string} only "quoted" text, {word} one bare word, {int} a
number. For the line `Given there is a plant named Fern`, right: test.step("there is a plant named {word}", ...).
Wrong: test.step("there is a plant named {string}", ...): Fern has no quotes, so the step never matches and test
keeps saying no step matches.

The app's data. Right: code/plants.lua opens the computer's own database and both the steps and the page
require it:
  local d = db.open("data/plants.dbl")
  d:exec("create table if not exists plant (name text primary key, watered text)")
  function M.add(name) d:exec("insert into plant values (?, ?)", name, nil) end
Wrong: a code/data.lua that keeps the rows in a Lua table and answers SQL with string matching: the steps pass
or fail on a stand-in, and the page shows nothing the person added.

A date in a feature. Right: Given an event "Party" 7 days from today, and a step that makes it with
date.add(date.now(), { days = 7 }): it passes on any day. Wrong: an event on "2026-10-10" with 7 days left: it
is true one day only.

A module. Right: code/habits.lua starts local M = {} and ends return M; a step file needs neither. Wrong:
function M.add(name) ... in a file that never says local M = {}: the error names it, code/habits.lua:3: attempt to
index a nil value (global 'M').

A statement that fails stops. Right: read its error, code/chores.lua:12: table chores has no column named person,
and change the statement or the table so they agree. Wrong: wrapping it in pcall so the page answers and keeps
nothing.

One table, one module. Right: code/chores.lua makes the table and holds every statement on it; the steps and the
page both require("chores") and call its functions. Wrong: steps that db.open and create the table themselves
with other columns (assigned_to where the page writes person): the steps pass on their own table and the page
fails on it.

A scenario's data. test gives each scenario empty tables of its own (never the app's data), so a scenario makes
what it reads in its Givens. Right: Given there is a plant named Fern, whose step calls plants.add("Fern"). Wrong:
a Then that counts rows no Given of its scenario made.

Looking at the app. Right: one command line that opens the page the current state names (Page / (open app)
answers 200), types in the page's fields by number (the browser numbers them from 1 in the page's order, as the
page you wrote has them), and submits:
  {"cmd": "open app; type 1 Zinnia; submit 1"}     (a form whose second field is a count: type 2 3 before submit)
then the page it prints must show Zinnia. Wrong: open app alone (nothing was used, so nothing was seen); open app
house-plants (a second page is open app/<path>, the path joined with /).
Each move does only its own part: the DONE letter is answer_task's, publish is publish's, the feature is
write_feature's; the computer refuses them in any other move.

A page and its database. Right: the code the page uses makes its table first,
  d:exec("create table if not exists plant (name text primary key, watered text)")
then queries it. Wrong: a query of a table nothing made: the page answers 500 and the app cannot ship.

A form that adds. Right: <form post="add"> and function post.add(req) that inserts req.form's fields. Wrong: an
empty function get.add(req) end written to quiet check's "names no action": the form then keeps nothing.

A page's colours. Right: the theme's, class="btn" or "bg-primary text-primary-foreground", "text-muted-foreground",
"border-border". Wrong: palette colours such as bg-blue-500 or text-gray-600: Shroomi knows none of them and
check names each one.

Answering the task. Right: the letter in a file, each line on its own line, then sent:
  {"cmd": "mail send rock-1 < files/reply.org", "files": {"files/reply.org": "* DONE Built the plants app
  :PROPERTIES:
  :TASK: org:rock-1/mail/1
  :END:
  It is at /plants/: add a plant, water it."}}
the address is the sender's id, the letter one org entry naming the task in :TASK:, sent once. Wrong: a \n
written into the letter where a line should break; mail send org:rock-1 DONE; printf ... | mail send (the
computer has no printf).
]]

M.rules = [[
- Make only this move's calls, then stop. Never decide the work is done: the decider does.
- Write every file whole with files; never build one with echo, printf, sed or >>. Change only what the failing
  step or page needs: keep every step and function that passes as it is.
- Every step checks real behaviour with test.eq or test.ok; never leave a body empty.
- Use only the commands help lists, and the APIs the knowledge base shows (db.open for data, test.step for steps,
  .lui for pages); never write a stand-in for one. Read an error's file and line before changing anything.
- Never write GRANTED, CLOSED or a LOGBOOK, never edit org/procedures/, and never change a feature the person
  agreed to without their agreeing again.
]]

function M.system(run)
  return table.concat({
    "<persona>",
    "You fill the next move of an agent that builds small apps on its own computer for a person. The agent's decider"
      .. " has chosen the move; you make its tool calls on the computer. You write plain, correct code, whole files at"
      .. " a time, and you never claim what a command's output does not show.",
    "</persona>",
    "<knowledge_base>", run.help, "</knowledge_base>",
    "<procedures>", run.procedures, "</procedures>",
    "<examples>", M.examples, "</examples>",
    "<critical_rules>", M.rules, "</critical_rules>",
  }, "\n")
end

function M.state(a, req, for_jev, facts)
  local out = { "<task>", req.text, "</task>", "<current_state>", facts }
  local parts = require("agent.parts").render(req)
  if parts then out[#out + 1] = parts end
  if req.guidance then out[#out + 1] = "Guidance: " .. req.guidance end
  local card = for_jev and require("agent.checkpoint").card(req)
  if card then out[#out + 1] = card end
  out[#out + 1] = ("This is step %d."):format(#req.steps + 1)
  out[#out + 1] = "</current_state>"
  out[#out + 1] = "<work_so_far>"
  out[#out + 1] = for_jev and a.history:render(a.name, true) or M.work(a)
  out[#out + 1] = "</work_so_far>"
  return table.concat(out, "\n")
end

-- the work so far, newest whole, within Mercury's budget
function M.work(a)
  local history = require("agent.history")
  local keep = history.mercury_chars
  history.mercury_chars = M.mercury_chars
  local text = a.history:render(a.name, false)
  history.mercury_chars = keep
  return text
end

local function sure_note(req)
  local s = req.sure
  if not s then return "" end
  local note = (" The decider gave it %.2f."):format(s.p)
  if s.p < M.close_note and req.second then note = note .. " It also weighed " .. req.second .. "." end
  return note
end

local function cause_note(req, causes)
  local c = req.cause
  if not c or not causes[c.choice] then return "" end
  return ("\nThe decider places the failure's cause in %s%s: %s"):format(c.choice,
    c.p and (" (%.2f)"):format(c.p) or "", causes[c.choice])
end

function M.fill(a, req, move, what, run, causes)
  local turn = M.state(a, req, false, a.world.facts_text(req)) .. "\n<next_move>\n" .. move .. ": " .. what
    .. sure_note(req) .. cause_note(req, causes or {}) .. "\n</next_move>\nMake the tool calls for this move now, in order."
  local ok, _, record = pcall(a.env.mercury.chat, a.env.mercury, { kind = "fill", reasoning_effort = "medium",
    temperature = 0.6, max_tokens = 8000, tools = { M.tool }, tool_choice = "required",
    messages = { { role = "system", content = M.system(run) }, { role = "user", content = turn } } })
  if not ok then return nil, tostring(_) end
  local calls = {}
  for _, tc in ipairs(record.tool_calls or {}) do
    local okj, args = pcall(json.decode, tc["function"] and tc["function"].arguments or "")
    if okj and type(args) == "table" and type(args.cmd) == "string" then calls[#calls + 1] = args end
  end
  return calls
end

function M.arbiter(a, req, first, second, moves)
  return { kind = "arbiter", reasoning_effort = "high", max_tokens = 1500,
    system = "You settle a close call for an agent building an app on its own computer. Its decider is torn between"
      .. " two next moves:\n- " .. first .. ": " .. tostring(moves[first]) .. "\n- " .. second .. ": "
      .. tostring(moves[second]) .. "\nRead the task, the state and every step so far, and pick the move that gets"
      .. " the task done. Reply with the name alone: " .. first .. " or " .. second .. ".",
    user = M.state(a, req, false, a.world.facts_text(req)) }
end

function M.blocked(a, req, moves)
  local names = {}
  for name, what in pairs(moves) do names[#names + 1] = "- " .. name .. ": " .. what end
  table.sort(names)
  return { kind = "blocked", reasoning_effort = "medium", max_tokens = 3000,
    system = "An agent building an app on its own computer has decided that none of its moves can make progress."
      .. " Its moves:\n" .. table.concat(names, "\n") .. "\nRead the task, the state and every step so far. In at"
      .. " most four short lines say what is missing or failing that no move can fix, as its maker would need to"
      .. " hear it.",
    user = M.state(a, req, false, a.world.facts_text(req)) }
end

function M.think(a, req, moves)
  local names = {}
  for name, what in pairs(moves) do names[#names + 1] = "- " .. name .. ": " .. what end
  table.sort(names)
  return { kind = "think", reasoning_effort = "high", max_tokens = 1500,
    system = "You are a careful reviewer for an agent that builds apps on its own computer. Its moves:\n"
      .. table.concat(names, "\n") .. "\nRead the task, the state and every step so far. In at most eight short"
      .. " lines say what is going on, what went wrong and why, and exactly what to do next.",
    user = M.state(a, req, false, a.world.facts_text(req)) }
end

return M
