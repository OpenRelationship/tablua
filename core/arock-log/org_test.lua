-- arock-log.org: the subset parsed, refused by line, and rendered back the same.
local spec = require("mono.spec")
local org = require("arock-log.org")

local function errs_of(text)
  local _, errs = org.parse(text)
  return errs
end

local function refused(text, line, pattern)
  local errs = errs_of(text)
  for _, e in ipairs(errs) do
    if e.line == line and e.msg:find(pattern, 1, true) then return end
  end
  local got = {}
  for _, e in ipairs(errs) do got[#got + 1] = e.line .. ": " .. e.msg end
  error(("want line %d to say %q; got %s"):format(line, pattern, #got > 0 and table.concat(got, "; ") or "nothing"), 2)
end

local PLANTS = table.concat({
  "#+TITLE: plants",
  "",
  "* TODO [#A] Water the fern :home:plants:",
  "SCHEDULED: <2026-10-03 Sat 07:00 +1w>",
  ":PROPERTIES:",
  ":ID: t-1",
  ":TO: org:fern/plants",
  ":END:",
  "Every week, before work. See [[org:fern/plants/weather][the weather tool]].",
  "- [ ] fill the can",
  "- [X] check the soil",
  "- city :: Lisbon",
  "** DONE Buy a can",
  "CLOSED: [2026-10-01 Thu 18:00]",
  "| plant | days |",
  "| fern  | 7    |",
  "#+BEGIN_SRC lua",
  "print('kept as text, never run')",
  "#+END_SRC",
}, "\n") .. "\n"

spec.test("a file in the subset parses with no errors", function()
  local doc, errs = org.parse(PLANTS)
  spec.eq(#errs, 0, "errors")
  spec.eq(doc.title, "plants")
  spec.eq(#doc.entries, 2)
  local t = doc.entries[1]
  spec.eq(t.keyword, "TODO"); spec.eq(t.priority, "A"); spec.eq(t.title, "Water the fern")
  spec.same(t.tags, { "home", "plants" })
  spec.eq(t.scheduled.hh, 7); spec.eq(t.scheduled["repeat"], "+1w"); spec.ok(t.scheduled.active)
  spec.eq(t.props.ID, "t-1"); spec.eq(t.props.TO, "org:fern/plants")
  spec.eq(t.links[1].target, "org:fern/plants/weather"); spec.eq(t.links[1].line, 9)
  local d = doc.entries[2]
  spec.eq(d.keyword, "DONE"); spec.eq(d.parent, 1); spec.eq(d.closed.d, 1); spec.ok(not d.closed.active)
end)

spec.test("render is canonical and parses back the same", function()
  local doc = org.parse(PLANTS)
  local text = org.render(doc)
  spec.eq(org.render(org.parse(text)), text)
  spec.ok(text:find("SCHEDULED: <2026-10-03 Sat 07:00 +1w>", 1, true), "the date renders back")
end)

spec.test("a wrong weekday is recomputed, not refused", function()
  local doc, errs = org.parse("* TODO x\nDEADLINE: <2026-10-02 Mon>\n")
  spec.eq(#errs, 0)
  spec.ok(org.render(doc):find("<2026-10-02 Fri>", 1, true))
end)

spec.test("nothing in org runs", function()
  refused("#+INCLUDE: secrets.org\n", 1, "#+INCLUDE is outside the org we speak")
  refused("#+SETUPFILE: x.setup\n", 1, "#+SETUPFILE")
  refused("* a\n#+CALL: build()\n", 2, "#+CALL")
  refused("* a\n#+BEGIN_SRC lua :results output\nx\n#+END_SRC\n", 2, "header arguments are Babel")
  refused("* a\nrun src_lua{os.exit()} now\n", 2, "inline Babel")
  refused("* a\n{{{secret}}}\n", 2, "macros")
  refused("* a\n[[shell:rm -rf /]]\n", 2, "scheme shell:")
  refused("* a\n[[elisp:(kill-emacs)]]\n", 2, "scheme elisp:")
end)

spec.test("keywords, priorities and checkboxes are ours", function()
  refused("* NEXT call the vet\n", 1, "NEXT is not a keyword we speak")
  refused("* TODO [#D] x\n", 1, "a priority is [#A], [#B] or [#C]")
  refused("* a\n- [?] maybe\n", 2, "a checkbox is")
  refused("* TODO\n", 1, "a headline has a title")
end)

spec.test("planning may span lines before the drawer, never after it", function()
  local doc, errs = org.parse("* TODO x\nSCHEDULED: <2026-10-03 Sat>\nDEADLINE: <2026-10-05 Mon>\n:PROPERTIES:\n:A: 1\n:END:\n")
  spec.eq(#errs, 0)
  spec.eq(doc.entries[1].deadline.d, 5)
  local after = org.parse("* TODO x\n:PROPERTIES:\n:A: 1\n:END:\nSCHEDULED: <2026-10-03 Sat>\n")
  spec.eq(after.entries[1].scheduled, nil, "a planning line after the drawer is body")
end)

spec.test("dates are real", function()
  refused("* a\nSCHEDULED: <2026-02-30 Mon>\n", 2, "no day 30 in 2026-02")
  refused("* a\nDEADLINE: <2026-13-01>\n", 2, "no month 13")
  refused("* a\nSCHEDULED: <2026-10-02 25:00>\n", 2, "no time 25:00")
  refused("* a\nSCHEDULED: <2026-10-02 Fri]\n", 2, "a date is")
  spec.eq(#errs_of("* a\nSCHEDULED: <2028-02-29 Tue>\n"), 0, "a leap day")
end)

spec.test("drawers are PROPERTIES and LOGBOOK, closed, in place", function()
  refused("* a\n:PROPERTIES:\n:ID: 1\n", 3, "never closed")
  refused("* a\n:PROPERTIES:\n:ID: 1\n:ID: 2\n:END:\n", 4, "set twice")
  refused("* a\n:CLOCK:\n:END:\n", 2, ":CLOCK: is outside")
  refused("* a\nsome words\n:PROPERTIES:\n:ID: 1\n:END:\n", 3, "right after the headline")
  refused(":PROPERTIES:\n:END:\n", 1, "belongs under a headline")
  refused("* a\n:END:\n", 2, "closes nothing")
  refused("* a\n:PROPERTIES:\nnot a property\n:END:\n", 3, "a property is :KEY: value")
end)

spec.test("blocks are QUOTE, EXAMPLE and SRC, and end", function()
  refused("* a\n#+BEGIN_EXPORT html\n<b>\n#+END_EXPORT\n", 2, "#+BEGIN_EXPORT is outside")
  refused("* a\n#+BEGIN_QUOTE\nwords\n", 3, "never ended")
  spec.eq(#errs_of("* a\n#+begin_quote\n* not a headline inside\n#+end_quote\n"), 0, "lower case, and a star inside")
end)

spec.test("file keywords are TITLE, DATE and FILETAGS, before any headline", function()
  refused("#+AUTHOR: me\n", 1, "#+AUTHOR is outside")
  refused("* a\n#+TITLE: late\n", 2, "#+TITLE is outside")
  local doc = org.parse("#+FILETAGS: :a:b:\n")
  spec.same(doc.filetags, { "a", "b" })
end)

spec.test("headline tags alone and preamble text", function()
  local doc, errs = org.parse("Words before.\n\n* Meeting :work:\n")
  spec.eq(#errs, 0)
  spec.eq(doc.preamble[1], "Words before.")
  spec.same(doc.entries[1].tags, { "work" }); spec.eq(doc.entries[1].title, "Meeting")
end)

spec.test("a hostile line reads in linear time, and its reading keeps its meaning", function()
  -- each of these took seconds to minutes at 64 KB before the patterns were made linear
  local K = 64 * 1024
  local t = os.clock()
  for _, text in ipairs({
    "* b\n" .. ("[["):rep(K / 2), "* b" .. (" "):rep(K) .. "x\n", "* b\n" .. ("A: <"):rep(K / 4) .. "\n",
    "* b\n:PROPERTIES:\n:A: x" .. (" "):rep(K) .. "x\n:END:\n", "#+TITLE: x" .. (" "):rep(K) .. "x\n* b\n",
  }) do org.parse(text) end
  spec.ok(os.clock() - t < 2, "five 64 KB hostile letters in under 2 s")
  local e = org.parse("* TODO  Water   :a:b:  \n:PROPERTIES:\n:K:   v  w  \n:END:\n").entries[1]
  spec.eq(e.title, "Water"); spec.same(e.tags, { "a", "b" }); spec.eq(e.props.K, "v  w")
  spec.eq(org.parse("* :only:\n").entries[1].title, "")
  spec.eq(org.parse("* a:b: c\n").entries[1].title, "a:b: c", "a word ending in colons mid-title is not tags")
  spec.eq(org.parse("#+TITLE:   far  \n").title, "far")
  -- a link's target holds no bracket: [[[[org:a/b]] is the link org:a/b, which the post then judges
  spec.eq(org.parse("* [[[[org:a/b]] x\n").entries[1].links[1].target, "org:a/b")
end)

spec.run()
