-- The Elixir host as the core sees it. The host binds its ports as functions
-- in __host before each call (db_exec on the run's SQLite file, clock, now,
-- sleep, fetch, colm, key, exec on the run's computer), calls one volvox.* function, and discards the
-- state. Everything a run knows is in its SQLite file, so nothing here is
-- kept between calls.
--
-- An agent is a function(host) -> { machine, jev, actions, budget?, give_up?,
-- context? }: the coordinator's options without the store, which the host
-- opens on the run's file.
volvox = {}

-- The ports as plain Lua values: host.db is the store's db port, host.run(name)
-- a suite run(src) function over the Colm module `name`.
function volvox.host()
  local h = __host
  return {
    db = { exec = function(_, sql, params) return h.db_exec(sql, params) end },
    clock = h.clock, now = h.now, sleep = h.sleep, fetch = h.fetch, key = h.key,
    -- the run's own computer (PROJECT.md §14), when the host gave it one
    exec = h.exec,
    run = function(name) return function(src) return h.colm(name, src) end end,
  }
end

function volvox.store(host)
  host = host or volvox.host()
  return require("store").open(host.db, { clock = host.clock })
end

local function coordinator(agent, host)
  local opts = agent(host)
  opts.store = volvox.store(host)
  return require("coordinator").new(opts), opts
end

-- The first half of coordinator run: Start Task, then the start state entered
-- with its action. The core has no start of its own yet, so run is called
-- with every state final, which stops it right after the entry.
function volvox.start(agent, task, goal)
  local c = coordinator(agent, volvox.host())
  local final = c.final
  c.final = setmetatable({}, { __index = function() return true end })
  c:run(task, goal)
  c.final = final
  local state = c.store:task(task).state
  return state, final[state] or false
end

-- One coordinator step of a started task: the state it is in now and whether
-- that state is final.
function volvox.step(agent, task)
  local c = coordinator(agent, volvox.host())
  return c:step(task)
end

-- An event from outside the agent (a user's steer, the host's own).
function volvox.append(task, keyword, args, actor)
  return volvox.store():append(task, keyword, args or {}, actor)
end

function volvox.open()
  volvox.store()
  return true
end

function volvox.dump()
  return volvox.store():dump()
end

function volvox.robot()
  return volvox.store():robot()
end

-- A machine from plan.machines.<name> as its state names, from the start
-- along the arrows (answers in the order asked, then the error arrow), then
-- any state no arrow reaches; nil when there is no such machine.
function volvox.machine(name)
  local ok, m = pcall(require, "plan.machines." .. name)
  if not ok or type(m) ~= "table" or not m.states then return nil end
  local order, seen, i = { m.start }, { [m.start] = true }, 1
  local function add(s)
    if s and m.states[s] and not seen[s] then seen[s] = true; order[#order + 1] = s end
  end
  while order[i] do
    local st = m.states[order[i]]
    for _, a in ipairs(st.ask and st.ask.answers or {}) do add(st.on and st.on[a]) end
    add(st.error)
    i = i + 1
  end
  local rest = {}
  for s in pairs(m.states) do if not seen[s] then rest[#rest + 1] = s end end
  table.sort(rest)
  for _, s in ipairs(rest) do order[#order + 1] = s end
  return order
end

-- The host calls every volvox.* function through this, so an error object
-- (ports.call raises tables with __tostring) reaches the host as its text.
function volvox.call(name, ...)
  local r = table.pack(pcall(volvox[name], ...))
  if not r[1] then error(tostring(r[2]), 0) end
  return table.unpack(r, 2, r.n)
end
