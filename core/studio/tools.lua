-- The studio's tools for agent.loop (owner, 2026-10-07: the harness works the way pi does): what the model calls to
-- read, change and see a Moonsplice comp (cadence/docs/ROWS.md). pi gives a coding agent read, edit, write and bash;
-- a comp's are brief (read it), patch (edit it, typed moves, several in one call as pi's edit takes edits[]), expect
-- (add what the ask requires; nothing edits or removes one), look (see it: the contact sheet as an image, the judge's
-- scores and what the engine measured) and reference (one section of the engine's card, read when needed, as pi reads
-- its docs). Each call is a step n of the session's rows; its result says what changed, in words.
--
--   local tools = require("studio.tools").list(s)   s: the session (studio.session), which keeps n, the snapshot and
--                                                    the findings; each tool's result details carry verb and outcome
local json = require("ports.json")
local moves = require("studio.moves")
local judge = require("studio.judge")
local context = require("studio.context")
local studio = require("tablua.studio")

local M = {}

-- the moves a patch carries: every move but treat (the treatment is the model's own text)
M.edits = {}
for _, m in ipairs(moves.order) do if m ~= "treat" then M.edits[#M.edits + 1] = m end end

local function clip(s, n) s = tostring(s or "") return #s > n and (s:sub(1, n) .. "...") or s end
M.max = 50 * 1024   -- a result's text at most, as pi's read cuts at 50 KB

local function counts(findings)
  local e, w = 0, 0
  for _, f in ipairs(findings or {}) do
    if (f.severity or "error") == "error" then e = e + 1 elseif f.severity == "warning" then w = w + 1 end
  end
  return e, w
end

-- errors, then warnings, a line each (info judges nothing)
function M.found(findings, max)
  local out = {}
  for _, sev in ipairs({ "error", "warning" }) do
    for _, f in ipairs(findings or {}) do
      if (f.severity or "error") == sev then
        out[#out + 1] = ("- %s %s%s%s"):format(sev, f.code, (f.id or "") ~= "" and (" on " .. f.id .. ((f.name or "") ~= ""
          and ("." .. f.name) or "")) or "", (f.detail or "") ~= "" and (": " .. clip(f.detail, 200)) or "")
      end
    end
  end
  if max and #out > max then
    local k = #out
    for i = max + 1, k do out[i] = nil end
    out[#out + 1] = ("- and %d more (brief lists them all)"):format(k - max)
  end
  return table.concat(out, "\n")
end

-- a list given as JSON text, or one item where a list belongs (pi's edit takes both the same way)
local function listed(v, single)
  if type(v) == "string" then
    local ok, d = pcall(json.decode, v)
    if ok then v = d end
  end
  if type(v) == "table" and v[1] == nil and single and single(v) then v = { v } end
  return v
end

function M.list(s)
  local t = s.t
  local brief = { name = "brief", description = "Read the comp as it is now: its settings, facts, every node with its "
    .. "props and keys (references resolved), what each system sets, the expectations (ok or FAIL) and the engine's "
    .. "errors and warnings.", parameters = { type = "object", properties = {} },
    execute = function()
      return { content = clip(s.engine:brief(s.comp), M.max), details = { verb = "brief", outcome = "complete" } }
    end }

  local patch = { name = "patch", description = "Change the comp with typed moves, applied in order and checked by "
      .. "the engine; one that fails is rejected with why and the others still land. Put a node with its props, keys "
      .. "and bind in one call.",
    parameters = { type = "object", required = { "moves" }, properties = { moves = { type = "array",
      description = "each a move: { move = <name>, ...its fields }; the moves: " .. table.concat(M.edits, ", "),
      items = { type = "object", required = { "move" }, properties = { move = { type = "string", enum = M.edits } } } } } },
    prepare = function(args)
      args.moves = listed(args.moves, function(v) return v.move ~= nil end)
      return args
    end,
    check = function(args)
      if type(args.moves) ~= "table" or #args.moves == 0 then return nil, "patch needs moves, a list of at least one" end
      return true
    end,
    execute = function(args)
      local good, refused = {}, {}
      for i, m in ipairs(args.moves) do
        local fields = {}
        for k, v in pairs(type(m) == "table" and m or {}) do if k ~= "move" then fields[k] = v end end
        local name = type(m) == "table" and m.move
        local ok, why = moves.check(name, fields)
        if ok and name == "treat" then ok, why = nil, "treat is not a move on the comp; write the treatment as text" end
        if ok then good[#good + 1] = moves.patch(name, fields) else refused[#refused + 1] = ("move %d: %s"):format(i, why) end
      end
      local verb = good[1] and good[1].move or (type(args.moves[1]) == "table" and args.moves[1].move) or "patch"
      if #good == 0 then
        return { content = "Nothing was applied: " .. table.concat(refused, "; "), is_error = true,
          details = { verb = verb, outcome = "no_effect" } }
      end
      local before = s.findings
      local ok, res = pcall(s.engine.patch, s.engine, s.comp, good)
      if not ok then
        return { content = "The engine failed: " .. clip(res, 600), is_error = true, details = { verb = verb, outcome = "broken" } }
      end
      s:snap(s.n, res.findings or {})
      for i, p in ipairs(res.applied or {}) do
        t:action{ todo = s.todo, n = s.n, i = i, cmd = json.encode(p), op = p.move,
          target = p.id or (p.node and p.node.id) or (p.asset and p.asset.id) or p.system or p.name or "" }
      end
      local outcome = res.digest_before ~= res.digest_after and studio.outcome(before, s.findings, res.touched or {})
        or "no_effect"
      for _, r in ipairs(res.rejected or {}) do refused[#refused + 1] = clip(r.why, 300) end
      local e, w = counts(s.findings)
      local lines = { ("%d applied, %d rejected%s. Outcome: %s."):format(#(res.applied or {}), #refused,
        #refused > 0 and (": " .. table.concat(refused, "; ")) or "", outcome) }
      -- the engine's delta when it gives one (closed and opened findings), else the snapshots'; the undo marks are ours
      local changed = context.changes(t, s.todo, s.n)
      if res.delta and res.delta.line then changed = changed and changed:match("(undoes .+)$") end
      lines[#lines + 1] = changed
      if outcome == "broken" then lines[#lines + 1] = M.found(s.findings, 8) end
      return { content = table.concat(lines, "\n"), is_error = #(res.applied or {}) == 0 or nil,
        details = { verb = verb, outcome = outcome, applied = #(res.applied or {}), rejected = #refused,
          state = res.state and res.state.line and (res.state.line .. "; step " .. s.n) or nil,
          delta = res.delta and res.delta.line or nil, errors = e, warnings = w } }
    end }

  local expect = { name = "expect", description = "Add expectations: what the ask requires, as rows the engine checks "
      .. "every run. Each row: id, says (the requirement in words), node; with prop, an op (== ~= > >= < <= has) and a "
      .. "value, at a time (at) or over t0..t1 (holds = ever for some frame of it). Added once and fixed: none is ever "
      .. "edited or removed.", parameters = moves.expect_tool()["function"].parameters,
    prepare = function(args)
      args.rows = listed(args.rows, function(v) return v.id ~= nil end)
      return args
    end,
    execute = function(args)
      local good, refused = {}, {}
      for _, x in ipairs(type(args.rows) == "table" and args.rows or {}) do
        local ok, why = moves.check_expect(x)
        if ok then good[#good + 1] = x else refused[#refused + 1] = why end
      end
      if #good == 0 then
        return { content = "No expectation was added: " .. table.concat(refused, "; "), is_error = true,
          details = { verb = "expect", outcome = "no_effect" } }
      end
      local ok, res = pcall(s.engine.expect, s.engine, s.comp, good)
      if not ok then return { content = "The engine failed: " .. clip(res, 600), is_error = true,
        details = { verb = "expect", outcome = "broken" } } end
      s:snap(s.n, res.findings)
      for _, r in ipairs(res.rejected or {}) do refused[#refused + 1] = clip(r.why, 300) end
      return { content = ("%d added, %d rejected%s. %s"):format(#(res.added or {}), #refused, #refused > 0
        and (": " .. table.concat(refused, "; ")) or "", context.changes(t, s.todo, s.n) or "No error opened or closed."),
        details = { verb = "expect", outcome = #(res.added or {}) > 0 and "complete" or "no_effect",
          state = res.state and res.state.line and (res.state.line .. "; step " .. s.n) or nil } }
    end }

  local look = { name = "look", description = "Render the comp's contact sheet and see it (the image), with the "
      .. "judge's scores and what the engine measured. Look after the changes you want to see.",
    parameters = { type = "object", properties = {} },
    execute = function()
      local sheet = s.engine:sheet(s.comp, s.sheet)
      s.render_s = sheet.seconds
      local b64 = s.exec("base64 < '" .. s.sheet:gsub("'", [['\'']]) .. "' | tr -d '\\n'", 60)
      if not b64 or b64.code ~= 0 then error("could not read the contact sheet", 0) end
      local lines = { ("The contact sheet: frames at %s s, left to right, top to bottom (the image after this).")
        :format(table.concat(sheet.picks or {}, ", ")) }
      if s.judge then
        local expects = t:comp_rows(s.todo, s.snapped or 0).tables.expect or {}
        local state, qs = judge.ask{ ask = s.ask, treatment = s.treatment, expects = expects, findings = s.findings,
          seen = {}, sheet_b64 = b64.stdout }
        local okj, answers = pcall(s.judge.decide, s.judge, state, qs)
        if okj then
          local scores = judge.read(qs, answers, {})
          t:scores(s.todo, s.n, "critic", scores)
          s.critic, s.looked = { scores = scores }, s.digest
          local d = {}
          for _, k in ipairs(judge.dims) do d[#d + 1] = ("%s %.1f"):format(k, scores[k] or 0) end
          lines[#lines + 1] = ("The judge, 1 to 5: %s; nearness to the ask %.1f. Chance some text is cut off or "
            .. "overlapping: %.2f."):format(table.concat(d, ", "), scores.ask or 0, scores.cut or 0)
          s.judged = lines[#lines]
          local seen = {}
          for _, x in ipairs(expects) do
            local p = scores["expect:" .. x.id]
            if p then seen[#seen + 1] = ("%s %.2f"):format(x.id, p) end
          end
          if #seen > 0 then lines[#lines + 1] = "Chance each expectation visibly holds: " .. table.concat(seen, ", ") .. "." end
        else
          lines[#lines + 1] = "The judge could not score it: " .. clip(answers, 200)
        end
      else
        s.looked = s.digest
      end
      local found = M.found(s.findings, 12)
      lines[#lines + 1] = found ~= "" and ("What the engine measured:\n" .. found) or "The engine found no errors or warnings."
      return { content = table.concat(lines, "\n"), image = b64.stdout, details = { verb = "look", outcome = "complete" } }
    end }

  local reference = { name = "reference", description = "Read one section of the engine's reference by name (the "
      .. "system prompt lists them).", parameters = { type = "object", required = { "section" },
      properties = { section = { type = "string" } } },
    execute = function(args)
      local text, why = context.section(s.reference, args.section)
      if not text then error(why, 0) end
      return { content = text, details = { verb = "reference", outcome = "complete" } }
    end }

  return { brief, patch, expect, look, reference }
end

return M
