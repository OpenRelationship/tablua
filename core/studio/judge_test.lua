-- Unit cases for studio.judge: the eye's observations and the engine's verdict on each expectation become one Jev
-- call, never told which move was picked, and its answers become the critic's scores and the next note.
local spec = require("spec")
local judge = require("studio.judge")

local expects = { { id = "high", says = "the HIGH row lands", node = "t4" }, { id = "lamp", says = "the lamp burns" } }
local findings = { { tier = "lint", id = "t4", code = "expect_failed", severity = "error", detail = "the HIGH row lands" } }
local seen = { "The tide table sits left, its HIGH row small and dim", "The buoy is dark against the sky" }

spec.test("one question per dim, the ask, each expectation and the next note; the sheet goes as an image", function()
  local state, qs = judge.ask{ ask = "the turn of the tide", treatment = "Rule: x", expects = expects,
    findings = findings, seen = seen, sheet_b64 = "UE5H" }
  spec.same({ state[1].type, state[2].image_url.url }, { "text", "data:image/png;base64,UE5H" })
  spec.ok(state[1].text:find("the HIGH row lands (the engine: failing)", 1, true), state[1].text)
  spec.ok(state[1].text:find("the lamp burns (the engine: holding)", 1, true))
  spec.ok(not state[1].text:lower():find("move", 1, true), "the judge is not told about moves")
  spec.same({ qs.rule.kind, #qs.rule.levels, qs.ask.kind, qs["expect:high"].kind, qs.next.kind },
    { "score", 5, "score", "noul", "choice" })
  spec.eq(qs.next.options.o2, seen[2])
end)

spec.test("answers become scores (the expected level), each expectation's p, and the chosen observation", function()
  local _, qs = judge.ask{ ask = "x", expects = expects, findings = {}, seen = seen }
  local answers = { ask = { score = qs.ask.levels[4], probabilities = { [qs.ask.levels[4]] = 0.5, [qs.ask.levels[2]] = 0.5 } },
    ["expect:high"] = { noul = 0.2 }, ["expect:lamp"] = { noul = 0.9 }, next = { choice = "o2" } }
  for _, d in ipairs(judge.dims) do answers[d] = { score = qs[d].levels[3], probabilities = { [qs[d].levels[3]] = 1 } } end
  local scores, said = judge.read(qs, answers)
  spec.same({ scores.rule, scores.ask, scores["expect:high"], scores["expect:lamp"] }, { 3, 3, 0.2, 0.9 })
  spec.eq(said.next, seen[2])
  spec.ok(said.notes:find("Next: The buoy is dark", 1, true), said.notes)
end)

spec.test("one observation or none: no choice is asked, the one is the next note", function()
  local _, qs = judge.ask{ ask = "x", expects = {}, findings = {}, seen = { "only this" } }
  spec.eq(qs.next, nil)
  local _, said = judge.read(qs, {}, { "only this" })
  spec.eq(said.next, "only this")
end)


spec.test("an expectation fails when a finding names it, as the engine writes it: its words, why, and (expect id)", function()
  local state = judge.ask{ ask = "x", expects = { { id = "wl", says = "22:58 HIGH sits on the waterline" } },
    findings = { { code = "expect_failed", id = "wl_type", severity = "error",
      detail = "22:58 HIGH sits on the waterline: node wl_type does not exist (expect wl)" } }, seen = {} }
  spec.ok(state:find("waterline (the engine: failing)", 1, true), state)
end)

spec.test("the judge reads the engine's errors and warnings, and is asked whether any text is cut off or overlapping", function()
  local state, qs = judge.ask{ ask = "x", expects = {}, seen = {}, findings = {
    { tier = "check", id = "t4", code = "text_overflow", severity = "error", detail = "74 px past the field" },
    { tier = "lint", id = "buoy", code = "subpixel_drift", severity = "info" } } }
  spec.ok(state:find("error text_overflow on t4: 74 px past the field", 1, true), state)
  spec.ok(not state:find("subpixel_drift", 1, true))
  spec.eq(qs.cut.kind, "noul")
end)
spec.run()
