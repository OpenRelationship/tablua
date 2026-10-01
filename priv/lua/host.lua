-- The Elixir host as Arock Core sees it. The host binds its ports as functions
-- in __host before each call (db_exec on a SQLite file, clock, now, sleep,
-- fetch, key, exec on a computer), calls one arock.* function, and discards
-- the state, so nothing here is kept between calls.
arock = {}

-- The ports as plain Lua values: host.db is alog's db port.
function arock.host()
  local h = __host
  return {
    db = { exec = function(_, sql, params) return h.db_exec(sql, params) end },
    clock = h.clock, now = h.now, sleep = h.sleep, fetch = h.fetch, key = h.key,
    -- a computer of its own (PROJECT.md §14), when the host gave one
    exec = h.exec,
  }
end

function arock.store(host)
  host = host or arock.host()
  return require("alog").open(host.db, { clock = host.clock })
end

-- Jev's decisions for the host's own use (the post reading letters, PROJECT.md §14.5): the core's port, so the
-- host asks Jev as the core does. Gives the answers and what the call cost.
function arock.decide(state, questions)
  local host = arock.host()
  local key = host.key("jev")
  if not key then error("no Jev key (OPENROUTER_API_KEY)", 0) end
  local answers, record = require("ports.jev").new(host, { key = key }):decide(state, questions)
  return answers, { cost = record.cost }
end

-- The host calls every arock.* function through this, so an error object
-- (ports.call raises tables with __tostring) reaches the host as its text.
function arock.call(name, ...)
  local r = table.pack(pcall(arock[name], ...))
  if not r[1] then error(tostring(r[2]), 0) end
  return table.unpack(r, 2, r.n)
end
