-- arock-log.org_kinds: the four kinds of org file an agent writes, each with the template `new org <kind>` gives and
-- the check that file must pass, and the help that teaches the org we speak (what Mercury reads).
--
--   kinds.HELP                    -- `help org`: the subset, in one screen
--   kinds.template(kind, vars)    -- task | note | letter | manifest; vars fill {computer}, {today}, {from}, {to}
--   kinds.check(kind, text)       -- -> doc, errs (org's and the kind's, by line)
local org = require("arock-log.org")
local manifest = require("arock-log.manifest")

local M = {}

M.HELP = [==[
Org, as this computer speaks it. Lua does things; org says things.

* A headline starts with stars. Its keyword is TODO, WAIT, DONE or DROP, then [#A], [#B] or [#C], then the title,
  then tags like :home:plants:.
* Right under a headline, its planning: SCHEDULED: <2026-10-03 Sat 09:00> DEADLINE: <2026-10-05 Mon>. Never
  write CLOSED: the computer stamps it when a task becomes DONE. A repeat: <2026-10-03 Sat 09:00 +1w>.
* Then, only if the kind below asks for properties, a drawer, one :KEY: value a line, never inside a list:
  :PROPERTIES:
  :KEY: value
  :END:
  Leave out :ID:; the computer gives each entry one. Never write a LOGBOOK; the computer keeps it.
  A drawer goes nowhere else: not at the end of an entry, not as a list item.
* Body: paragraphs, lists (- item), checkboxes (- [ ] and - [X]), description lists (- term :: what it is),
  tables (| a | b |), and #+BEGIN_QUOTE, #+BEGIN_EXAMPLE or #+BEGIN_SRC lua blocks (kept as text).
* Links: [[org:fern/plants/weather][the weather tool]], [[https://example.com]], [[file:files/report.pdf]].
  Every thing on the node has an org: address: org:<computer>/<app>/<tool>.
* File keywords, before the first headline: #+TITLE:, #+DATE:, #+FILETAGS:.
* Nothing in org runs: no Babel (header arguments, #+CALL, src_), no macros, no #+INCLUDE or #+SETUPFILE.
Write only the org file, with no fences around it.
]==]

-- what each kind adds to the help
M.KIND_HELP = {
  task = [==[
A task file: headlines with TODO (to do), WAIT (waiting on someone), DONE or DROP (given up). Steps are
checkboxes or sub-headlines. Tasks need no properties.
]==],
  note = [==[
A note: #+TITLE, then headings and plain sentences, lists and tables. Notes need no keywords and no properties.
]==],
  letter = [==[
A letter: exactly one top headline, its subject, with TODO when it hands over work. Right under it a drawer
with :FROM: (the sender's org: address) and :TO: (the recipient's), then the message. Nothing else is a
property; a date goes on the planning line under the headline.
]==],
  manifest = [==[
A manifest declares what this computer or app offers. Only two headings: * Apps (a list of [[org:<computer>/<app>]]
links) and * Tools (one ** headline per tool, named in a-z, 0-9 and -, as water-plant). No keywords.
Each tool's drawer: :RUN: code/<name>.lua (always), and only these, when needed:
  :NET: host names it may fetch, space-separated (api.open-meteo.com), no paths or schemes
  :MAIL: org: addresses it may send to (org:moss-1); a computer on the node is reached by MAIL, never NET
  :ACCOUNT: one app of the person's it uses (slack, google)
  :ASK: alone, when it must have the person's yes before each run
  :PUBLISH: alone, when it opens an app to people other than the owner
  :EVERY: hourly, daily 07:00, weekly Fri 17:00, or every 15m, every 6h, every 1d
  :ON: mail (when a letter arrives), or write org/*.org (when such a file changes)
Then one sentence saying what the tool does, then its arguments, one a line:
  - city :: string     - days :: number = 3     - note :: string?     - units :: one of metric|imperial
The types are string, number, bool and one of a|b|c; ? makes it optional, = gives a default.
]==],
}

function M.help(kind) return M.HELP .. "\n" .. assert(M.KIND_HELP[kind], "no org kind " .. tostring(kind)) end

M.TEMPLATES = {
  task = [==[
#+TITLE: {title}

* TODO {goal}
SCHEDULED: <{today}>
What done looks like, in a sentence.
- [ ] the first step
]==],
  note = [==[
#+TITLE: {title}

* {heading}
What was learned, in plain sentences.
- term :: what it means
]==],
  letter = [==[
* TODO {subject}
:PROPERTIES:
:FROM: org:{from}
:TO: org:{to}
:END:
What you need from them, and by when.
]==],
  manifest = [==[
#+TITLE: {computer}

* Apps
- [[org:{computer}/plants]]

* Tools
** weather
:PROPERTIES:
:RUN: code/weather.lua
:NET: api.open-meteo.com
:END:
Pull the day's weather for the plants app.
- city :: string
]==],
}

function M.template(kind, vars)
  local t = assert(M.TEMPLATES[kind], "no org kind " .. tostring(kind))
  return (t:gsub("{(%w+)}", function(k) return vars and vars[k] or "{" .. k .. "}" end))
end

local function err(errs, line, msg) errs[#errs + 1] = { line = line, msg = msg } end

-- what no kind may hold: what the host writes
local function host_only(doc, errs)
  for _, e in ipairs(doc.entries) do
    if e.closed then err(errs, e.line, "CLOSED is stamped by the computer when a task becomes DONE; leave it out") end
    if #e.logbook > 0 then err(errs, e.line, "the LOGBOOK is kept by the computer; leave it out") end
  end
end

local CHECKS = {}

function CHECKS.task(doc, errs)
  local any = false
  for _, e in ipairs(doc.entries) do if e.keyword then any = true end end
  if not any then err(errs, 1, "a task file holds at least one TODO, WAIT, DONE or DROP headline") end
end

function CHECKS.note(doc, errs)
  if not doc.title then err(errs, 1, "a note has a #+TITLE") end
end

function CHECKS.letter(doc, errs)
  local tops = {}
  for _, e in ipairs(doc.entries) do if e.level == 1 then tops[#tops + 1] = e end end
  if #tops ~= 1 then err(errs, 1, "a letter is one top headline (its subject), with any below it") return end
  local e = tops[1]
  for _, key in ipairs({ "FROM", "TO" }) do
    local v = e.props[key]
    if not v then err(errs, e.line, "a letter names :" .. key .. ": as an org: address")
    elseif not org.address(v) then err(errs, e.line, ":" .. key .. ": is an org: address, as org:moss-1, not " .. v) end
  end
end

function CHECKS.manifest(doc, errs)
  local _, merrs = manifest.read(doc)
  for _, e in ipairs(merrs) do errs[#errs + 1] = e end
end

function M.check(kind, text)
  local doc, errs = org.parse(text)
  host_only(doc, errs)
  assert(CHECKS[kind], "no org kind " .. tostring(kind))(doc, errs)
  table.sort(errs, function(a, b) return a.line < b.line end)
  return doc, errs
end

return M
