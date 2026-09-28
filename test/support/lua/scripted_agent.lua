-- A scripted agent for host tests: Volvox's coding machine with a fake Jev
-- and fake actions. Everything it decides comes from the store, since the
-- host starts every step from a fresh state: the tests fail until the fix
-- has written the guarded div.
return function(host)
  local store = volvox.store(host)
  local choices = { understand = "yes", choose_scaffold = "edit_existing", write = "yes", fix = "retry" }
  local jev = {
    decide = function(_, state, questions)
      local out = {}
      for id in pairs(questions) do
        local choice = choices[id] or state:match("Last test result: (%a+)")
        out[id] = { choice = choice, confidence = 0.9 }
      end
      return out, { service = "jev", model = "scripted", tries = 1, seconds = 0.2, cost = 0.0001 }
    end,
  }
  local actions = {
    gather_context = function() return {} end,
    apply_edits = function() return { { "Write File", "calc.py", "def div(a, b):\n    return a / b\n" } } end,
    apply_fix = function() return { { "Write File", "calc.py", "def div(a, b):\n    return a / b if b else None\n" } } end,
    run_tests = function()
      if (store:file("calc.py") or ""):find("if b", 1, true) then return { { "Test Result", "pass" } } end
      return { { "Test Result", "fail", "ZeroDivisionError in test_div" } }
    end,
  }
  return { machine = require("plan.machines.code"), jev = jev, actions = actions, budget = 30 }
end
