-- The Elixir host as Arock Core sees it. The host binds its ports as functions
-- in __host before each call (db_exec on a SQLite file, clock, now, sleep,
-- fetch, key, sha256, exec on a computer), calls one arock.* function, and discards
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

-- A Moss computer's log (PROJECT.md §15) on the db port, its content kept by the host's SHA-256: alog opened
-- (which makes its tables, or folds the state again when alog's version changed), then one of its methods,
-- e.g. arock.log("append", task, keyword, args, actor), arock.log("rebuild") or arock.log("recall", q).
function arock.log(method, ...)
  local host = arock.host()
  local log = require("alog").open(host.db, { clock = host.clock, hash = __host.sha256 })
  if method then return log[method](log, ...) end
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

-- The post's rules, from rockmail (PROJECT.md §18): pure Lua over facts the host gathered from its store.
--   arock.mail("check", letter, facts, opts) -> "ok", mode | "refused", reason
--   arock.mail("ask", letters, history)      -> the state and the questions Jev reads
--   arock.mail("verdicts", { { letter, answer }, ... }, sure) -> { verdict, ... }, one per letter
local mail = {}

function mail.check(letter, facts, opts) return require("rockmail.checks").letter(letter, facts, opts) end

function mail.ask(letters, history)
  local screen = require("rockmail.screen")
  return screen.state(letters, history), screen.questions(letters)
end

function mail.verdicts(items, sure)
  local screen, out = require("rockmail.screen"), {}
  for i, item in ipairs(items) do out[i] = screen.verdict(item.letter, item.answer, sure) end
  return out
end

function arock.mail(what, ...)
  return mail[what](...)
end

-- Names (Arock's feature manifest): what a manifest.org declares, read by alog, for the node's registry.
--   arock.names("manifest", text) -> { apps = { name, ... }, tools = { name, ... } }, the valid ones only
--   arock.names("address", s)     -> { computer, part, ... } | nil, why
--   arock.names("full", text), arock.names("check", text): below
local names = {}

function names.manifest(text)
  local doc = require("alog.org").parse(text)
  local m = require("alog.manifest").read(doc, { host = true })
  local out = { apps = {}, tools = {} }
  for _, a in ipairs(m.apps) do out.apps[#out.apps + 1] = a.name end
  for _, t in ipairs(m.order) do out.tools[#out.tools + 1] = t end
  return out
end

function names.address(s) return require("alog.org").address(s) end

-- arock.names("full", text) -> JSON { apps = { name, ... }, tools = { tool, ... } } in their order, each tool as
-- alog.manifest reads it (run, description, args, every, on, net, mail, account, ask, publish), the valid ones only
function names.full(text)
  local m = require("alog.manifest").read(require("alog.org").parse(text), { host = true })
  local out = { apps = {}, tools = {} }
  for _, a in ipairs(m.apps) do out.apps[#out.apps + 1] = a.name end
  for _, n in ipairs(m.order) do
    local t = m.tools[n]
    out.tools[#out.tools + 1] = { name = t.name, run = t.run, description = t.description, args = t.args,
      every = t.every, on = t.on, net = t.net, mail = t.mail, account = t.account, ask = t.ask or false,
      publish = t.publish or false }
  end
  return require("ports.json").encode(out)
end

-- arock.names("check", text) -> JSON { "line: why", ... }: a manifest as an agent wrote it, checked as alog checks
-- it (GRANTED is the host's, never an agent's)
function names.check(text)
  local _, errs = require("alog.org_kinds").check("manifest", text)
  local out = {}
  for i, e in ipairs(errs) do out[i] = e.line .. ": " .. e.msg end
  return require("ports.json").encode(out)
end

function arock.names(what, ...)
  return names[what](...)
end

-- The host calls every arock.* function through this, so an error object
-- (ports.call raises tables with __tostring) reaches the host as its text.
function arock.call(name, ...)
  local r = table.pack(pcall(arock[name], ...))
  if not r[1] then error(tostring(r[2]), 0) end
  return table.unpack(r, 2, r.n)
end
