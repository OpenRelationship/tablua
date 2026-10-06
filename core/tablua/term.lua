-- The terminal as rows (schema 15): every action a step sent to the terminal and the screen it left
-- (tablua_term), and what that screen says went wrong (tablua_event, term.read). Each comes from a source: the
-- computer (real) or a world model that foresaw it before it ran (world, ports.agentworld), in the same columns,
-- so where they part is a query (tablua_surprise): a failure nobody foresaw, or one foreseen that never came. A
-- tabular model reads the step's terminal as features (t:term_features), and learns from the real rows what the
-- world model foresees, so the world model is asked only where the rows leave it unsure.
--
--   t:term(todo, n, i, source, r) -> events   r = { keys, wait, screen, exit?, done, ms?, first_ms?, files?, raw?,
--                                             trace?, passed?, total? } (term's send with where the tests stood, or a
--                                             foreseen screen with no exit); its events read from the screen, what
--                                             was typed from its keys (term.command), the raw bytes' columns from
--                                             raw (term.pty), and each file written as a tablua_file row; from
--                                             trace, what bash ran (ran: each command's first word, M.ran)
--   M.ran(trace) -> "cd,ls,wc"                 read apart from term.command, so the two can be checked one by the other
--   t:term_rows(todo, n?, source?) -> rows    in order
--   t:vector(todo, n, i, v, model?, source?)  a world model's hidden state for the action
--   t:vectors(source?) -> { { todo, n, i, v = { ... } }, ... }   every one kept, in order
--   t:term_features(todo, n) -> { name = number }, last_kind, last_program   how the terminal stood after step n
--   t:surprise(todo, n) -> { unforeseen, unfulfilled, failed_differs }   step n's real against its foreseen
local read = require("term.read")
local command = require("term.command")
local pty = require("term.pty")

local M = {}

M.chars = 20000   -- of a screen kept in a row: its start and end

-- the features t:term_features gives, in order: numbers a tabular model reads, then the one category
M.features = { "commands", "running", "exit", "failed", "errors", "kinds", "repeats", "fails_in_row", "surprise",
  "red", "files", "seconds", "reads" }

local TERM = { "todo", "n", "i", "source", "keys", "wait", "exit", "done", "failed", "ms", "lines", "screen",
  "program", "programs", "reads", "writes", "files", "first_ms", "bytes", "red", "yellow", "green", "redraws",
  "alt_screen", "passed", "total", "trace", "ran" }
local FILE = { "todo", "n", "i", "path", "size" }
local EVENT = { "todo", "n", "i", "source", "k", "kind", "name", "file", "line", "sig", "count", "text" }

local function ends(s, n)
  s = tostring(s or "")
  if #s <= n then return s end
  local half = math.floor(n / 2)
  return s:sub(1, half) .. ("\n[... %d characters left out ...]\n"):format(#s - 2 * half) .. s:sub(-half)
end

local function lines(s)
  local k = 0
  for _ in (tostring(s or "") .. "\n"):gmatch("[^\n]*\n") do k = k + 1 end
  return k
end

-- the program each traced command started: its first word past any NAME=value, as a path's last part; a shell
-- keyword's line (a for, while or case header) started none
local KEYWORD = { ["for"] = true, ["while"] = true, ["until"] = true, ["if"] = true, ["case"] = true,
  ["select"] = true, ["[["] = true, ["(("] = true, ["function"] = true }
function M.ran(trace)
  local out = {}
  for _, c in ipairs(trace or {}) do
    local w
    for word in c:gmatch("%S+") do
      if not word:find("^[%a_][%w_]*=") then w = word break end
    end
    if w and not KEYWORD[w] and not w:find("^%(%(") then
      out[#out + 1] = (w:gsub("^['\"]", ""):gsub("['\"]$", ""):match("[^/]+$") or w)
    end
  end
  return table.concat(out, ",")
end

return function(T, put)
  function T:term(todo, n, i, source, r)
    local events = read.events(r.screen)
    -- a real action failed when it came back with an exit other than 0; a foreseen one when its screen says so
    local failed
    if source == "real" then
      failed = r.exit ~= nil and r.exit ~= 0 and 1 or (r.exit == 0 and 0 or nil)
    else
      failed = #events > 0 and 1 or 0
    end
    local typed = command.parse(r.keys)
    local raw = r.raw and pty.read(r.raw)
    put(self.db, "tablua_term", TERM, { todo = todo, n = n, i = i, source = source, keys = r.keys or "",
      wait = r.wait, exit = r.exit, done = r.done == false and 0 or 1, failed = failed, ms = r.ms,
      lines = lines(r.screen), screen = ends(r.screen, M.chars), program = typed.program,
      programs = table.concat(typed.programs, ","), reads = typed.reads and 1 or 0, writes = #typed.writes,
      files = #(r.files or {}), first_ms = r.first_ms, bytes = raw and raw.bytes, red = raw and raw.red,
      yellow = raw and raw.yellow, green = raw and raw.green, redraws = raw and raw.redraws,
      alt_screen = raw and raw.alt_screen, passed = r.passed, total = r.total,
      trace = r.trace and table.concat(r.trace, "\n"):sub(1, M.chars) or nil, ran = r.trace and M.ran(r.trace) or nil })
    if source == "real" then
      self.db:exec("delete from tablua_file where todo = ? and n = ? and i = ?", { todo, n, i })
      for _, f in ipairs(r.files or {}) do
        put(self.db, "tablua_file", FILE, { todo = todo, n = n, i = i, path = f.path, size = f.size })
      end
    end
    self.db:exec("delete from tablua_event where todo = ? and n = ? and i = ? and source = ?", { todo, n, i, source })
    for k, e in ipairs(events) do
      put(self.db, "tablua_event", EVENT, { todo = todo, n = n, i = i, source = source, k = k, kind = e.kind,
        name = e.name or "", file = e.file or "", line = e.line, sig = e.sig, count = e.count,
        text = (e.text or ""):sub(1, 500) })
    end
    return events
  end

  function T:vector(todo, n, i, v, model, source)
    local parts = {}
    for k, x in ipairs(v) do parts[k] = ("%.6g"):format(x) end
    put(self.db, "tablua_vector", { "todo", "n", "i", "source", "model", "dims", "v" }, { todo = todo, n = n, i = i,
      source = source or "world", model = model or "", dims = #v, v = "[" .. table.concat(parts, ",") .. "]" })
  end

  function T:vectors(source)
    local out = {}
    for _, r in ipairs(self.db:exec("select todo, n, i, v from tablua_vector where source = ? order by todo, n, i",
      { source or "world" })) do
      out[#out + 1] = { todo = r.todo, n = r.n, i = r.i, v = require("ports.json").decode(r.v) }
    end
    return out
  end

  function T:term_rows(todo, n, source)
    local sql, args = "select * from tablua_term where todo = ?", { todo }
    if n then sql, args[#args + 1] = sql .. " and n = ?", n end
    if source then sql, args[#args + 1] = sql .. " and source = ?", source end
    return self.db:exec(sql .. " order by n, i, source", args)
  end

  function T:surprise(todo, n)
    local r = self.db:exec("select coalesce(sum(unforeseen), 0) as unforeseen, coalesce(sum(unfulfilled), 0) as"
      .. " unfulfilled, coalesce(sum(failed_differs), 0) as failed_differs, count(*) as actions from tablua_surprise"
      .. " where todo = ? and n = ?", { todo, n })[1]
    return r
  end

  -- how the terminal stood after step n, from the real rows of every step up to it:
  --   commands      actions sent so far              running     1 when the last one is still running
  --   exit          the last finished one's exit (-1: none yet)   failed  how many of step n's actions failed
  --   errors        step n's events                  kinds       how many kinds of event step n showed
  --   repeats       how many earlier steps showed the signature step n showed most
  --   fails_in_row  steps in a row, to n, with a failed action     surprise    step n's events nobody foresaw
  --                                                                            plus those foreseen that never came
  function T:term_features(todo, n)
    local f = { commands = 0, running = 0, exit = -1, failed = 0, errors = 0, kinds = 0, repeats = 0,
      fails_in_row = 0, surprise = 0, red = 0, files = 0, seconds = 0, reads = 0 }
    local rows = self.db:exec("select n, i, exit, done, failed, program, red, files, ms, reads from tablua_term"
      .. " where todo = ? and source = 'real' and n <= ? order by n, i", { todo, n })
    local last_program = "none"
    local failed_at = {}
    for _, r in ipairs(rows) do
      f.commands = f.commands + 1
      f.running = r.done == 0 and 1 or 0
      if r.exit ~= nil then f.exit = r.exit end
      if r.failed == 1 then failed_at[r.n] = true end
      if r.n == n and r.failed == 1 then f.failed = f.failed + 1 end
      if r.n == n then
        f.red, f.files = f.red + (r.red or 0), f.files + (r.files or 0)
        f.seconds, f.reads = f.seconds + (r.ms or 0) / 1000, f.reads + (r.reads or 0)
      end
      if r.program and r.program ~= "" then last_program = r.program end
    end
    local m = n
    while m >= 1 and failed_at[m] do f.fails_in_row, m = f.fails_in_row + 1, m - 1 end
    local events = self.db:exec("select kind, sig, count from tablua_event where todo = ? and n = ? and source = 'real'"
      .. " order by i, k", { todo, n })
    local kinds, top, last_kind = {}, nil, "none"
    for _, e in ipairs(events) do
      f.errors = f.errors + 1
      if not kinds[e.kind] then kinds[e.kind], f.kinds = true, f.kinds + 1 end
      if not top or e.count > top.count then top = e end
      last_kind = e.kind
    end
    if top then
      f.repeats = self.db:exec("select count(distinct n) as k from tablua_event where todo = ? and n < ? and"
        .. " source = 'real' and sig = ?", { todo, n, top.sig })[1].k
      last_kind = top.kind
    end
    local s = self:surprise(todo, n)
    f.surprise = (s.unforeseen or 0) + (s.unfulfilled or 0)
    return f, last_kind, last_program
  end
end
