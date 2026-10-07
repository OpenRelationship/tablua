-- What the writer and the critic are asked, for a comp built as rows (Moonsplice's .robot/docs/rows.robot). The bans and the
-- critic's rubric are Moonsplice's own (Moonsplice's core/host/prompts.lua, 2026-10-06), kept word for word so a score means the
-- same thing in both.
--
--   prompts.director(ask, kind, comp?) -> chat request     the treatment, within the seed (comp: its brief)
--   prompts.move(move, ask, kind, treatment, standing, comp, card?, sources?) -> chat request   one move, as tool
--                                  calls; comp is the engine's brief (rows --brief), card the sections of Moonsplice's
--                                  API card (Moonsplice's .robot/docs/reference.robot) the move needs, sources the systems' code
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
A comp is rows (msr/1): comp (width, height, duration, fps, ...), node (id, kind, parent, order), prop (id, name, value),
key (id, name, t, value, ease: from the previous key of that prop to this one; t is seconds or a fact reference such
as "beat:12"), motion (path, wiggle, follow, spring, drop), system (a pure function (t, state, q) -> rows, run every
frame after the keys; it reads only through q), asset (src and its derive ops) and fact (what perception found). 3D
things are nodes whose parent is a world node, with Bevy's props (shape, pos, rot, size, material, light). You change
the comp only with patches; each is checked, and one that fails is rejected with why.]]

-- comp: the seed as the engine's brief, its expectations among it. In studio s2 the treatment replaced the seed's tide
-- table with "one moment of type", and the critic then had it deleted (Moonsplice, 2026-10-06)
-- the driving model's system prompt, built as pi builds its own (packages/coding-agent/src/core/system-prompt.ts): a
-- preamble, the tools a line each, the rules, then what the work needs (the bans, the reference's sections by name)
M.tools = {
  brief = "read the comp as it is now, with its expectations and the engine's findings",
  patch = "change the comp with typed moves, several in one call",
  expect = "add an expectation the ask needs that the comp lacks, or withdraw one of yours that was wrong, with why",
  look = "render the contact sheet and see it, with the judge's scores and what the engine measured",
  reference = "read one section of the engine's reference by name",
}
M.tool_order = { "brief", "patch", "expect", "look", "reference" }

M.rules = {
  "Begin with a short treatment as text: the premise, the one governing rule, the grammar (what things are, how "
    .. "they move, what they are timed to) and the structure in time. Then work.",
  "Read the comp with brief before you change it, and again whenever you have lost track of it.",
  "Change the comp only with patch. Put a node with its props, keys and bind in one call. Numbers and booleans "
    .. "unquoted (y = 500, not \"500\").",
  "The comp's expectations are what the piece is: restyle, retime or re-stage what they name; never remove or hide it. "
    .. "Write the ask as expectations of your own, each saying when (at, or t0..t1); one of yours that turns out wrong "
    .. "you withdraw with why, and the judge reads why.",
  "A result that says rejected or broken says why: fix that before anything else. Do not set a prop back and forth.",
  "Look after the changes you want to see, and before you hand in.",
  "When the piece is done, reply without calling a tool and say what you made. A hand-in with errors or failing "
    .. "expectations comes back to you.",
  "Be concise.",
}

function M.system(kind, index)
  local what = kind == "game" and "game" or "motion piece"
  local tools = {}
  for _, name in ipairs(M.tool_order) do tools[#tools + 1] = "- " .. name .. ": " .. M.tools[name] end
  local rules = {}
  for i, r in ipairs(M.rules) do rules[i] = "- " .. r end
  return "You are building a Moonsplice " .. what .. " inside Tablua, a harness that gives you tools to read, change "
    .. "and see it.\n\n<tools>\n" .. table.concat(tools, "\n") .. "\n</tools>\n\n<rules>\n" .. table.concat(rules, "\n")
    .. "\n</rules>\n\n<comp>\n" .. M.rows .. "\n</comp>\n\n<bans>\n" .. M.bans:gsub("^\n", "") .. "\n</bans>"
    .. (index and index ~= "" and ("\n\n<reference>\nThe engine's reference, a section at a time with the reference "
      .. "tool:\n" .. index .. "\n</reference>") or "")
end

function M.director(ask, kind, comp)
  return { system = "You are the director of a small studio making a " .. (kind == "game" and "game" or "motion piece")
    .. ". You think before anything is built.\n\n" .. M.bans,
    user = "The ask: " .. ask .. (comp and ("\n\nThe piece as it stands:\n" .. comp .. "\n\nIts expectations are what the "
      .. "piece is: the treatment works within them. Restyle, retime or re-stage what they name; never replace or "
      .. "remove it.") or "") .. "\n\nWrite the treatment: the premise; the ONE governing rule everything follows; the "
      .. "grammar (what things are, how they move, what they are timed to); the structure in time. Under 250 words.",
    temperature = 0.7 }
end

function M.move(move, ask, kind, treatment, standing, comp, card, sources)
  return { system = "You build a Moonsplice " .. (kind == "game" and "game" or "motion piece") .. " to a treatment, "
      .. "one move at a time.\n\n" .. M.rows .. "\n\n" .. M.bans
      .. (card and ("\n\nThe engine's reference:\n" .. card) or ""),
    messages = { { role = "user", content = "The ask: " .. ask .. "\n\nThe treatment:\n" .. (treatment or "(none yet)")
      .. "\n\nWhere the work stands:\n" .. standing .. "\n\nThe comp now:\n" .. comp
      .. (sources and sources ~= "" and ("\n\nThe systems' source:\n" .. sources) or "") .. "\n\nMake this move: "
      .. move .. ". Call its tool once per patch. When the move needs patches of other kinds to read (a new node's "
      .. "keys, its bind to a beat), make them in the same reply, after it; change nothing the move does not need. Write numbers and booleans as JSON numbers and booleans, never in quotes, in node "
      .. "props and derive ops too (y = 500, not \"500\"; deflicker = true, not \"true\")." } },
    temperature = 0.4 }
end

-- the ask as expectations (rows.robot, "Expectations"): rows the engine checks every run, written once and then fixed
function M.expect(ask, kind, treatment, comp, reference)
  return { system = "You turn the ask for a Moonsplice " .. (kind == "game" and "game" or "motion piece") .. " into "
      .. "expectations the engine checks on every run.\n\n" .. M.rows .. (reference and ("\n\nThe engine's reference:\n"
      .. reference) or ""),
    messages = { { role = "user", content = "The ask: " .. ask .. "\n\nThe treatment:\n" .. (treatment or "(none)")
      .. "\n\nThe comp now (its expectations, if any, are the seed's and stay):\n" .. comp .. "\n\nCall the "
      .. "expect tool once with three to eight rows: what the ask requires that the engine can measure. Name nodes "
      .. "and props in the rows; a node the ask needs that is not there yet may be named by the id a move should give "
      .. "it. Times are seconds inside the comp or facts that exist (beat:N); has takes a string, the others numbers. Each row: id, says "
      .. "(the requirement in words), node; with prop, an op (== ~= > >= < <= has) and a value, at a time (at) or over "
      .. "t0..t1 (holds = \"ever\" for some frame of it). These are fixed once written: nothing later may change them, "
      .. "so write what the ask needs, not how to build it. Write numbers and booleans unquoted." } },
    temperature = 0.3 }
end

function M.critic(ask, kind, treatment, sheet_b64, picks, expects)
  local fixed = ""
  if expects and #expects > 0 then
    local says = {}
    for i, x in ipairs(expects) do says[i] = "- " .. tostring(x.says) end
    fixed = "The ask's expectations are fixed and the engine checks them; they are not yours to drop:\n"
      .. table.concat(says, "\n") .. "\nWhere one names something that should not stay as it is, say restyle, move "
      .. "or retime it, never kill or remove it.\n\n"
  end
  local lines, fields = {}, {}
  for i, k in ipairs(M.order) do lines[i] = k .. ": " .. M.rubric[k]; fields[i] = '"' .. k .. '": n' end
  return { messages = { { role = "user", content = {
    { type = "text", text = "You are a demanding creative director reviewing a " .. (kind == "game" and "game (a "
      .. "recording of it playing itself)" or "motion piece") .. ". The ask was: " .. ask .. "\n\n"
      .. (treatment and ("Its treatment:\n" .. treatment .. "\n\n") or "") .. "The contact sheet shows frames at "
      .. table.concat(picks or {}, ", ") .. " seconds, left to right, top to bottom.\n\n" .. fixed .. M.bans .. "\n\nScore each "
      .. "from 1 to 5 (5 = work you would show a client):\n" .. table.concat(lines, "\n") .. "\n\nReply with one JSON "
      .. "object only: {\"scores\": {" .. table.concat(fields, ", ") .. "}, \"broken\": [\"anything visibly wrong\"], "
      .. "\"notes\": \"the three most important changes, concrete\"}" },
    { type = "image_url", image_url = { url = "data:image/png;base64," .. sheet_b64 } } } } },
    temperature = 0.2 }
end

-- the eye: shown the sheet, it says only what it sees (studio.judge scores; a critic that directs had s2 delete what the
-- ask was about), its reply JSON { observations = { "..." } }
function M.eye(ask, kind, sheet_b64, picks)
  return { messages = { { role = "user", content = {
    { type = "text", text = "You look at a contact sheet of a " .. (kind == "game" and "game playing itself" or
      "motion piece") .. " made for this ask: " .. ask .. "\n\nThe frames are at " .. table.concat(picks or {}, ", ")
      .. " seconds, left to right, top to bottom. Say only what you see, at most eight observations, most important "
      .. "first: what is on screen and where, what is legible and what is not, what changes between frames, what "
      .. "looks broken. Describe; do not recommend, direct or judge the work. Reply with one JSON object only: "
      .. "{\"observations\": [\"...\"]}" },
    { type = "image_url", image_url = { url = "data:image/png;base64," .. sheet_b64 } } } } },
    temperature = 0.2 }
end

-- the eye's observations, or nil and why
function M.observations(text)
  local ok, v = pcall(json.decode, tostring(text or ""):match("%b{}") or "")
  if not ok or type(v) ~= "table" or type(v.observations) ~= "table" then return nil, "the eye gave no observations" end
  local out = {}
  for _, s in ipairs(v.observations) do if type(s) == "string" and s ~= "" then out[#out + 1] = s end end
  if #out == 0 then return nil, "the eye gave no observations" end
  return out
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
