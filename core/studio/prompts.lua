-- What the writer and the critic are asked, for a comp built as rows (cadence/docs/ROWS.md). The bans and the
-- critic's rubric are Moonsplice's own (cadence/agent/prompts.lua, 2026-10-06), kept word for word so a score means the
-- same thing in both.
--
--   prompts.director(ask, kind) -> chat request            the treatment
--   prompts.move(move, ask, kind, treatment, standing, rows_json, reference?) -> chat request   one move, as tool
--                                  calls; reference is Moonsplice's rows-form API card (cadence/agent/REFERENCE.md),
--                                  given by the host
--   prompts.critic(ask, kind, treatment, sheet_b64, picks) -> chat request, its reply JSON { scores, broken, notes }
--   prompts.scores(text) -> { dim = 1..5 } | nil, why
local json = require("ports.json")

local M = {}

M.bans = [[
Banned defaults (each allowed only if the treatment argues for it): a centred white title over footage;
fade in / fade out as the way things arrive; lower-thirds; drop shadows for legibility; captions with no
speech; stock "pop" entrances; more than two typefaces; colour not taken from the subject; evenly spaced
cuts or beats with no reason; decoration that relates to nothing in the picture.]]

M.rubric = {
  rule = "Can the piece's governing rule be inferred from these frames alone?",
  relationship = "Is every graphic in a stated relationship with the picture (behind, attached to, cut by, measured "
    .. "from, timed to something), rather than floating on it?",
  defaults = "How free of the banned defaults is it? 5 = none present, 1 = several.",
  rhythm = "Do motion and changes across the frames follow a structure rather than even spacing or randomness?",
  memory = "Is there one frame someone would screenshot? 5 = unmistakably, 1 = nothing distinctive.",
  craft = "Type, colour, spacing and legibility at the level of a good studio (no clipped text, no overlaps, "
    .. "intentional palette).",
}
M.order = { "rule", "relationship", "defaults", "rhythm", "memory", "craft" }

M.rows = [[
A comp is rows (msr/1): comp (width, height, duration, fps, ...), node (id, kind, parent, z), prop (id, name, value),
key (id, name, t, value, ease: from the previous key of that prop to this one; t is seconds or a fact reference such
as "beat:12"), motion (path, wiggle, follow, spring, drop), system (a pure function (t, state, q) -> rows, run every
frame after the keys; it reads only through q), asset (src and its derive ops) and fact (what perception found). 3D
things are nodes whose parent is a world node, with Bevy's props (shape, pos, rot, size, material, light). You change
the comp only with patches; each is checked, and one that fails is rejected with why.]]

function M.director(ask, kind)
  return { system = "You are the director of a small studio making a " .. (kind == "game" and "game" or "motion piece")
    .. ". You think before anything is built.\n\n" .. M.bans,
    user = "The ask: " .. ask .. "\n\nWrite the treatment: the premise; the ONE governing rule everything follows; the "
      .. "grammar (what things are, how they move, what they are timed to); the structure in time. Under 250 words.",
    temperature = 0.7 }
end

function M.move(move, ask, kind, treatment, standing, rows_json, reference)
  return { system = "You build a Moonsplice " .. (kind == "game" and "game" or "motion piece") .. " to a treatment, "
      .. "one move at a time.\n\n" .. M.rows .. "\n\n" .. M.bans
      .. (reference and ("\n\nThe engine's reference:\n" .. reference) or ""),
    messages = { { role = "user", content = "The ask: " .. ask .. "\n\nThe treatment:\n" .. (treatment or "(none yet)")
      .. "\n\nWhere the work stands:\n" .. standing .. "\n\nThe comp's rows now:\n" .. rows_json .. "\n\nMake this move: "
      .. move .. ". Call its tool once per patch. When the move needs patches of other kinds to read (a new node's "
      .. "keys, its bind to a beat), make them in the same reply, after it; change nothing the move does not need. Write numbers and booleans as JSON numbers and booleans, never in quotes, in node "
      .. "props and derive ops too (y = 500, not \"500\"; deflicker = true, not \"true\")." } },
    temperature = 0.4 }
end

function M.critic(ask, kind, treatment, sheet_b64, picks)
  local lines, fields = {}, {}
  for i, k in ipairs(M.order) do lines[i] = k .. ": " .. M.rubric[k]; fields[i] = '"' .. k .. '": n' end
  return { messages = { { role = "user", content = {
    { type = "text", text = "You are a demanding creative director reviewing a " .. (kind == "game" and "game (a "
      .. "recording of it playing itself)" or "motion piece") .. ". The ask was: " .. ask .. "\n\n"
      .. (treatment and ("Its treatment:\n" .. treatment .. "\n\n") or "") .. "The contact sheet shows frames at "
      .. table.concat(picks or {}, ", ") .. " seconds, left to right, top to bottom.\n\n" .. M.bans .. "\n\nScore each "
      .. "from 1 to 5 (5 = work you would show a client):\n" .. table.concat(lines, "\n") .. "\n\nReply with one JSON "
      .. "object only: {\"scores\": {" .. table.concat(fields, ", ") .. "}, \"broken\": [\"anything visibly wrong\"], "
      .. "\"notes\": \"the three most important changes, concrete\"}" },
    { type = "image_url", image_url = { url = "data:image/png;base64," .. sheet_b64 } } } } },
    temperature = 0.2 }
end

-- the critic's scores, each a whole number from 1 to 5, every dim present
function M.scores(text)
  local body = tostring(text or ""):match("%b{}")
  local ok, v = pcall(json.decode, body or "")
  if not ok or type(v) ~= "table" or type(v.scores) ~= "table" then return nil, "the critic gave no scores" end
  local out = {}
  for _, k in ipairs(M.order) do
    local s = tonumber(v.scores[k])
    if not s or s < 1 or s > 5 then return nil, "the critic gave no score for " .. k end
    out[k] = s
  end
  return out, v
end

return M
