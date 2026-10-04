-- How far Jev's sureness can be trusted (PROJECT.md §7.9, §11): the probability Jev gave each verb it picked
-- (memory.lua's Sure rows) set beside how the step turned out. Steps are put in five bands of what Jev said; each
-- band has the share that were complete. Brier is the mean squared gap between what was said and what happened; the
-- calibration error is the bands' gaps weighted by their size. A step the person said no to is left out.
--
--   calibrate.report(steps) -> { n, denied, brier, ece, bands = { { lo, hi, n, said, worked } } }
--   calibrate.render(report) -> text                  steps: memory.steps ({ p, outcome, ... })
local M = {}

M.BANDS = 5

function M.report(steps)
  local r = { n = 0, denied = 0, brier = 0, ece = 0, bands = {} }
  for i = 1, M.BANDS do r.bands[i] = { lo = (i - 1) / M.BANDS, hi = i / M.BANDS, n = 0, said = 0, worked = 0 } end
  for _, s in ipairs(steps) do
    if s.p and s.outcome == "denied" then
      r.denied = r.denied + 1
    elseif s.p and s.outcome then
      local y = s.outcome == "complete" and 1 or 0
      local b = r.bands[math.max(1, math.min(M.BANDS, math.floor(s.p * M.BANDS) + 1))]
      b.n, b.said, b.worked = b.n + 1, b.said + s.p, b.worked + y
      r.n, r.brier = r.n + 1, r.brier + (s.p - y) ^ 2
    end
  end
  if r.n == 0 then return r end
  r.brier = r.brier / r.n
  for _, b in ipairs(r.bands) do
    if b.n > 0 then
      b.said, b.worked = b.said / b.n, b.worked / b.n
      r.ece = r.ece + b.n / r.n * math.abs(b.said - b.worked)
    end
  end
  return r
end

function M.label(b) return ("%.1f-%.1f"):format(b.lo, b.hi) end

function M.render(r)
  local out = {}
  if r.n == 0 then
    out[1] = "No step has a probability from Jev yet."
  else
    out[1] = ("Jev's sureness over %d steps: Brier %.3f, calibration error %.3f."):format(r.n, r.brier, r.ece)
    for i = #r.bands, 1, -1 do
      local b = r.bands[i]
      if b.n > 0 then
        local gap = b.said - b.worked
        local how = gap >= 0.05 and ("too sure by %.2f"):format(gap)
          or gap <= -0.05 and ("not sure enough by %.2f"):format(-gap) or "about right"
        out[#out + 1] = ("%s: %d steps, Jev said %.2f, %.2f worked (%s)"):format(M.label(b), b.n, b.said, b.worked, how)
      end
    end
  end
  if r.denied > 0 then out[#out + 1] = ("%d left out: the person said no."):format(r.denied) end
  return table.concat(out, "\n")
end

return M
