-- The turns as AgentWorldBench's terminal samples write them, character for character.
local spec = require("spec")
local turns = require("term.turns")

spec.test("a first turn and a later one, as the training samples write them", function()
  spec.eq(turns.user(1, "ls -la\n", 0.1, "root@bb210bf1ec82:/app#"),
    '### Turn 1\n**Current State:**\nroot@bb210bf1ec82:/app#\n\n**Action:**\n```json\n[\n  {\n    "keystrokes": "ls -la\\n",\n'
    .. '    "duration": 0.1\n  }\n]\n```')
  spec.eq(turns.user(2, "./maze_game.sh\n", 1),
    '### Turn 2\n**Action:**\n```json\n[\n  {\n    "keystrokes": "./maze_game.sh\\n",\n    "duration": 1.0\n  }\n]\n```')
end)

spec.test("the session goes as user and assistant turns; the oldest fall out of the window, the first kept says the screen", function()
  local session = { opening = "root@x:/app#", turns = {} }
  for i = 1, 3 do session.turns[i] = { keys = "echo " .. i .. "\n", wait = 1, screen = "root@x:/app# echo " .. i .. "\n" .. i .. "\nroot@x:/app#" } end
  local m = turns.messages(session, "ls\n", 0.5)
  spec.same({ #m, m[1].role, m[2].role, m[7].role }, { 7, "user", "assistant", "user" })
  spec.ok(m[1].content:find("**Current State:**\nroot@x:/app#\n", 1, true), m[1].content)
  spec.ok(m[2].content:find("^%*%*Environment Observation:%*%*\nroot@x:/app# echo 1"), m[2].content)
  local keep, keep_cut = turns.window, turns.cut_every
  turns.window, turns.cut_every = 2, 1
  m = turns.messages(session, "ls\n", 0.5)
  turns.window, turns.cut_every = keep, keep_cut
  spec.ok(m[1].content:find("### Turn 1\n**Current State:**\nroot@x:/app# echo 1\n1\nroot@x:/app#\n", 1, true), m[1].content)
  spec.ok(m[5].content:find("### Turn 3\n", 1, true), m[5].content)
end)

spec.test("the foreseen screen is the last predicted_observation block, after any reasoning", function()
  spec.eq(turns.observed("From Turn 2:\n<predicted_observation>old</predicted_observation>\nSo:\n"
    .. "<predicted_observation>root@x:/app# ls\na.txt\nroot@x:/app#</predicted_observation>"), "root@x:/app# ls\na.txt\nroot@x:/app#")
  spec.eq(turns.observed("**Environment Observation:**\nroot@x:/app#"), "root@x:/app#")
  spec.eq(turns.observed("I am not sure."), nil)
end)

spec.test("with no tag, the fenced block that holds a prompt, or the lines from the first prompt (thinking off)", function()
  local screen = "root@4f2a:/app# gcc -o hello hello.c\ngcc: error: hello.c: No such file or directory\nroot@4f2a:/app#"
  spec.eq(turns.observed("It fails like:\n```\ngcc: error: x\n```\nHere is the predicted terminal state:\n```\n"
    .. screen .. "\n```\n"), screen)
  spec.eq(turns.observed("Here is the predicted terminal state:\n\n```\n" .. screen), screen)
  spec.eq(turns.observed("Let's predict the terminal state:\n\n" .. screen), screen)
  spec.eq(turns.observed("The prompt `root@4f2a:/app#` shows a shell."), nil)
end)

spec.test("an observation is the visible screen: its last 40 lines, as the training samples show it", function()
  local lines = {}
  for i = 1, 100 do lines[i] = "line " .. i end
  local o = turns.observation(table.concat(lines, "\n"))
  spec.ok(o:find("\nline 61\n", 1, true) and not o:find("line 60\n", 1, true), o:sub(1, 80))
  spec.ok(o:find("line 100$"), "ends at the last line")
end)

spec.test("past the window, the oldest turn sent moves only every cut_every turns", function()
  local keep_w, keep_c = turns.window, turns.cut_every
  turns.window, turns.cut_every = 4, 3
  local session = { opening = "root@x:/app#", turns = {} }
  local firsts = {}
  for i = 1, 12 do
    session.turns[i] = { keys = "echo " .. i .. "\n", wait = 1, screen = "root@x:/app# echo " .. i .. "\n" .. i .. "\nroot@x:/app#" }
    local m = turns.messages(session, "ls\n", 1)
    firsts[i] = m[1].content:match("Current State:%*%*\n.-echo (%d+)") or "0"
  end
  turns.window, turns.cut_every = keep_w, keep_c
  local changes = 0
  for i = 2, 12 do if firsts[i] ~= firsts[i - 1] then changes = changes + 1 end end
  spec.ok(changes <= 3, "the first turn moved " .. changes .. " times: " .. table.concat(firsts, ","))
end)

spec.run()
