-- arock-log.org_kinds: each template passes its own check, and each kind refuses what it must.
local spec = require("mono.spec")
local kinds = require("arock-log.org_kinds")

local VARS = { title = "Plants", goal = "Water the fern", today = "2026-10-03 Sat", heading = "Ferns",
  subject = "Build the plants page", from = "fern", to = "moss-1", computer = "fern" }

local function says(kind, text, pattern)
  local _, errs = kinds.check(kind, text)
  for _, e in ipairs(errs) do if e.msg:find(pattern, 1, true) then return end end
  error(("%s: want %q, got %s"):format(kind, pattern, errs[1] and errs[1].msg or "nothing"), 2)
end

spec.test("every template, filled, passes its own check", function()
  for _, kind in ipairs({ "task", "note", "letter", "manifest" }) do
    local _, errs = kinds.check(kind, kinds.template(kind, VARS))
    spec.eq(#errs, 0, kind .. ": " .. (errs[1] and errs[1].msg or ""))
  end
end)

spec.test("each kind refuses what it must", function()
  says("task", "#+TITLE: x\n\n* Just a heading\n", "at least one TODO")
  says("note", "* Ferns\nwords\n", "a note has a #+TITLE")
  says("letter", "* Hi\n:PROPERTIES:\n:TO: org:moss-1\n:END:\n", "names :FROM:")
  says("letter", "* Hi\n:PROPERTIES:\n:FROM: fern\n:TO: org:moss-1\n:END:\n", ":FROM: is an org: address")
  says("letter", "* One\n* Two\n", "one top headline")
  says("manifest", "* Tools\n** w\nW.\n", "RUN names the code")
end)

spec.test("what the computer writes is refused from an agent", function()
  says("task", "* DONE x\nCLOSED: [2026-10-01 Thu]\n", "CLOSED is stamped by the computer")
  says("task", "* TODO x\n:LOGBOOK:\n- State \"DONE\"\n:END:\n", "the LOGBOOK is kept by the computer")
end)

spec.test("each kind has its own help", function()
  spec.ok(kinds.help("manifest"):find(":EVERY:", 1, true))
  spec.ok(kinds.help("letter"):find(":FROM:", 1, true))
  spec.ok(not kinds.HELP:find(":TO: org:", 1, true), "the common help shows no property to copy")
end)

spec.test("the help names the subset", function()
  for _, word in ipairs({ "TODO, WAIT, DONE or DROP", "org:", "Nothing in org runs" }) do
    spec.ok(kinds.HELP:find(word, 1, true), word)
  end
end)

spec.run()
