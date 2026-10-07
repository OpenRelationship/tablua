-- Unit cases for the Jev port against a fake host: answers by question kind, and an optional question (a feature
-- asked beside the decision) that may go unanswered without failing the decision.
local spec = require("spec")
local json = require("ports.json")
local jev = require("ports.jev")

local function fake(answers)
  local sent
  local host = { fetch = function(req)
    sent = json.decode(req.body)
    return { status = 200, body = json.encode({ model = "typesafe/jev-1.13", answers = answers, usage = { cost = 0 } }) }
  end }
  return jev.new(host, { key = "k" }), function() return sent end
end

local next_q = { kind = "choice", text = "next?", options = { a = "do a", b = "do b" } }

spec.test("a choice, a noul and a score come back by kind", function()
  local j, sent = fake({ next = { choice = "a", probabilities = { a = 0.7, b = 0.3 } }, dates = { noul = 0.9 },
    done = { score = "most", probabilities = { most = 1 } } })
  local out = j:decide("state", { next = next_q, dates = { kind = "noul", text = "dates?", yes = "y", no = "n" },
    done = { kind = "score", text = "done?", levels = { "none", "most" } } })
  spec.eq(out.next.choice, "a")
  spec.eq(out.dates.noul, 0.9)
  spec.eq(out.done.score, "most")
  spec.eq(sent().questions.dates.type, "noul")
end)

spec.test("an optional question left unanswered is left out; a required one fails", function()
  local j = fake({ next = { choice = "b", probabilities = { a = 0.2, b = 0.8 } } })
  local out = j:decide("state", { next = next_q,
    dates = { kind = "noul", text = "dates?", yes = "y", no = "n", optional = true } })
  spec.eq(out.next.choice, "b")
  spec.eq(out.dates, nil)
  local ok = pcall(j.decide, j, "state", { next = next_q, dates = { kind = "noul", text = "d?", yes = "y", no = "n" } })
  spec.eq(ok, false)
end)

spec.test("a score keyed by level index (Jev's form since studio pi-s5) comes back keyed by level text", function()
  -- as gpt-6-luna-decisions answered on 2026-10-07: probabilities by 0-based index, score their expected index
  local j = fake({ craft = { type = "score", score = 3.12, confidence = 0.65,
    legend = { ["0"] = "1: fails", ["1"] = "2: weak", ["2"] = "3: ok" },
    probabilities = { ["0"] = 0.01, ["1"] = 0.29, ["2"] = 0.7 } } })
  local out = j:decide("state", { craft = { kind = "score", text = "craft?", levels = { "1: fails", "2: weak", "3: ok" } } })
  spec.same({ out.craft.score, out.craft.probabilities["3: ok"], out.craft.probabilities["2: weak"],
    out.craft.probabilities["0"] }, { "3: ok", 0.7, 0.29, nil })
end)

spec.run()
