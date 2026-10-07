-- Unit cases for agent.compact, pi's compaction (packages/coding-agent/src/core/compaction): tokens estimated at four
-- characters each, a cut at a user or assistant turn that keeps the newest ~keep tokens, the rest summarised in pi's
-- checkpoint format and put back as one user turn, an earlier summary updated rather than lost.
local spec = require("spec")
local compact = require("agent.compact")

local function turns(k, size)
  local out = {}
  for i = 1, k do
    out[#out + 1] = { role = "user", content = ("u%d "):format(i) .. string.rep("x", size) }
    out[#out + 1] = { role = "assistant", content = "", tool_calls = { { id = "c" .. i, type = "function",
      ["function"] = { name = "patch", arguments = "{}" } } } }
    out[#out + 1] = { role = "tool", tool_call_id = "c" .. i, name = "patch", content = string.rep("y", size) }
  end
  return out
end

spec.test("tokens are characters over four, an image a fixed 1200; compaction is due past the window less the reserve", function()
  spec.eq(compact.tokens({ { role = "user", content = string.rep("a", 400) } }), 100)
  spec.eq(compact.tokens({ { role = "tool", content = "", image = "UE5H" } }), 1200)
  spec.ok(not compact.due(turns(3, 400), { window = 100000 }))
  spec.ok(compact.due(turns(3, 400), { window = 600, reserve = 100 }))
end)

spec.test("the cut keeps the newest turns whole: never between a call and its result", function()
  local msgs = turns(10, 4000)   -- about 2000 tokens a turn
  local cut = compact.cut(msgs, 5000)
  spec.ok(msgs[cut].role == "user" or msgs[cut].role == "assistant", msgs[cut].role)
  local kept = 0
  for i = cut, #msgs do kept = kept + compact.tokens({ msgs[i] }) end
  -- pi moves the cut forward to the nearest turn, so a little under keep may stay
  spec.ok(kept >= 3000 and kept < 9000, kept)
end)

spec.test("the older turns become one summary turn; the summary is asked of the model in pi's format", function()
  local msgs = turns(10, 4000)
  local asked
  local model = { chat = function(_, req) asked = req return "## Goal\nA tide clock." end }
  local out = compact.run(msgs, model, { keep = 5000 })
  spec.ok(out[1].role == "user" and out[1].content:find("<summary>\n## Goal\nA tide clock.\n</summary>", 1, true))
  spec.ok(#out < #msgs)
  spec.ok(asked.system:find("context summarization assistant", 1, true))
  spec.ok(asked.user:find("[User]: u1", 1, true) and asked.user:find("## Next Steps", 1, true))
  spec.ok(asked.user:find("[Assistant tool calls]: patch()", 1, true))
  -- a second compaction updates the first summary
  local again = compact.run(out, model, { keep = 1000 })
  spec.ok(asked.user:find("<previous-summary>", 1, true) and asked.user:find("PRESERVE all existing", 1, true))
  spec.eq(again[1].summary, true)
end)

spec.test("a summary that fails leaves the transcript as it was", function()
  local msgs = turns(10, 4000)
  local out, why = compact.run(msgs, { chat = function() error("timeout", 0) end }, { keep = 5000 })
  spec.same({ out, why }, { msgs, "compaction failed: timeout" })
end)


spec.test("a checkpoint rendered from the tables takes the summary's place: no model is asked", function()
  local msgs = turns(10, 4000)
  local model = { chat = function() error("no model call when the checkpoint is rendered", 0) end }
  local out = compact.run(msgs, model, { keep = 5000, render = function(older)
    return "## Goal\nA tide clock.\n\n## Progress\nstep 1 brief -> complete (" .. #older .. " messages before)" end })
  spec.ok(out[1].summary and out[1].content:find("## Progress\nstep 1 brief", 1, true), out[1].content)
  -- a re-render replaces the checkpoint rather than nesting it
  local again = compact.run(out, model, { keep = 1000, render = function() return "## Goal\nagain" end })
  spec.ok(again[1].content:find("## Goal\nagain", 1, true) and not again[1].content:find("A tide clock", 1, true))
end)
spec.run()
