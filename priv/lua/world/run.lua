-- The computer's agent, one step a call (Moss.Computer.Agent drives it; core/agent over moss.world).
-- tv-labs lua keeps no garbage collector, so a run is not one long call: each call builds the agent again from
-- what the last one saved (the request and the conversation, as JSON), takes one step (Jev decides, Mercury fills,
-- the computer runs it, the step is recorded) and saves again. Every decision is a Decide row on the computer's
-- log and every step's outcome an Outcome row, both at the step's address (the task's, then /step/<n>), so a
-- decision is joined to how it turned out; each call to Jev, Mercury and TabPFN is counted with what it cost.
--
--   run.step(saved_json | nil, ctx) -> kind ("act" | "wait" | "done" | "blocked"), detail, saved_json, counts
--   ctx = { task, at, help, procedures, filler?, decider?, steps?, learn?, per_run? }    host: __host.exec, agent_facts(at), agent_events(), ...
--   filler: an OpenRouter model in Mercury's place; decider: a System One model in Jev's; each to compare
local agent = require("agent")
local memory = require("agent.memory")
local learn = require("agent.learn")
local json = require("ports.json")

local M = {}

-- Inception's prices for mercury-2.5, USD per token (its /v1/models, 2026-10-02): input, cached input, output
M.mercury_price = { 0.04e-6, 0.004e-6, 0.15e-6 }

local function mercury_cost(record)
  local u, p = record and record.usage or {}, M.mercury_price
  local cached = u.cached or 0
  return ((u.prompt or 0) - cached) * p[1] + cached * p[2] + (u.completion or 0) * p[3]
end

-- A port whose every call is counted, with what it cost (Jev's record carries its own cost).
local function counted(port, name, counts)
  if not port then return nil end
  return setmetatable({}, { __index = function(_, k)
    local f = port[k]
    if type(f) ~= "function" then return f end
    return function(_, ...)
      counts[name] = (counts[name] or 0) + 1
      local out = table.pack(f(port, ...))
      local record = out[2]
      local cost = type(record) == "table" and tonumber(record.cost) or (name == "mercury" and mercury_cost(record)) or 0
      counts[name .. "_cost"] = (counts[name .. "_cost"] or 0) + cost
      return table.unpack(out, 1, out.n)
    end
  end })
end

-- The computer's log as agent.memory's store: read and written through the computer itself.
local store = {
  events = function() return __host.agent_events() end,
  append = function(_, task, keyword, args, actor) __host.agent_append(task, keyword, args, actor or "agent") end,
}

local function keys(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = k end
  table.sort(out)
  return out
end

function M.step(saved_json, ctx)
  local host = arock.host()
  local saved = saved_json and json.decode(saved_json) or { counts = { jev = 0, mercury = 0, tabpfn = 0 } }
  local counts = saved.counts
  local mem = memory.new(store, { today = function() return host.clock():sub(1, 10) end })
  -- the models: through Arock's service on a node, the providers with the host's keys elsewhere (host.lua)
  local models = arock.models(host)
  -- the filler: Mercury, or for a comparison an OpenRouter model in its place, counted as the filler all the same
  -- (a thinking model on OpenRouter may refuse tool_choice "required": Qwen 3.8 does, so it is asked for "auto")
  local filler = ctx.filler and models.chat(ctx.filler, { tool_choice = "auto" })
    or assert(models.mercury, "no Mercury key")
  -- the decider: Jev, or for a comparison another System One model in its place, with the host's own key
  local decider = ctx.decider and require("ports.jev").new(host, { key = assert(host.key("jev"), "no Jev key"),
    model = ctx.decider }) or models.jev
  local env = {
    name = "the agent",
    jev = counted(assert(decider, "no Jev key"), "jev", counts),
    mercury = counted(filler, "mercury", counts),
    memory = mem,
    -- rank mode (ctx.learn "rank"): TabPFN ranks the allowed moves at every building decision and may take the step
    rank = ctx.learn == "rank" or nil,
    -- shadow mode (ctx.learn "shadow"): the same ranking, only recorded (Tablua's p_progress); Jev never reads it
    shadow = ctx.learn == "shadow" or nil,
  }
  local function at(n) return ctx.at .. "/step/" .. n end
  -- every step as Tablua's typed rows in the computer's own file (world/record.lua)
  -- the harness's own notes go under a task of their own: a log task is a plain name, and ctx.at is an address
  local rec = require("moss.world.record").new(ctx.at, function(line) __host.agent_append("tablua", "Note", { line }, "host") end)
  -- TabPFN learns which move helps from Tablua's rows: this computer's, and the node's shared experience when there is
  -- one (other computers' finished runs, Moss.Computer.Experience.share), in place of memory's folded rows
  local t = rec.tablua(ctx.experience)
  env.learn = learn.new({ memory = mem, tabpfn = models.tabpfn and counted(models.tabpfn, "tabpfn", counts),
    tablua = t, per_run = ctx.per_run })
  -- the facts, with what is broken in the app's program (its files put as Tablua's rows, tablua_break): a page
  -- calling a function its module never defined is named before a test is run on it
  local function facts()
    local f = __host.agent_facts(ctx.at)
    local ok, breaks = pcall(function() return t and f.program and t:put_app(f.program) end)
    f.breaks, f.program = ok and breaks or nil, nil
    return f
  end
  local decided
  env.decided = function(req, verb, answer, how)
    decided = verb
    rec.decided(req, verb, answer, how)
    local p = answer.probabilities or {}
    local options = {}
    for _, k in ipairs(keys(p)) do options[#options + 1] = k end
    store:append(req.task, "Decide", { at(#req.steps + 1), how or "jev",
      json.encode(json.array(options)), verb, tostring(answer.confidence or "") })
  end
  -- each command is logged under the step it is for, so the log (and its Robot rows) reads a step's work as one
  local doing
  local world = require("moss.world").new({
    exec = function(req)
      req.task = req.task or doing
      return __host.exec(req)
    end,
    facts = facts,
  }, ctx)
  world.after = function(_, req, step)
    store:append(req.task, "Outcome", { at(step.n), step.outcome, step.note or "", tostring(step.n) }, "host")
    local now = facts()
    rec.after(req, step, now, (require("moss.world").stage(now, req.publishes0)))
  end

  local a = agent.new(env, world)
  local req
  if saved.req then
    req, a.req = saved.req, saved.req
    a.history.entries, a.history.request = saved.history.entries, saved.history.request
  else
    req = a:begin(ctx.task)
    rec.gates(ctx)
  end

  local next = a:step(req)
  local kind, detail = next[1], next[2]
  -- Jev's answer is a decision too: its outcome is the run's end
  if kind == "done" and decided then
    store:append(req.task, "Outcome", { at(#req.steps + 1), "done", tostring(detail or ""), tostring(#req.steps + 1) },
      "host")
  end
  if kind == "act" then
    local step = detail
    doing = at(#req.steps + 1)
    local after = a:perform(req, step)
    -- the agent's own verbs (think, plan) leave no outcome: they did their part unless they say they failed, and
    -- every decision has its outcome
    step.outcome = step.outcome or (step.note and step.note:find("failed") and "broken" or "complete")
    a:close(req, step)
    kind, detail = after and after[1] or "act", after and after[2] or step.verb
    if kind == "done" and step.verb == "blocked" then kind = "blocked" end
  end
  counts.tabpfn_why = req.unranked   -- why TabPFN did not rank this step, cleared once it does
  saved.req, saved.history = req, { entries = a.history.entries, request = a.history.request }
  return kind, detail, json.encode(saved), counts
end

return M
