-- A look's judge (Moonsplice's proposal, 2026-10-06): an eye describes the contact sheet and Jev judges it. In studio
-- s2 one model wrote and criticised, and its "kill the tide table panel" became three steps deleting it; now the eye
-- (the writer's model, shown the sheet) only says what it sees, and the judge (Jev, Luna) answers typed questions over
-- the ask, the treatment, each expectation with the engine's verdict, the eye's observations and the sheet as an
-- image. It is never told which move was picked: it judges the comp, not its own pick.
--
--   judge.ask{ ask, treatment?, expects, findings, seen, sheet_b64? } -> state, questions   for jev:decide
--   judge.read(questions, answers, seen?) -> scores { dim = value }, said { next, notes }
--     a dim's score is the expected level (1..5) of the judge's distribution; ask is how near the comp is to the ask;
--     expect:<id> is p that the expectation visibly holds; cut is p that some text is cut off or overlapping; next is
--     the observation that matters most
local prompts = require("studio.prompts")

local M = {}

M.dims = prompts.order
M.near = { "contradicts the ask", "misses most of the ask", "half there", "nearly there", "lands the ask" }
M.shown = 8   -- observations offered as the next note, at most

local function levels(dim)
  return { "1: " .. dim .. " fails outright", "2: weak", "3: acceptable", "4: good", "5: work to show a client" }
end

local function failing(x, findings)
  for _, f in ipairs(findings or {}) do
    -- the engine names the expectation at the end of the detail: "<says>: <why> (expect <id>)"
    local id = f.code == "expect_failed" and tostring(f.detail or ""):match("%(expect ([^)]+)%)%s*$")
    if id == x.id or (f.code == "expect_failed" and f.detail == x.says) then
      return true
    end
  end
  return false
end

function M.ask(o)
  local lines = { "The ask: " .. o.ask }
  if o.treatment then lines[#lines + 1] = "The treatment:\n" .. o.treatment end
  if #(o.expects or {}) > 0 then
    lines[#lines + 1] = "What the ask requires, and what the engine measured:"
    for _, x in ipairs(o.expects) do
      lines[#lines + 1] = ("- %s (the engine: %s)"):format(x.says, failing(x, o.findings) and "failing" or "holding")
    end
  end
  local found = {}
  for _, sev in ipairs({ "error", "warning" }) do
    for _, f in ipairs(o.findings or {}) do
      if (f.severity or "error") == sev and f.code ~= "expect_failed" then
        found[#found + 1] = ("- %s %s%s%s"):format(sev, f.code, (f.id or "") ~= "" and (" on " .. f.id) or "",
          (f.detail or "") ~= "" and (": " .. tostring(f.detail):sub(1, 160)) or "")
      end
    end
  end
  if #found > 0 then
    lines[#lines + 1] = "What the engine measured (errors, then warnings):"
    for i = 1, math.min(12, #found) do lines[#lines + 1] = found[i] end
  end
  if #(o.seen or {}) > 0 then
    lines[#lines + 1] = "What an eye saw on the contact sheet:"
    for i, s in ipairs(o.seen) do lines[#lines + 1] = ("%d. %s"):format(i, s) end
  end
  if o.sheet_b64 then lines[#lines + 1] = "The contact sheet is the image: frames left to right, top to bottom." end
  local text = table.concat(lines, "\n")
  local state = o.sheet_b64 and { { type = "text", text = text },
    { type = "image_url", image_url = { url = "data:image/png;base64," .. o.sheet_b64 } } } or text

  local qs = {}
  for _, d in ipairs(M.dims) do qs[d] = { kind = "score", text = prompts.rubric[d], levels = levels(d) } end
  qs.ask = { kind = "score", text = "How near is the piece to what the ask wants?", levels = M.near }
  -- studio s3 ended with its climax row clipped 74 px into the 3D view, and neither the eye nor the judge said so
  qs.cut = { kind = "noul", text = "In any frame, is any text cut off, clipped by a panel or the frame's edge, or "
    .. "overlapping other text?", yes = "some text is cut off or overlapping", no = "all text is whole and clear" }
  for _, x in ipairs(o.expects or {}) do
    qs["expect:" .. x.id] = { kind = "noul", text = "Is this visibly so in the frames? " .. x.says,
      yes = "it visibly holds", no = "it does not, or cannot be seen" }
  end
  local seen = o.seen or {}
  if #seen >= 2 then
    local options = {}
    for i = 1, math.min(M.shown, #seen) do options["o" .. i] = seen[i] end
    qs.next = { kind = "choice", text = "Which observation matters most to the ask, to act on next?", options = options }
  end
  return state, qs
end

-- the expected level, 1..n, of a score answer
local function expected(q, a)
  if not (a and a.probabilities) then
    for i, l in ipairs(q.levels) do if a and a.score == l then return i end end
    return nil
  end
  local sum, mass = 0, 0
  for i, l in ipairs(q.levels) do
    local p = a.probabilities[l] or 0
    sum, mass = sum + i * p, mass + p
  end
  return mass > 0 and sum / mass or nil
end

function M.read(qs, answers, seen)
  local scores = {}
  for id, q in pairs(qs) do
    local a = answers[id]
    if q.kind == "score" then scores[id] = expected(q, a)
    elseif q.kind == "noul" and a then scores[id] = a.noul end
  end
  seen = seen or {}
  local next
  if qs.next and answers.next then next = qs.next.options[answers.next.choice] end
  if not next and qs.next == nil then next = seen[1] end
  local also = {}
  for _, s in ipairs(seen) do if s ~= next then also[#also + 1] = s end end
  local notes = (next and ("Next: " .. next .. ".") or "") .. (#also > 0 and (" Also seen: " .. table.concat(also, "; ")) or "")
  return scores, { next = next, notes = notes }
end

return M
