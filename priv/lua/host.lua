-- The Elixir host as Arock Core sees it. The host binds its ports as functions
-- in __host before each call (db_exec on a SQLite file, clock, now, sleep,
-- fetch, key, sha256, exec on a computer), calls one arock.* function, and discards
-- the state, so nothing here is kept between calls.
arock = {}

-- The ports as plain Lua values: host.db is arock-log's db port.
function arock.host()
  local h = __host
  return {
    db = { exec = function(_, sql, params) return h.db_exec(sql, params) end },
    clock = h.clock, now = h.now, sleep = h.sleep, fetch = h.fetch, key = h.key, service = h.service,
    -- a computer of its own (PROJECT.md §14), when the host gave one
    exec = h.exec,
  }
end

function arock.store(host)
  host = host or arock.host()
  return require("arock-log").open(host.db, { clock = host.clock })
end

-- A Moss computer's log (PROJECT.md §15) on the db port, its content kept by the host's SHA-256: arock-log opened
-- (which makes its tables, or folds the state again when arock-log's version changed), then one of its methods,
-- e.g. arock.log("append", task, keyword, args, actor), arock.log("rebuild") or arock.log("recall", q).
function arock.log(method, ...)
  local host = arock.host()
  local log = require("arock-log").open(host.db, { clock = host.clock, hash = __host.sha256 })
  if method then return log[method](log, ...) end
end

-- An org file kept on the computer's log (Arock's feature file-kinds, arock-log.org_log): the write checked whole
-- against the file's history and its events appended, or refused by line. Links resolve through the host
-- (__host.resolve: org: addresses on the node, file: on the disk).
--   arock.org(path, text, actor, task) -> the file as the log reads it back | nil, { "line: why", ... }
function arock.org(path, text, actor, task)
  local host = arock.host()
  local log = require("arock-log").open(host.db, { clock = host.clock, hash = __host.sha256 })
  local resolve = __host.resolve and function(target) return __host.resolve(target) end
  local out, errs = require("arock-log.org_log").write(log, path, text, { actor = actor, task = task, resolve = resolve })
  if out then return out end
  local lines = {}
  for i, e in ipairs(errs) do lines[i] = e.line .. ": " .. e.msg end
  return nil, lines
end

-- The models a call uses (PROJECT.md §19 item 6). On a node, Arock's service with the node's token and the
-- computer's person, so the node holds no provider key: one port that decides as Jev, fills and chats as Mercury,
-- and prices and fits as TabPFN, the service picking each model. Elsewhere (a Mac, a test), the providers' own
-- ports with the host's keys, each nil when its key is missing. chat(model, opts) is a filler of the caller's
-- choosing for a comparison; through the service it is the service's own.
function arock.models(host)
  local svc = host.service and host.service()
  if svc then
    local p = require("ports.arock").new(host, { key = svc.key, base = svc.base, person = svc.person })
    return { jev = p, mercury = p, tabpfn = p:tabpfn(), chat = function() return p end }
  end
  local jev, mercury, tabpfn = host.key("jev"), host.key("mercury"), host.key("tabpfn")
  return {
    jev = jev and require("ports.jev").new(host, { key = jev }),
    mercury = mercury and require("ports.mercury").new(host, { key = mercury }),
    tabpfn = tabpfn and require("ports.tabpfn").new(host, { key = tabpfn }),
    chat = function(model, opts)
      local o = { key = assert(jev, "no Jev key (OPENROUTER_API_KEY)"), model = model }
      for k, v in pairs(opts or {}) do o[k] = v end
      return require("ports.chat").new(host, o)
    end,
  }
end

-- Jev's decisions for the host's own use (the post reading letters, PROJECT.md §14.5): the core's port, so the
-- host asks Jev as the core does. Gives the answers and what the call cost.
function arock.decide(state, questions)
  local host = arock.host()
  local jev = arock.models(host).jev
  if not jev then error("no Jev key (OPENROUTER_API_KEY)", 0) end
  local answers, record = jev:decide(state, questions)
  return answers, { cost = record.cost }
end

-- The post's rules, from uspx (once arock-mail; PROJECT.md §18): pure Lua over facts the host gathered from its store.
--   arock.mail("check", letter, facts, opts) -> "ok", mode | "refused", reason
--   arock.mail("route", route, facts)        -> "ok" | "refused", reason
--   arock.mail("ask", letters, history)      -> the state and the questions Jev reads
--   arock.mail("verdicts", { { letter, answer }, ... }, sure) -> { verdict, ... }, one per letter
local mail = {}

function mail.check(letter, facts, opts) return require("uspx.checks").letter(letter, facts, opts) end

function mail.route(route, facts) return require("uspx.checks").route(route, facts) end

function mail.ask(letters, history)
  local screen = require("uspx.screen")
  return screen.state(letters, history), screen.questions(letters)
end

function mail.verdicts(items, sure)
  local screen, out = require("uspx.screen"), {}
  for i, item in ipairs(items) do out[i] = screen.verdict(item.letter, item.answer, sure) end
  return out
end

-- Letters in org (feature file-kinds): a letter is one org entry, read by arock-log and judged by uspx.tasks.
--   arock.mail("letter", sender, recipient, subject, body) -> JSON { text, subject, kind, task, links } | { why }
--   arock.mail("stamp", text, id)                           -> the letter with its :ID: (its own address)
--   arock.mail("reply", task, sender, recipient, named)     -> nil | why (named: { sender, recipient, body })
--   arock.mail("board", letters, me)                        -> the board as org ({ id, sender, recipient, body })
local function top(text)
  local doc = require("arock-log.org").parse(text)
  local tops = {}
  for _, e in ipairs(doc.entries) do if e.level == 1 then tops[#tops + 1] = e end end
  return doc, tops[1], #tops
end

local function set(e, key, value)
  if e.props[key] == nil then e.order[#e.order + 1] = key end
  e.props[key] = value
end

-- a body with no headline is the message under one made of the subject; FROM and TO are the post's to say
function mail.letter(sender, recipient, subject, body)
  local json, org = require("ports.json"), require("arock-log.org")
  local text = string.match(body, "^%s*%*+ ") and body or ("* " .. subject .. "\n" .. body)
  local doc, e, n = top(text)
  if n ~= 1 then return json.encode({ why = "a letter is one org entry: one top headline, its subject" }) end
  for i = #e.order, 1, -1 do
    if e.order[i] == "ID" then table.remove(e.order, i) end
  end
  e.props.ID = nil
  set(e, "FROM", "org:" .. sender)
  set(e, "TO", "org:" .. recipient)
  text = org.render(doc)
  local _, errs = require("arock-log.org_kinds").check("letter", text)
  if #errs > 0 then return json.encode({ why = "line " .. errs[1].line .. ": " .. errs[1].msg }) end
  local links = {}
  for _, entry in ipairs(doc.entries) do
    for _, l in ipairs(entry.links) do
      if string.sub(l.target, 1, 4) == "org:" then links[#links + 1] = l.target end
    end
  end
  local t = require("uspx.tasks").read(e)
  return json.encode({ text = text, subject = e.title, kind = t.kind, task = t.task, links = links })
end

function mail.stamp(text, id)
  local doc, e = top(text)
  set(e, "ID", id)
  return require("arock-log.org").render(doc)
end

function mail.reply(task, sender, recipient, named)
  local entry = named and select(2, top(named.body))
  local n = named and { sender = named.sender, recipient = named.recipient, entry = entry }
  return require("uspx.tasks").check_reply({ task = task }, sender, recipient, n)
end

function mail.board(letters, me)
  local tasks, list = require("uspx.tasks"), {}
  for i, l in ipairs(letters) do
    list[i] = { id = l.id, sender = l.sender, recipient = l.recipient, entry = select(2, top(l.body)) }
  end
  return tasks.agenda(tasks.board(list, me))
end

function arock.mail(what, ...)
  return mail[what](...)
end

-- Names (Arock's feature manifest): what a manifest.org declares, read by arock-log, for the node's registry.
--   arock.names("manifest", text) -> { apps = { name, ... }, tools = { name, ... } }, the valid ones only
--   arock.names("address", s)     -> { computer, part, ... } | nil, why
--   arock.names("full", text), arock.names("check", text): below
local names = {}

function names.manifest(text)
  local doc = require("arock-log.org").parse(text)
  local m = require("arock-log.manifest").read(doc, { host = true })
  local out = { apps = {}, tools = {} }
  for _, a in ipairs(m.apps) do out.apps[#out.apps + 1] = a.name end
  for _, t in ipairs(m.order) do out.tools[#out.tools + 1] = t end
  return out
end

function names.address(s) return require("arock-log.org").address(s) end

-- arock.names("full", text) -> JSON { apps = { name, ... }, tools = { tool, ... } } in their order, each tool as
-- arock-log.manifest reads it (run, description, args, every, on, net, mail, account, ask, publish, from, output), the
-- valid ones only
function names.full(text)
  local m = require("arock-log.manifest").read(require("arock-log.org").parse(text), { host = true })
  local out = { apps = {}, tools = {} }
  for _, a in ipairs(m.apps) do out.apps[#out.apps + 1] = a.name end
  for _, n in ipairs(m.order) do
    local t = m.tools[n]
    out.tools[#out.tools + 1] = { name = t.name, run = t.run, description = t.description, args = t.args,
      every = t.every, on = t.on, net = t.net, mail = t.mail, account = t.account, ask = t.ask or false,
      publish = t.publish or false, from = t.from, output = t.output }
  end
  return require("ports.json").encode(out)
end

-- arock.names("check", text) -> JSON { "line: why", ... }: a manifest as an agent wrote it, checked as arock-log checks
-- it (GRANTED is the host's, never an agent's)
function names.check(text)
  local _, errs = require("arock-log.org_kinds").check("manifest", text)
  local out = {}
  for i, e in ipairs(errs) do out[i] = e.line .. ": " .. e.msg end
  return require("ports.json").encode(out)
end

-- arock.names("template", kind, computer, today) -> what `new task|note|letter|manifest` writes (arock-log.org_kinds)
function names.template(kind, computer, today)
  return require("arock-log.org_kinds").template(kind, { computer = computer, today = today, from = computer })
end

-- arock.names("help", kind) -> `help org [kind]`: the org this computer speaks, and that kind's part
function names.help(kind)
  local kinds = require("arock-log.org_kinds")
  return kind and kinds.KIND_HELP[kind] and kinds.help(kind) or kinds.HELP
end

function arock.names(what, ...)
  return names[what](...)
end

-- The computer's own agent, one step a call (priv/lua/world/run.lua; Moss.Computer.Agent drives it).
function arock.agent(saved, ctx) return require("moss.world.run").step(saved, ctx) end

-- The host calls every arock.* function through this, so an error object
-- (ports.call raises tables with __tostring) reaches the host as its text.
function arock.call(name, ...)
  local r = table.pack(pcall(arock[name], ...))
  if not r[1] then error(tostring(r[2]), 0) end
  return table.unpack(r, 2, r.n)
end
