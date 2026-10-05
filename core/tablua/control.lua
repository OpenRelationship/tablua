-- The Mac's "control" checkpoint as rows (schema 7, issue #1 M7): the controls a step chose among on a screen, and
-- which one it chose. TabPFN learns from them which control the request means: a choice whose step worked says the
-- chosen control was the one and a sample of the others were not; a choice whose step did not work says only that
-- the chosen one was not. Also how TabPFN's logged predictions have done, for either head.
--
--   t:controls(task, n, verb, app, controls, chosen)   controls = { { id, role, label, order }, ... }, chosen an id
--   t:control_training() -> { columns, rows, categorical }, labels   one row per example, oldest first
--   t:control_rows(ctx, candidates) -> rows, columns    ctx = { app, verb }: each candidate's row, as training's
--   t:scored(head) -> { n, right, brier }      head "progress" (a move's chance its step helps) or "control"
--   t:ranking(task, head, key) -> { p, ... } | nil   t:ranked(task, head, key, n, ps)   t:rankings(task) -> n
--                                              the rankings a run paid TabPFN for, each by its state's key
local M = {}

M.max = 200        -- controls kept of one reading
M.sampled = 20     -- controls not chosen, kept as not-the-one for a choice that worked
M.columns = { "app", "verb", "role", "label", "order", "seen_ok" }
M.categorical = { 0, 1 }   -- 0-based (ports.tabpfn)

local COLS = { "task", "n", "i", "id", "app", "verb", "role", "label", "ord", "chosen" }

-- each attached file that has the table, others' first, then this one's
local function sources(t)
  local out = {}
  for i = #t.sources, 1, -1 do
    local src = t.sources[i]
    if #t.db:exec(("select 1 from %s.sqlite_master where name = 'tablua_control'"):format(src)) > 0 then
      out[#out + 1] = src
    end
  end
  return out
end

local function key(app, label) return (app or "") .. "\0" .. (label or "") end

return function(T, put)
  function T:controls(task, n, verb, app, controls, chosen)
    self.db:exec("delete from tablua_control where task = ? and n = ?", { task, n })
    for i = 1, math.min(#controls, M.max) do
      local c = controls[i]
      put(self.db, "tablua_control", COLS, { task = task, n = n, i = i, id = tostring(c.id), app = app or "",
        verb = verb or "", role = c.role or "", label = c.label or "", ord = c.order,
        chosen = chosen ~= nil and tostring(c.id) == tostring(chosen) and 1 or 0 })
    end
  end

  -- seen_ok: how often a control of this app with this label was the one that worked, among the choices before
  function T:control_training()
    local rows, labels, counts = {}, {}, {}
    for _, src in ipairs(sources(self)) do
      local steps = self.db:exec(("select c.task, c.n, o.progress from %s.tablua_control c join %s.tablua_outcome o"
        .. " on o.task = c.task and o.n = c.n where c.chosen = 1 order by c.rowid"):format(src, src))
      for _, s in ipairs(steps) do
        local picked, others = nil, {}
        for _, k in ipairs(self.db:exec(("select id, app, verb, role, label, ord, chosen from %s.tablua_control"
          .. " where task = ? and n = ? order by i"):format(src), { s.task, s.n })) do
          if k.chosen == 1 then picked = k else others[#others + 1] = k end
        end
        local function add(k, y)
          rows[#rows + 1] = { k.app, k.verb, k.role, k.label, k.ord or 0, counts[key(k.app, k.label)] or 0 }
          labels[#labels + 1] = y
        end
        add(picked, s.progress)
        if s.progress == 1 then
          local step = math.max(1, math.floor(#others / M.sampled))
          for j = 1, #others, step do
            if (j - 1) / step >= M.sampled then break end
            add(others[j], 0)
          end
          counts[key(picked.app, picked.label)] = (counts[key(picked.app, picked.label)] or 0) + 1
        end
      end
    end
    local columns = {}
    for i, c in ipairs(M.columns) do columns[i] = c end
    return { columns = columns, rows = rows, categorical = M.categorical }, labels
  end

  function T:control_rows(ctx, candidates)
    local counts = {}
    for _, src in ipairs(sources(self)) do
      for _, r in ipairs(self.db:exec(("select c.app, c.label, count(*) as k from %s.tablua_control c join"
        .. " %s.tablua_outcome o on o.task = c.task and o.n = c.n where c.chosen = 1 and o.progress = 1"
        .. " group by c.app, c.label"):format(src, src))) do
        counts[key(r.app, r.label)] = (counts[key(r.app, r.label)] or 0) + r.k
      end
    end
    local rows = {}
    for i, c in ipairs(candidates) do
      rows[i] = { ctx.app or "", ctx.verb or "", c.role or "", c.label or "", c.order or 0,
        counts[key(ctx.app, c.label)] or 0 }
    end
    local columns = {}
    for i, c in ipairs(M.columns) do columns[i] = c end
    return rows, columns
  end

  function T:ranking(task, head, key)
    local r = self.db:exec("select ps from tablua_ranking where task = ? and head = ? and key = ?", { task, head, key })[1]
    if not r then return nil end
    local ps = {}
    for v in r.ps:gmatch("[^,]+") do ps[#ps + 1] = tonumber(v) end
    return ps
  end

  function T:ranked(task, head, key, n, ps)
    local parts = {}
    for i, p in ipairs(ps) do parts[i] = ("%.6f"):format(p) end
    put(self.db, "tablua_ranking", { "task", "head", "key", "n", "ps" },
      { task = task, head = head, key = key, n = n, ps = table.concat(parts, ",") })
  end

  function T:rankings(task)
    return self.db:exec("select count(*) as k from tablua_ranking where task = ?", { task })[1].k
  end

  -- each logged prediction whose outcome has landed: the step took that move, or chose that control
  function T:scored(head)
    local sql = head == "control"
      and [[select p.p, o.progress as y from tablua_prediction p
        join tablua_control c on c.task = p.task and c.n = p.n and c.id = p.move and c.chosen = 1
        join tablua_outcome o on o.task = p.task and o.n = p.n where p.head = 'control']]
      or [[select p.p, o.progress as y from tablua_prediction p
        join tablua_decision d on d.task = p.task and d.n = p.n and d.chosen = p.move
        join tablua_outcome o on o.task = p.task and o.n = p.n where p.head = ?]]
    local n, right, sq = 0, 0, 0
    for _, r in ipairs(self.db:exec(sql, head ~= "control" and { head } or nil)) do
      n, sq = n + 1, sq + (r.p - r.y) ^ 2
      if (r.p >= 0.5) == (r.y == 1) then right = right + 1 end
    end
    return { n = n, right = right, brier = n > 0 and sq / n or nil }
  end
end
