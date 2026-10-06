-- A terminal session as turns in Qwen-AgentWorld's own format, the one its training samples are in
-- (AgentWorldBench's terminal domain): the first turn carries the screen as it stood, each turn's action is a JSON
-- array of { keystrokes, duration }, and each observation is the screen after it, under **Environment Observation:**.
-- What the session did is a conversation of these turns, and the world model's reply to one more action is the
-- screen it foresees, in a <predicted_observation> block after whatever reasoning it gives first.
--
--   local turns = require("term.turns")
--   turns.action(keys, wait) -> "**Action:**\n```json\n[ ... ]\n```"
--   turns.user(k, keys, wait, state?) -> "### Turn k\n" (with **Current State:** when state is given) .. action
--   turns.observation(screen) -> "**Environment Observation:**\n" .. screen
--   turns.messages(session, keys, wait) -> { { role, content }, ... }   the session so far and the action to foresee
--        session = { opening = the screen before the first turn, turns = { { keys, wait, screen }, ... } }
--   turns.observed(reply) -> screen | nil   the foreseen screen, out of the model's reply: its <predicted_observation>
--                                           block, or with none the fenced block or lines that begin at a prompt
--   turns.window, turns.screen_chars        the newest turns sent (cut only every turns.cut_every), and how much of
--                                           each screen
local json = require("ports.json")

local M = {}

M.window = 40
M.cut_every = 10
M.screen_chars = 4000
-- the terminal's visible height: what one observation shows, as in the training samples ("Limited visible lines
-- (typically 40 lines), older output scrolls off"). Fed whole screens, the model foresaw whole files, 30 to 200
-- seconds a call (overfull-hbox, 2026-10-06); fed the visible screen, it foresees one.
M.screen_lines = 40
M.state_lines = M.screen_lines

-- a wait as the samples write a duration: 0.1, 1.0, 60.0
local function duration(w)
  w = tonumber(w) or 1
  if w == math.floor(w) then return ("%.1f"):format(w) end
  return tostring(w)
end

function M.action(keys, wait)
  return "**Action:**\n```json\n[\n  {\n    \"keystrokes\": " .. json.encode(tostring(keys or ""))
    .. ",\n    \"duration\": " .. duration(wait) .. "\n  }\n]\n```"
end

function M.user(k, keys, wait, state)
  local s = "### Turn " .. k .. "\n"
  if state then s = s .. "**Current State:**\n" .. state .. "\n\n" end
  return s .. M.action(keys, wait)
end

-- the start and end of a long screen
local function ends(s, n)
  s = tostring(s or "")
  if #s <= n then return s end
  local half = math.floor(n / 2)
  return s:sub(1, half) .. "\n...\n" .. s:sub(-half)
end

local tail_lines

function M.observation(screen)
  return "**Environment Observation:**\n" .. ends(tail_lines(screen, M.screen_lines), M.screen_chars)
end

function tail_lines(s, n)
  local lines = {}
  for l in (tostring(s or "") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
  while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
  local from = math.max(1, #lines - n + 1)
  return table.concat(lines, "\n", from)
end

function M.messages(session, keys, wait)
  local all = session.turns or {}
  -- the oldest turn sent moves only every cut_every turns (up to cut_every - 1 turns past the window), so the
  -- prompt's start (and the server's cached prefix) stays the same between
  local first = math.max(1, #all - M.window + 1)
  if first > 1 then
    first = math.floor((first - 1) / M.cut_every) * M.cut_every + 1
  end
  local state = first == 1 and (session.opening or "") or tail_lines(all[first - 1].screen, M.state_lines)
  local out, k = {}, 0
  for i = first, #all do
    local t = all[i]
    k = k + 1
    out[#out + 1] = { role = "user", content = M.user(k, t.keys, t.wait, k == 1 and state or nil) }
    out[#out + 1] = { role = "assistant", content = M.observation(t.screen) }
  end
  out[#out + 1] = { role = "user", content = M.user(k + 1, keys, wait, k == 0 and state or nil) }
  return out
end

-- a shell prompt at a line's start: user@host:path# or $
local PROMPT = "^[%w%._%-]+@[%w%._%-]+:[^\n]-[#$]"

local function strip(s) return (tostring(s or ""):gsub("^%s*\n", ""):gsub("%s+$", "")) end

function M.observed(reply)
  reply = tostring(reply or ""):gsub("<think>.-</think>", "")
  local last
  for block in reply:gmatch("<predicted_observation>(.-)</predicted_observation>") do last = block end
  if not last then last = reply:match("<predicted_observation>(.*)$") end
  if not last then last = reply:match("%*%*Environment Observation:%*%*\n(.*)$") end
  -- with thinking off it sometimes gives the screen with no tag (2026-10-06): the last fenced block that holds a
  -- prompt, or else the lines from the first one that starts with a prompt to the end
  if not last then
    for block in reply:gmatch("```[%w]*\n(.-)```") do
      if block:find(PROMPT) or block:find("\n" .. PROMPT:sub(2)) then last = block end
    end
    if not last then
      local open = reply:match("```[%w]*\n(.*)$")
      if open and (open:find(PROMPT) or open:find("\n" .. PROMPT:sub(2))) then last = open end
    end
  end
  if not last then
    local at = reply:find(PROMPT) or reply:find("\n" .. PROMPT:sub(2))
    if at then last = reply:sub(at):gsub("```%s*$", "") end
  end
  if not last then return nil end
  last = strip(last)
  return last ~= "" and last or nil
end

return M
