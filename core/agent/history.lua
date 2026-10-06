-- The conversation the agent's two minds share: every turn the person spoke, everything the agent
-- said aloud, and every step it took with what it found, in the order they happened, across requests and across
-- conversations opened and closed, for as long as the host runs. Jev and Mercury read the same text, so whichever
-- runs next knows what was said and done. An answer the person talked over is kept only as far as they heard it.
-- Words the turn dropped as the agent's own echo never reach it.
--
--   local h = history.new()
--   h:begin()              a new request starts (its steps are numbered from 1)
--   h:person(text)  h:rock(text)  h:note(text)  h:step(step)   step = { verb, lines, note?, n }
--   h:cut(played, total?) -> the words heard of the last thing the agent said, which is marked cut off
--                          (played: seconds of it that reached the speaker; total: its length, when known)
--   h:render(name, for_jev) -> text, oldest first; Jev's copy is the newest part that fits M.jev_chars, with
--                          results from earlier requests shortened
--   h:turns(chars?) -> the conversation alone as chat turns { role = "user" | "assistant", content }, oldest first,
--                          the newest that fit `chars` (steps and notes left out: the spoken reply gets those apart)
--   history.heard(text, played, total?) -> the words of text a listener heard after played seconds
--   h.summary              what came before, once the conversation was compacted (compact.lua): read first
local clip = require("agent.clip").clip

local M = {}
M.rate = 14              -- characters a second the voice speaks, for an answer talked over while still being made
M.jev_chars = 16000      -- Jev's accuracy falls as its state fills with what does not bear on the choice (TypeSafe's
                         -- jev-1.13 notes), so it reads the newest part of the conversation, not all that fits
M.mercury_chars = 400000
M.earlier_result = 300   -- a result from an earlier request, as Jev reads it
M.older_result = 1500    -- an older step's result in the current request, as Jev reads it
M.latest_result = 4000   -- the latest step's result, as Jev reads it (Mercury reads it whole)
-- where the writer's copy may start, once the conversation is longer than its budget: only at every cut_every-th
-- entry, so its start (and a server's cached prompt prefix) stays the same for that many entries at a time, where
-- cutting at the newest entries that fit moved the start every step and no cache ever matched (2026-10-06)
M.cut_every = 8

local H = {}
H.__index = H

function M.new() return setmetatable({ entries = {}, request = 0 }, H) end

local function add(h, e) h.entries[#h.entries + 1] = e; return e end
function H:begin() self.request = self.request + 1 end
-- by: "chose" or "typed" when the words were given on a form by hand, not spoken
function H:person(text, by) return add(self, { who = "person", text = text, by = by }) end
function H:rock(text) return add(self, { who = "rock", text = text }) end
function H:note(text) return add(self, { who = "note", text = text }) end
function H:step(step)
  step.who, step.request = "step", self.request
  return add(self, step)
end

-- The words heard: the share of the text that played (of its whole length, or of how long the voice takes to
-- say it), ending at the last whole word.
function M.heard(text, played, total)
  local length = (total and total > 0) and total or (#text / M.rate)
  local share = math.max(0, math.min(1, played / length))
  if share >= 0.98 then return text end
  local upto = math.floor(#text * share)
  local cut = text:sub(1, upto)
  if upto < #text and text:sub(upto + 1, upto + 1):match("%S") then cut = cut:gsub("%S*$", "") end
  return (cut:gsub("[%s,;:]+$", ""))
end

function H:cut(played, total)
  for i = #self.entries, 1, -1 do
    local e = self.entries[i]
    if e.who == "rock" then
      e.cut, e.heard = true, M.heard(e.text, played, total)
      return e.heard
    end
    if e.who == "person" then return nil end
  end
  return nil
end

local function entry_lines(e, name, for_jev, current, last_n)
  if e.who == "person" then return { "Person" .. (e.by and (" (" .. e.by .. " on the form)") or "") .. ": " .. e.text } end
  if e.who == "note" then return { "(" .. e.text .. ")" } end
  if e.who == "rock" then
    if not e.cut then return { name .. ": " .. e.text } end
    if e.heard == "" then return { name .. " began to speak, and the person talked over it at once." } end
    return { name .. " (the person talked over this; they heard only this much): " .. e.heard .. " …" }
  end
  local out = {}
  if e.request == current then
    out[1] = ("  Step %d: %s"):format(e.n, e.verb)
    local keep = for_jev and (e.n < last_n and M.older_result or M.latest_result) or nil
    for _, l in ipairs(e.lines) do out[#out + 1] = "    " .. (keep and clip(l, keep) or l) end
  else
    for _, l in ipairs(e.lines) do
      out[#out + 1] = "  (" .. name .. " did) " .. (for_jev and clip(l, M.earlier_result) or l)
    end
    if #e.lines == 0 then out[1] = "  (" .. name .. " did) " .. e.verb end
  end
  if e.note then out[#out + 1] = "    " .. e.note end
  return out
end

function H:render(name, for_jev)
  local last_n = 0
  for _, e in ipairs(self.entries) do
    if e.who == "step" and e.request == self.request then last_n = math.max(last_n, e.n) end
  end
  local budget = for_jev and M.jev_chars or M.mercury_chars
  local texts, size, first = {}, 0, 1
  for i = #self.entries, 1, -1 do
    local text = table.concat(entry_lines(self.entries[i], name, for_jev, self.request, last_n), "\n")
    if size + #text > budget and next(texts) then first = i + 1 break end
    texts[i] = text
    size = size + #text + 1
    first = i
  end
  -- the writer's copy starts at a fixed cut, the last at or before where the budget allows: up to cut_every - 1
  -- entries over the budget, so the start moves only when it passes the next cut
  if not for_jev and first > 1 then
    first = math.floor((first - 1) / M.cut_every) * M.cut_every + 1
  end
  local out = {}
  if self.summary then out[1] = "(Earlier in this conversation, in short: " .. self.summary .. ")" end
  if first > 1 then out[#out + 1] = ("(the %d earlier entries of the conversation are not shown)"):format(first - 1) end
  for i = first, #self.entries do out[#out + 1] = texts[i] end
  return table.concat(out, "\n")
end

M.turn_chars = 24000   -- the conversation the spoken reply reads, about 6k tokens

function H:turns(chars)
  local out, size = {}, 0
  for i = #self.entries, 1, -1 do
    local e, turn = self.entries[i], nil
    if e.who == "person" then
      turn = { role = "user", content = e.text }
    elseif e.who == "rock" and not (e.cut and e.heard == "") then
      turn = { role = "assistant", content = e.cut and (e.heard .. " …") or e.text }
    end
    if turn then
      size = size + #turn.content
      if size > (chars or M.turn_chars) and #out > 0 then break end
      local last = out[#out]
      if last and last.role == turn.role then last.content = turn.content .. "\n" .. last.content
      else out[#out + 1] = turn end
    end
  end
  local ordered = {}
  for i = #out, 1, -1 do ordered[#ordered + 1] = out[i] end
  if ordered[1] and ordered[1].role == "assistant" then table.remove(ordered, 1) end
  return ordered
end

return M
