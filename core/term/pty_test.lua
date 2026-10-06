-- Raw terminal bytes as columns: colours, redraws, the alternate screen, and the text without escapes.
local spec = require("spec")
local pty = require("term.pty")

local E = "\27"

spec.test("lines shown in red, yellow and green, and the text without its escapes", function()
  local r = pty.read("ok\n" .. E .. "[1;31merror:" .. E .. "[0m bad thing\n" .. E .. "[33mwarning" .. E .. "[m\n"
    .. E .. "[32mPASSED" .. E .. "[39m\n")
  spec.same({ r.lines, r.red, r.yellow, r.green, r.bold }, { 4, 1, 1, 1, 1 })
  spec.eq(r.text, "ok\nerror: bad thing\nwarning\nPASSED\n")
end)

spec.test("256-colour and true-colour red count as red", function()
  spec.eq(pty.read(E .. "[38;5;196mfail\n").red, 1)
  spec.eq(pty.read(E .. "[38;2;220;40;40mfail\n").red, 1)
end)

spec.test("a progress bar redraws its line; a full-screen program takes the alternate screen", function()
  local r = pty.read(" 10%\r 50%\r100%\ndone\n")
  spec.same({ r.redraws, r.lines }, { 2, 2 })
  r = pty.read(E .. "[?1049h" .. E .. "[2J" .. E .. "[1;1Hvim screen" .. E .. "[?1049l")
  spec.same({ r.alt_screen, r.clears, r.cursor_moves }, { 1, 1, 1 })
end)

spec.test("bash's own carriage returns (before an escape, a newline or the end) are no redraw", function()
  spec.eq(pty.read("echo hi\r\nhi\r\n\27[?2004hroot@x:/app# \27[?2004l\r\r\n").redraws, 0)
end)

spec.test("a window title and a bell are no text", function()
  local r = pty.read(E .. "]0;root@x: /app\7hello\7\n")
  spec.same({ r.text, r.bells }, { "hello\n", 1 })
end)

spec.test("base64 back to the bytes, newlines in it ignored", function()
  spec.eq(pty.base64("G1szMW1y\nZWQbWzBt"), E .. "[31mred" .. E .. "[0m")
end)

spec.run()
