-- arock-log.manifest: apps, tools, typed arguments, triggers and reach read from a manifest.org, and refused by line.
local spec = require("mono.spec")
local org = require("arock-log.org")
local manifest = require("arock-log.manifest")

local function read(text, opts)
  local doc, errs = org.parse(text)
  spec.eq(#errs, 0, "org errors: " .. (errs[1] and errs[1].msg or ""))
  return manifest.read(doc, opts)
end

local function refused(text, line, pattern)
  local doc, errs = org.parse(text)
  local _, merrs = manifest.read(doc)
  for _, e in ipairs(merrs) do errs[#errs + 1] = e end
  local got = {}
  for _, e in ipairs(errs) do
    if e.line == line and e.msg:find(pattern, 1, true) then return end
    got[#got + 1] = e.line .. ": " .. e.msg
  end
  error(("want line %d to say %q; got %s"):format(line, pattern, #got > 0 and table.concat(got, "; ") or "nothing"), 2)
end

local FERN = table.concat({
  "#+TITLE: fern",
  "",
  "* Apps",
  "- [[org:fern/plants]]",
  "- [[org:fern/notes]]",
  "",
  "* Tools",
  "** weather",
  ":PROPERTIES:",
  ":RUN: code/weather.lua",
  ":NET: api.open-meteo.com",
  ":END:",
  "Pull the day's weather for the plants app.",
  "- city :: string",
  "- days :: number = 3",
  "- units :: one of metric|imperial = metric",
  "- note :: string?",
  "** post-summary",
  ":PROPERTIES:",
  ":RUN: code/summary.lua",
  ":ACCOUNT: slack",
  ":ASK:",
  ":EVERY: weekly Fri 17:00",
  ":END:",
  "Post the week's summary to the person's Slack.",
}, "\n") .. "\n"

spec.test("apps, tools and their arguments are read", function()
  local m, errs = read(FERN)
  spec.eq(#errs, 0, errs[1] and errs[1].msg)
  spec.eq(#m.apps, 2); spec.eq(m.apps[1].name, "plants"); spec.eq(m.apps[1].address, "org:fern/plants")
  spec.same(m.order, { "weather", "post-summary" })
  local w = m.tools.weather
  spec.eq(w.run, "code/weather.lua"); spec.same(w.net, { "api.open-meteo.com" })
  spec.eq(w.description, "Pull the day's weather for the plants app.")
  spec.eq(#w.args, 4)
  spec.eq(w.args[1].type, "string"); spec.eq(w.args[2].default, "3")
  spec.same(w.args[3].choices, { "metric", "imperial" }); spec.ok(w.args[4].optional)
  local p = m.tools["post-summary"]
  spec.eq(p.account, "slack"); spec.ok(p.ask); spec.eq(p.every, "weekly Fri 17:00")
end)

spec.test("an agent cannot grant itself; the host reads its grant", function()
  local text = "* Tools\n** weather\n:PROPERTIES:\n:RUN: code/weather.lua\n:GRANTED: 2026-10-02\n:END:\nWeather.\n"
  refused(text, 2, "GRANTED is written by the host")
  local m, errs = read(text, { host = true })
  spec.eq(#errs, 0); spec.eq(m.tools.weather.granted, "2026-10-02")
end)

spec.test("a tool runs code, says what it does, and asks in known words", function()
  refused("* Tools\n** weather\nWeather.\n", 2, "RUN names the code it runs")
  refused("* Tools\n** weather\n:PROPERTIES:\n:RUN: weather.sh\n:END:\nW.\n", 2, "RUN names a code file")
  refused("* Tools\n** weather\n:PROPERTIES:\n:RUN: code/w.lua\n:END:\n", 2, "its first paragraph says what it does")
  refused("* Tools\n** weather\n:PROPERTIES:\n:RUN: code/w.lua\n:SHELL: yes\n:END:\nW.\n", 2, "SHELL is not a tool property")
  refused("* Tools\n** Weather Tool\n:PROPERTIES:\n:RUN: code/w.lua\n:END:\nW.\n", 2, "a tool's name is a-z")
  refused("* Tools\n** w\n:PROPERTIES:\n:RUN: code/w.lua\n:NET: https://x.com/a\n:END:\nW.\n", 2, "NET lists host names")
  refused("* Tools\n** w\n:PROPERTIES:\n:RUN: code/w.lua\n:MAIL: bob@x.com\n:END:\nW.\n", 2, "MAIL lists org: addresses")
  refused("* Tools\n** w\n:PROPERTIES:\n:RUN: code/w.lua\n:EVERY: at dawn\n:END:\nW.\n", 2, "EVERY is hourly")
  refused("* Tools\n** w\n:PROPERTIES:\n:RUN: code/w.lua\n:ON: boot\n:END:\nW.\n", 2, "ON is mail")
  refused("* Tools\n** w\n:PROPERTIES:\n:RUN: code/w.lua\n:END:\nW.\n** w\n:PROPERTIES:\n:RUN: code/w.lua\n:END:\nW.\n", 7, "declared twice")
end)

spec.test("NET and MAIL take commas or spaces", function()
  local m = read("* Tools\n** news\n:PROPERTIES:\n:RUN: code/news.lua\n:NET: api.a.com, api.b.com\n:END:\nNews.\n")
  spec.same(m.tools.news.net, { "api.a.com", "api.b.com" })
  local none = read("* Tools\n** w\n:PROPERTIES:\n:RUN: code/w.lua\n:NET:\n:END:\nW.\n")
  spec.same(none.tools.w.net, {}, "an empty NET asks for nothing")
end)

spec.test("arguments are typed", function()
  spec.eq(manifest.arg("- n :: number = 7").default, "7")
  spec.eq(select(2, manifest.arg("- n :: number = soon")), "the default soon is not a number")
  spec.ok(select(2, manifest.arg("- n :: date")):find("string, number, bool or one of", 1, true))
  spec.ok(select(2, manifest.arg("- s :: one of big")):find("two choices", 1, true))
  spec.eq(manifest.arg("- on :: bool = true").type, "bool")
  spec.same(manifest.arg("- op :: read|write").choices, { "read", "write" })
end)

spec.test("a manifest is Apps and Tools, and declares", function()
  refused("* Apps\n- plants\n", 2, "an app is listed as")
  refused("* Apps\n- [[org:fern]]\n", 2, "an app is listed as")
  refused("* Notes\n", 1, "headings are * Apps and * Tools")
  refused("* Tools\n** TODO w\n:PROPERTIES:\n:RUN: code/w.lua\n:END:\nW.\n", 2, "a manifest declares")
  refused("* Apps\n- [[org:Fern/plants]]\n", 2, "parts are a-z")
end)

spec.test("every names a clock", function()
  for _, ok in ipairs({ "hourly", "daily 07:00", "weekly Mon 9:30", "every 15m", "every 2h", "every 1d" }) do
    spec.ok(manifest.every(ok), ok)
  end
  for _, bad in ipairs({ "daily 25:00", "weekly Someday 09:00", "every 0m", "every 5s", "nightly" }) do
    spec.ok(not manifest.every(bad), bad)
  end
end)

-- a writ's tools (Arock feature notes): weekdays, a fixed offset from UTC for the person's clock, where the tool came
-- from (a writ's address) and the form of its result
spec.test("every takes weekdays and an offset from UTC", function()
  for _, ok in ipairs({ "weekdays 07:00", "weekdays 7:00 UTC-07:00", "daily 07:00 UTC+05:30", "weekly Mon 09:00 UTC+00:00" }) do
    spec.ok(manifest.every(ok), ok)
  end
  for _, bad in ipairs({ "weekdays", "weekdays 24:00", "daily 07:00 PST", "daily 07:00 UTC-15:00", "hourly UTC-07:00",
      "every 15m UTC+01:00", "weekdays 07:00 UTC-7" }) do
    spec.ok(not manifest.every(bad), bad)
  end
end)

spec.test("a writ's tool says where it came from and what it makes", function()
  local text = "* Tools\n** file-mail\n:PROPERTIES:\n:RUN: code/file-mail.lua\n:EVERY: weekdays 07:00 UTC-07:00\n"
    .. ":FROM: note-3@2#1-62\n:OUTPUT: one task a letter, in org/inbox.org\n:END:\nFiles the morning's mail as tasks.\n"
  local m, errs = read(text)
  spec.eq(#errs, 0, errs[1] and errs[1].msg)
  local t = m.tools["file-mail"]
  spec.eq(t.from, "note-3@2#1-62"); spec.eq(t.output, "one task a letter, in org/inbox.org")
  spec.eq(t.every, "weekdays 07:00 UTC-07:00")
  refused("* Tools\n** x\n:PROPERTIES:\n:RUN: code/x.lua\n:FROM: my notes\n:END:\nX.\n", 2, "FROM is a writ's address")
end)

spec.run()
