-- Unit cases for agent/history.lua: the one conversation Jev and Mercury both read, in order, with Jev's copy cut
-- to what bears on the choice and a talked-over answer kept as far as it was heard.
local spec = require("spec")
local history = require("agent.history")

spec.test("turns and steps read back in order", function()
  local h = history.new()
  h:begin()
  h:person("list my files")
  h:step({ verb = "run", lines = { "a.txt b.txt" }, n = 1 })
  h:rock("You have two files.")
  local text = h:render("Fern", false)
  spec.ok(text:find("Person: list my files\n  Step 1: run\n    a.txt b.txt\nFern: You have two files.", 1, true))
end)

spec.test("Jev reads the latest step's result cut, Mercury reads it whole", function()
  local h = history.new()
  h:begin()
  h:step({ verb = "run", lines = { ("x"):rep(history.latest_result + 500) }, n = 1 })
  spec.ok(#h:render("Fern", true) < history.latest_result + 200)
  spec.ok(#h:render("Fern", false) > history.latest_result + 500)
end)

spec.test("an answer talked over is kept as far as it was heard", function()
  local h = history.new()
  h:rock("The weather is fine today and tomorrow")
  spec.eq(h:cut(1, 2), "The weather is fine")
end)

spec.test("the conversation alone as chat turns, starting with the person", function()
  local h = history.new()
  h:rock("hi")
  h:person("hello")
  h:rock("how can I help")
  spec.same(h:turns(), { { role = "user", content = "hello" }, { role = "assistant", content = "how can I help" } })
end)

spec.run()
