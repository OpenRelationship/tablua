-- Moonsplice as Tablua's world (owner, 2026-10-06; cadence/docs/ROWS.md): the agent builds a game or a video as a
-- comp of rows, one typed patch move at a time. Jev decides the move, the writer (MiniMax M3) fills it as tool calls,
-- the engine applies and checks it, and the step's outcome comes from the findings; look renders a contact sheet the
-- critic scores. Every step leaves the comp, its findings and the scores as rows of the sheet (tablua.studio).
--
--   local w = require("studio.world").new{ engine, writer, critic, tablua, comp, sheet, ask, kind?, exec, reference?,
--                                          log? }   reference: Moonsplice's rows-form API card, for the writer
--     engine: ports.moonsplice (or the Studio's session with the same methods); writer, critic: ports.chat;
--     tablua: the run's handle; comp: the comp's .lua path; sheet: where look writes its contact sheet;
--     exec: the host's command (reads the sheet as base64)
--   agent.new(env, w)      env.tablua = the same handle; env.learn with step = studio.features.learner(t)
--
-- Stages: treating (no treatment yet), building (no nodes, or errors open), polishing (no errors). Moves allowed:
-- treat while treating; every patch move after; look once the comp has changed since the last look; answer once a
-- look scored the comp as it is. Open errors hold neither back: the decider reads them in the state and decides.
local checkpoint = require("agent.checkpoint")
local json = require("ports.json")
local moves = require("studio.moves")
local features = require("studio.features")
local prompts = require("studio.prompts")
local studio = require("tablua.studio")

local M = {}

M.edits = { "add_node", "set_prop", "add_key", "move_key", "drop_key", "bind", "add_system", "edit_system", "derive",
  "remove" }
M.look = "Render a contact sheet and have the critic score it (once the comp changed since the last look)."
M.answer = "Hand the piece in as it is now, scored by the last look. Open errors go with it."
M.shown = 12   -- open findings shown in the state

-- the stages whose every decision TabICL ranks, with env.rank or env.shadow
checkpoint.ranked.building, checkpoint.ranked.polishing = true, true

local function clip(s, n) s = tostring(s or "") return #s > n and (s:sub(1, n) .. "...") or s end

-- a chat call, asked once more afresh when the model reasoned to its limit and said nothing (M3 spent 129k tokens
-- on one derive in studio s1 and answered nothing): ok, text, record
local function ask(port, req)
  local ok, text, record = pcall(port.chat, port, req)
  if not ok and tostring(text):find("said nothing", 1, true) then ok, text, record = pcall(port.chat, port, req) end
  return ok, text, record
end

function M.new(o)
  local t = assert(o.tablua, "studio world needs the run's tablua handle")
  local w = { tools = {}, o = o, digest = nil, looked = nil, findings = {} }
  for _, m in ipairs(moves.order) do w.tools[#w.tools + 1] = { name = m, what = moves.what[m] } end
  w.tools[#w.tools + 1] = { name = "look", what = M.look }

  -- the comp as it stands now, as step n's snapshot (n = 0 before any step)
  local function snap(todo, n, findings)
    local rows = o.engine:rows(o.comp)
    t:comp(todo, n, rows)
    w.digest, w.snapped = rows.digest, n
    if not findings then
      findings = o.engine:lint(o.comp)
      for _, f in ipairs(o.engine:check(o.comp)) do findings[#findings + 1] = f end
    end
    t:findings(todo, n, findings)
    w.findings = findings
    return rows
  end

  local function errors()
    local k = 0
    for _, f in ipairs(w.findings) do if (f.severity or "error") == "error" then k = k + 1 end end
    return k
  end

  local function nodes(req)
    return #t.db:exec("select 1 from tablua_msr_node where todo = ? and n = (select max(n) from tablua_msr_node "
      .. "where todo = ?)", { req.todo, req.todo })
  end

  local function stage(req)
    if not req.treatment then return "treating" end
    if nodes(req) == 0 or errors() > 0 then return "building" end
    return "polishing"
  end

  -- the comp before any step, taken at the first decision
  local function start(req) if not w.digest then snap(req.todo, 0) end end

  -- pass: the share of seven checks that hold, the gate (no errors) and each of the critic's six at 3 or more on the
  -- comp as it is now (a score on an earlier version holds none)
  local function pass()
    local held = errors() == 0 and 1 or 0
    if w.critic and w.looked == w.digest then
      for _, k in ipairs(prompts.order) do if (w.critic.scores[k] or 0) >= 3 then held = held + 1 end end
    end
    return held / 7
  end
  M.pass = pass

  function w.allowed(_, req)
    start(req)
    req.stage = stage(req)
    if req.stage == "treating" then return { "treat" } end
    local out = {}
    for _, m in ipairs(M.edits) do out[#out + 1] = m end
    -- a look whenever the comp changed since the last: findings a step cannot clear (a contrast measured on pixels)
    -- held every look and answer back in studio trial 1, and the agent could only go on patching
    if w.looked ~= w.digest then out[#out + 1] = "look" end
    return out
  end

  function w.question(a)
    local req = a.req
    start(req)
    local n = #req.steps + 1
    features.record(t, req.todo, n, features.read(t, req.todo, n, { game = o.kind == "game" and 1 or 0,
      render_s = w.render_s or -1 }))
    local options = {}
    for _, m in ipairs(w.allowed(a, req)) do options[m] = m == "look" and M.look or moves.what[m] end
    if w.looked and w.looked == w.digest then options.answer = M.answer end
    return { kind = "choice", options = options,
      text = "Which move should the studio make next on the comp? Read the ask, the treatment, the open findings and "
        .. "the critic's scores." }
  end

  local function standing(req)
    local s = { ("Ask (%s): %s"):format(o.kind or "video", o.ask),
      req.treatment and ("Treatment: " .. clip(req.treatment, 600)) or "Treatment: none yet.",
      ("Steps so far: %d. Stage: %s."):format(#req.steps, req.stage or stage(req)) }
    local kinds = t.db:exec("select kind, count(*) as c from tablua_msr_node where todo = ? and n = (select max(n) from "
      .. "tablua_msr_node where todo = ?) group by kind order by kind", { req.todo, req.todo })
    local parts = {}
    for _, r in ipairs(kinds) do parts[#parts + 1] = r.c .. " " .. r.kind end
    s[#s + 1] = "Comp: " .. (#parts > 0 and table.concat(parts, ", ") or "no nodes yet") .. "."
    s[#s + 1] = ("Open findings: %d (%d errors)."):format(#w.findings, errors())
    for i = 1, math.min(M.shown, #w.findings) do
      local f = w.findings[i]
      s[#s + 1] = ("  %s %s %s%s: %s"):format(f.tier or "lint", f.severity or "error", f.code, f.id ~= "" and f.id
        and (" on " .. f.id .. (f.name and f.name ~= "" and ("." .. f.name) or "")) or "", clip(f.detail, 160))
    end
    if w.critic then
      local d = {}
      for _, k in ipairs(prompts.order) do d[#d + 1] = k .. " " .. w.critic.scores[k] end
      s[#s + 1] = ("Critic%s: %s. %s"):format(w.looked == w.digest and "" or " (on an earlier version)",
        table.concat(d, ", "), clip(w.critic.notes, 500))
    end
    local last = req.steps[#req.steps]
    if last then s[#s + 1] = ("Last step: %s -> %s. %s"):format(last.verb, tostring(last.outcome), clip(last.note, 400)) end
    return table.concat(s, "\n")
  end

  -- Jev reads the standing, TabICL's ranking when shown, and the newest contact sheet as an image: the Decisions API
  -- reads content parts in state (a 64 px red square scored red 1.00 there, 0.03 as text alone; 2026-10-06)
  function w.state(a, req, for_jev)
    local s = standing(req)
    local card = for_jev and checkpoint.card(req, a.env)
    if card then s = s .. "\n" .. card end
    if not (for_jev and w.sheet_b64) then return s end
    return { { type = "text", text = s .. "\nThe newest contact sheet" .. (w.looked == w.digest and "" or
      " (of an earlier version)") .. " is the image." },
      { type = "image_url", image_url = { url = "data:image/png;base64," .. w.sheet_b64 } } }
  end

  function w.think(_, req)
    return { system = "You advise a small studio.", user = standing(req) .. "\nWhat matters most now? Two sentences." }
  end
  function w.ask(a, req) return w.think(a, req) end
  function w.form(written) return { question = written } end

  local function treat(req, step)
    local ok, text = ask(o.writer, prompts.director(o.ask, o.kind))
    if not ok or not text or text == "" then step.outcome, step.note = "broken", "the director failed: " .. clip(text, 200) return end
    req.treatment = text
    step.outcome, step.note = "complete", "treatment: " .. clip(text:gsub("\n", " "), 200)
  end

  local function look(req, step, n)
    local ok, sheet = pcall(o.engine.sheet, o.engine, o.comp, o.sheet)
    if not ok then step.outcome, step.note = "broken", "render failed: " .. clip(sheet, 300) return end
    w.render_s = sheet.seconds
    local b64 = o.exec("base64 < '" .. o.sheet:gsub("'", [['\'']]) .. "' | tr -d '\\n'", 60)
    if not b64 or b64.code ~= 0 then step.outcome, step.note = "broken", "could not read the sheet" return end
    local okc, text = ask(o.critic, prompts.critic(o.ask, o.kind, req.treatment, b64.stdout, sheet.picks))
    local scores, said = prompts.scores(okc and text)
    if not scores then step.outcome, step.note = "broken", tostring(said) .. ": " .. clip(text, 200) return end
    t:scores(req.todo, n, "critic", scores)
    -- notes asked as text come back as a list too (M3, studio s2)
    local notes = type(said.notes) == "table" and table.concat(said.notes, "; ") or said.notes
    w.critic, w.looked, w.sheet_b64 = { scores = scores, notes = notes }, w.digest, b64.stdout
    step.outcome, step.note = "complete", "critic: " .. clip(notes, 300)
  end

  local function edit(req, step, n, move)
    -- the newest snapshot, not step n - 1's: treat and look take none (studio s2: a key after a look saw an empty comp
    -- and guessed the node buoy)
    local rows = t:comp_rows(req.todo, w.snapped or 0)
    -- the comp's rows and the facts its assets gave (beat:N, word:...), so a bind names one that exists
    local req_w = prompts.move(move, o.ask, o.kind, req.treatment, standing(req),
      json.encode({ tables = rows.tables, derived = rows.derived }), o.reference)
    -- the chosen move first, then the others it may need in the same reply (an add_node with its keys): in studio s1
    -- a node and its keys took a step each, and seventeen steps changed little (Moonsplice's read, 2026-10-06)
    local offered = { [move] = true }
    req_w.tools, req_w.tool_choice = { moves.tool(move) }, "required"
    for _, m in ipairs(M.edits) do
      if m ~= move then offered[m] = true req_w.tools[#req_w.tools + 1] = moves.tool(m) end
    end
    -- one call that reasons briefly: M3 at its default effort took 50 to 280 s a step, and once 129k tokens
    req_w.reasoning_effort = "low"
    local ok, _, record = ask(o.writer, req_w)
    if not ok then step.outcome, step.note = "broken", "the writer failed: " .. clip(_, 300) return end
    local patches, refused, chosen = {}, {}, false
    for _, c in ipairs(record.tool_calls or {}) do
      local name = c["function"] and c["function"].name
      local okj, args = pcall(json.decode, c["function"] and c["function"].arguments or "")
      local good, why = moves.check(name, okj and args or nil)
      if good and not offered[name] then good, why = nil, tostring(name) .. " is not a patch move" end
      if good then patches[#patches + 1] = moves.patch(name, args) chosen = chosen or name == move
      else refused[#refused + 1] = why end
    end
    if not chosen then patches = {} refused[#refused + 1] = "no " .. move .. " among the calls" end
    if #patches == 0 then
      step.outcome, step.note = "no_effect", "the writer made no valid " .. move .. " patch" .. (#refused > 0
        and (": " .. table.concat(refused, "; ")) or "")
      return
    end
    local before = w.findings
    local okp, res = pcall(o.engine.patch, o.engine, o.comp, patches)
    if not okp then step.outcome, step.note = "broken", "the patch failed: " .. clip(res, 300) return end
    snap(req.todo, n, res.findings or {})
    for i, p in ipairs(res.applied or {}) do
      t:action{ todo = req.todo, n = n, i = i, cmd = json.encode(p), op = p.move or move, target = (p.id or p.name or "") }
    end
    local changed = res.digest_before ~= res.digest_after
    step.outcome = changed and studio.outcome(before, w.findings, res.touched or {}) or "no_effect"
    local why = {}
    for _, r in ipairs(res.rejected or {}) do why[#why + 1] = clip(r.why, 160) end
    for _, r in ipairs(refused) do why[#why + 1] = r end
    step.note = ("%d applied, %d rejected%s; %d findings open (%d errors)"):format(#(res.applied or {}),
      #(res.rejected or {}) + #refused, #why > 0 and (": " .. table.concat(why, "; ")) or "", #w.findings, errors())
  end

  function w.act(_, req, verb, step)
    local n = #req.steps + 1
    if verb == "treat" then treat(req, step)
    elseif verb == "look" then look(req, step, n)
    elseif moves.schema[verb] then edit(req, step, n, verb)
    else step.outcome, step.note = "broken", "no such move " .. tostring(verb) end
    step.lines[#step.lines + 1] = verb .. ": " .. tostring(step.note)
    req.stage, req.pass = stage(req), pass()
  end

  return w
end

return M
