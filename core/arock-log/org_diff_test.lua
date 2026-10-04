-- arock-log.org_diff: an org file's new text against its history, as events or refusals by line.
local spec = require("mono.spec")
local org_diff = require("arock-log.org_diff")

local NOW = { now = "2026-10-02 Fri 12:00" }

local function empty() return { path = "org/plants.org", entries = {}, known = {}, next_id = 1 } end

-- the history after a plan is kept, as the fold would hold it
local function after(h, plan)
  local known = {}
  for id in pairs(h.known) do known[id] = true end
  for _, e in ipairs(plan.entries) do known[e.id] = true end
  for _, id in ipairs(plan.archived) do known[id] = true end
  return { path = h.path, entries = plan.entries, header = plan.header, known = known, next_id = plan.next_id }
end

local function read_back(plan)
  local parts = { plan.header ~= "\n" and plan.header or nil }
  for _, e in ipairs(plan.entries) do parts[#parts + 1] = e.text end
  return table.concat(parts, "\n")
end

local function keywords(plan)
  local out = {}
  for _, ev in ipairs(plan.events) do out[#out + 1] = ev[1] end
  return table.concat(out, ",")
end

local function refused(text, h, line, pattern, opts)
  local plan, errs = org_diff.plan(text, h, opts or NOW)
  spec.eq(plan, nil, "the write should be refused")
  for _, e in ipairs(errs) do if e.line == line and e.msg:find(pattern, 1, true) then return end end
  error(("want line %d to say %q; got %s"):format(line, pattern, errs[1] and (errs[1].line .. ": " .. errs[1].msg) or "nothing"), 2)
end

local function start(text)
  local h = empty()
  local plan = assert(org_diff.plan(text, h, NOW))
  return after(h, plan), plan
end

spec.test("new entries are added with IDs the host gives", function()
  local h, plan = start("#+TITLE: plants\n\n* TODO Water the fern\n* Buy soil\n")
  spec.eq(keywords(plan), "Add Entry,Add Entry,Set Header")
  spec.eq(plan.events[1][2][1], "org/plants.org"); spec.eq(plan.events[1][2][2], "e1")
  spec.ok(plan.entries[1].text:find(":ID: e1", 1, true)); spec.eq(h.next_id, 3)
  spec.ok(plan.entries[1].text:find('- State "TODO" [2026-10-02 Fri 12:00]', 1, true), "a new task's state is logged")
end)

spec.test("writing back what was read changes nothing", function()
  local h, plan = start("* TODO Water the fern\n")
  local again = assert(org_diff.plan(read_back(plan), h, NOW))
  spec.eq(#again.events, 0)
end)

spec.test("a task done is stamped CLOSED and logged", function()
  local h, plan = start("* TODO Water the fern\n")
  local text = read_back(plan):gsub("TODO Water", "DONE Water")
  local done = assert(org_diff.plan(text, h, NOW))
  spec.eq(keywords(done), "Set State,Edit Entry")
  spec.same(done.events[1][2], { "e1", "TODO", "DONE" })
  spec.ok(done.entries[1].text:find("CLOSED: [2026-10-02 Fri 12:00]", 1, true))
  spec.ok(done.entries[1].text:find('- State "DONE" from "TODO" [2026-10-02 Fri 12:00]', 1, true))
  -- reopened, CLOSED goes and the reopening is logged
  local h2 = after(h, done)
  local reopened = assert(org_diff.plan(read_back(done):gsub("DONE Water", "TODO Water"), h2, NOW))
  spec.ok(not reopened.entries[1].text:find("CLOSED", 1, true))
end)

spec.test("CLOSED is the host's and history", function()
  refused("* DONE x\nCLOSED: [2026-10-01 Thu]\n", empty(), 1, "CLOSED is stamped by the computer")
  local h, plan = start("* DONE x\n")
  local text = read_back(plan):gsub("CLOSED: %[2026%-10%-02 Fri 12:00%]", "CLOSED: [2026-09-01 Tue]")
  refused(text, h, 1, "CLOSED is history and never rewritten")
end)

spec.test("an entry leaves only by archiving", function()
  local h, plan = start("* DONE Old\n* TODO New\n")
  local without = read_back(plan):gsub("%* DONE Old.-\n(%* TODO)", "%1")
  refused(without, h, 1, "an entry leaves only by archiving")
  local tagged = read_back(plan):gsub("%* DONE Old", "* DONE Old :ARCHIVE:")
  local archived = assert(org_diff.plan(tagged, h, NOW))
  spec.same(archived.archived, { "e1" }); spec.eq(#archived.entries, 1)
  spec.ok(keywords(archived):find("Archive Entry", 1, true))
end)

spec.test("IDs are the computer's, unique and never reused", function()
  refused("* TODO x\n:PROPERTIES:\n:ID: mine\n:END:\n", empty(), 1, "IDs are given by the computer")
  local h, plan = start("* a\n")
  refused(read_back(plan) .. read_back(plan), h, 5, "is on two entries")
  local archived = assert(org_diff.plan(read_back(plan):gsub("%* a", "* a :ARCHIVE:"), h, NOW))
  local h2 = after(h, archived)
  refused("* b\n:PROPERTIES:\n:ID: e1\n:END:\n", h2, 1, "belongs to another entry")
  local fresh = assert(org_diff.plan("* c\n", h2, NOW))
  spec.eq(fresh.entries[1].id, "e2", "an archived entry's ID is not given again")
end)

spec.test("a link names something the log or the node knows", function()
  local h = start("* a\n")
  local other = { path = "org/other.org", entries = {}, known = h.known, next_id = h.next_id }
  refused("* b [[id:e9]]\n", other, 1, "names no entry the log knows")
  local ok = assert(org_diff.plan("* b see [[id:e1]]\n", other, NOW))
  spec.eq(#ok.entries, 1)
  local resolve = function(t) return t == "org:fern/plants", "the address " .. t .. " names nothing" end
  refused("* c\n[[org:fern/nothing]]\n", empty(), 2, "the address org:fern/nothing names nothing",
    { now = NOW.now, resolve = resolve })
  spec.ok(org_diff.plan("* c\n[[org:fern/plants]] and [[https://fern.org/]]\n", empty(), { now = NOW.now, resolve = resolve }))
end)

spec.test("keywords change only as allowed", function()
  local h, plan = start("* DONE x\n")
  refused(read_back(plan):gsub("DONE x", "WAIT x"), h, 1, "DONE becomes only TODO again, not WAIT")
  local h2, p2 = start("* TODO y\n")
  refused(read_back(p2):gsub("TODO y", "y"), h2, 1, "a task keeps its keyword")
end)

spec.test("a number stays a number; GRANTED and the LOGBOOK are the host's", function()
  local h, plan = start("* w\n:PROPERTIES:\n:DAYS: 7\n:END:\n")
  refused(read_back(plan):gsub(":DAYS: 7", ":DAYS: soon"), h, 1, "was a number")
  refused("* w\n:PROPERTIES:\n:GRANTED: 2026-10-02\n:END:\n", empty(), 1, "GRANTED is written by the host")
  local hosted = assert(org_diff.plan("* w\n:PROPERTIES:\n:GRANTED: 2026-10-02\n:END:\n", empty(), { now = NOW.now, host = true }))
  local h2 = after(empty(), hosted)
  local dropped = assert(org_diff.plan(read_back(hosted):gsub(":GRANTED: 2026%-10%-02\n", ""), h2, NOW))
  spec.ok(dropped.entries[1].text:find(":GRANTED: 2026-10-02", 1, true), "left out, a grant stays")
  local h3, p3 = start("* DONE z\n")
  refused(read_back(p3):gsub('%- State "DONE"', '- State "DROP"'), h3, 1, "the LOGBOOK is the computer's")
end)

spec.test("a reorder is a move; a header change is a header", function()
  local h, plan = start("#+TITLE: a\n\n* one\n* two\n")
  local swapped = read_back(plan):gsub("(%* one.-)(%* two.*)$", "%2\n%1")
  local moved = assert(org_diff.plan(swapped, h, NOW))
  spec.eq(keywords(moved), "Move Entry"); spec.eq(moved.events[1][2][2], "e2 e1")
  local retitled = assert(org_diff.plan(read_back(plan):gsub("#%+TITLE: a", "#+TITLE: b"), h, NOW))
  spec.eq(keywords(retitled), "Set Header")
end)

spec.test("dates and properties changed are their own events", function()
  local h, plan = start("* TODO x\n")
  local text = read_back(plan):gsub("(%* TODO x\n)", "%1SCHEDULED: <2026-10-03 Sat>\n"):gsub(":END:", ":WHERE: balcony\n:END:", 1)
  local changed = assert(org_diff.plan(text, h, NOW))
  spec.eq(keywords(changed), "Set Date,Set Property,Edit Entry")
  spec.same(changed.events[1][2], { "e1", "scheduled", "<2026-10-03 Sat>" })
end)

spec.test("text outside the subset never reaches the log", function()
  refused("* a\n#+INCLUDE: x.org\n", empty(), 2, "#+INCLUDE")
end)

spec.run()
