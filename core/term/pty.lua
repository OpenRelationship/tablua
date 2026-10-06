-- The terminal's raw bytes, as columns: what the rendered screen (term's capture) loses. The bytes a program
-- wrote to its pseudo-terminal (tmux's pipe-pane) still carry its colours, its redraws and its control of the screen:
-- red is how compilers, test runners and package managers mark an error; a carriage return with no newline is a
-- progress bar drawn over itself; switching to the alternate screen is a full-screen program (vim, less, top) taking
-- the terminal over; a clear or a cursor move is a program drawing rather than printing.
--
--   local pty = require("term.pty")
--   pty.read(bytes) -> { bytes, lines, escapes, red, yellow, green, bold, redraws, clears, alt_screen, bells,
--                        cursor_moves, text }   red, yellow, green, bold: lines with any text so marked
--   pty.base64(text) -> bytes    the bytes as term's sender sends them
local M = {}

local ESC, BEL = "\27", "\7"

-- the colour an SGR sequence's parameters set the foreground to, or nil when they leave it: "red", "yellow",
-- "green", "other" or "none"; and whether it turns bold on (true), off (false) or leaves it (nil)
local function sgr(params)
  local fg, bold
  local ps = {}
  for p in (params == "" and "0" or params):gmatch("[^;:]*") do if p ~= "" then ps[#ps + 1] = tonumber(p) or 0 end end
  local i = 1
  while i <= #ps do
    local p = ps[i]
    if p == 0 then fg, bold = "none", false
    elseif p == 1 then bold = true
    elseif p == 22 then bold = false
    elseif p == 31 or p == 91 then fg = "red"
    elseif p == 33 or p == 93 then fg = "yellow"
    elseif p == 32 or p == 92 then fg = "green"
    elseif p == 39 then fg = "none"
    elseif (p >= 30 and p <= 37) or (p >= 90 and p <= 97) then fg = "other"
    elseif p == 38 and ps[i + 1] == 5 then
      local c = ps[i + 2] or 0
      fg = (c == 1 or c == 9 or c == 160 or c == 196 or c == 124) and "red" or (c == 3 or c == 11 or c == 220 or c == 226)
        and "yellow" or (c == 2 or c == 10 or c == 34 or c == 46) and "green" or "other"
      i = i + 2
    elseif p == 38 and ps[i + 1] == 2 then
      local r, g, b = ps[i + 2] or 0, ps[i + 3] or 0, ps[i + 4] or 0
      fg = (r > 150 and g < 100 and b < 100) and "red" or (r > 150 and g > 150 and b < 100) and "yellow"
        or (g > 150 and r < 100 and b < 100) and "green" or "other"
      i = i + 4
    end
    i = i + 1
  end
  return fg, bold
end

function M.read(bytes)
  bytes = tostring(bytes or "")
  local r = { bytes = #bytes, lines = 0, escapes = 0, red = 0, yellow = 0, green = 0, bold = 0, redraws = 0, clears = 0,
    alt_screen = 0, bells = 0, cursor_moves = 0 }
  local text, fg, bold = {}, "none", false
  local line = {}   -- what the current line has shown: red, yellow, green, bold
  local function endline()
    for k in pairs(line) do r[k] = r[k] + 1 end
    line = {}
  end
  local i, n = 1, #bytes
  while i <= n do
    local c = bytes:sub(i, i)
    if c == ESC then
      r.escapes = r.escapes + 1
      local nxt = bytes:sub(i + 1, i + 1)
      if nxt == "[" then
        local params, final, upto = bytes:match("^([%d;:?<=>]*)[ -/]*([@-~])()", i + 2)
        if final then
          if final == "m" then
            local f, b = sgr(params)
            if f then fg = f end
            if b ~= nil then bold = b end
          elseif final == "J" and (params == "2" or params == "3") then r.clears = r.clears + 1
          elseif (final == "h" or final == "l") and (params == "?1049" or params == "?47" or params == "?1047") then
            if final == "h" then r.alt_screen = 1 end
          elseif final:find("[ABCDGHf]") then r.cursor_moves = r.cursor_moves + 1 end
          i = upto
        else
          i = i + 2
        end
      elseif nxt == "]" then
        -- an operating system command (a window title): to BEL or ESC \
        local stop = bytes:find("[\7\27]", i + 2)
        i = stop and (bytes:sub(stop, stop) == BEL and stop + 1 or stop + 2) or n + 1
      elseif nxt == "(" or nxt == ")" then
        i = i + 3
      else
        i = i + 2
      end
    elseif c == "\n" then
      r.lines = r.lines + 1
      endline()
      text[#text + 1] = c
      i = i + 1
    elseif c == "\r" then
      -- a carriage return followed by text draws over the line: a progress bar or a spinner (one before a newline,
      -- an escape or the end is a terminal's own line handling, as bash's bracketed paste puts at every prompt)
      if bytes:sub(i + 1, i + 1):find("[^\r\n\27]") then r.redraws = r.redraws + 1 end
      i = i + 1
    elseif c == BEL then
      r.bells = r.bells + 1
      i = i + 1
    else
      if c:find("%S") then
        if fg == "red" or fg == "yellow" or fg == "green" then line[fg] = true end
        if bold then line.bold = true end
      end
      text[#text + 1] = c
      i = i + 1
    end
  end
  endline()
  r.text = table.concat(text)
  return r
end

local B64 = {}
do
  local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  for k = 1, 64 do B64[abc:sub(k, k)] = k - 1 end
end

function M.base64(s)
  s = tostring(s or ""):gsub("[^%w%+/=]", "")
  local out, bits, nbits = {}, 0, 0
  for k = 1, #s do
    local v = B64[s:sub(k, k)]
    if v then
      bits, nbits = bits * 64 + v, nbits + 6
      if nbits >= 8 then
        nbits = nbits - 8
        local byte = math.floor(bits / 2 ^ nbits)
        out[#out + 1] = string.char(byte)
        bits = bits - byte * 2 ^ nbits
      end
    end
  end
  return table.concat(out)
end

return M
