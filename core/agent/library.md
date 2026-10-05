---
name: agent
description: Arock's agent harness in portable Lua — Jev decides each step (typed choice with probabilities, a close call settled by a careful Mercury), Mercury fills it, TabPFN ranks the tools from past outcomes once Jev is stuck — as an explicit state machine over a world (the person's Mac in app/desktop/agent, the agent's own computer a host gives it); use when changing how the agent decides, records, learns or plans, or when giving it a new world.
summary: agent.new(env, world) or agent.mix(methods); a:begin(text) -> req; a:step(req) -> {"act", step} | {"done", why}; a:perform(req, step) -> nil | {"ask", form} | {"wait", what} | {"done", said}; a:answered(step, form, reply); a:close(req, step). env = { jev, mercury, learn?, memory?, trace?, log?, stepping?, refused?, decided? }; world = { tools, question, state, arbiter, think, ask, form, act, questions?, answered?, after?, judged? }. history (the conversation both minds read), parts (plan, next_part), checkpoint (outcomes, TabPFN before Jev, Jev's judgement), learn (TabPFN's ranking from Tablua's rows), memory (requests as rows in an arock-log store), calibrate (Jev's sureness against outcomes), trace (every port call as rows), clip (text cut to fit).
do:
  - Keep the loop free of coroutines; a world whose hands answer later returns {"wait", what} or waits inside its own act.
  - Ask every question about one state in Jev's one call (world.questions), and keep the state Jev reads to what bears on the choice.
  - Give Jev the full set of options with words for names and descriptions; TabPFN's ranking is evidence on its card, never a cut (in rank mode, opt-in and measured, its best allowed move may take a step over an unsure Jev).
  - Log every decision (env.decided) and every step's outcome (memory), so each decision is joined to how it turned out.
dont:
  - Put a world's tools, voice, or host in here; they belong to the world.
  - Let Mercury pick the verb; it fills the step Jev chose, and settles only Jev's close calls.
  - Use goto, //, utf8 or FFI: this runs on LuaJIT, Lua 5.4/5.5, Luerl and any Lua VM a host embeds.
---

# core/agent

Arock's agent (PROJECT.md §1, §11), shared by every place it works. Jev decides and Mercury fills: at each step Jev
picks a verb from the world's tools and the agent's own (`answer`, `ask`, `think`, `plan`, `next_part`), with a
probability for each; when its best two are within `agent.close` of each other a careful Mercury settles the call
(`world.arbiter`). After `checkpoint.stuck` failed steps, TabPFN ranks the tools from past outcomes (`learn.lua` over
Tablua's rows, core/tablua) and the ranking reaches Jev as evidence. `memory.lua` keeps the requests and steps as
keyword rows for the Mailbox and the log; a world without a harness of its own (the Mac's) passes `env.tablua`, and
`checkpoint.after` writes each step's Tablua rows itself. The request ends when Jev answers.

Rank mode (`env.rank`, 2026-10-04): at every decision of a stage in `checkpoint.ranked` (building) TabPFN ranks the
moves the world allows now (`world.allowed`), and its best takes the step when it leads Jev's pick by `agent.margin`
while Jev gave its pick less than `agent.jev_sure` (`A:overrule`; the decision is logged as TabPFN's). Each step's
row keeps the stage and the share of scenarios passing it was taken at (`req.stage`, `req.pass` from the world). An
offline study of 4,515 build steps found progress predictable from them (AUROC 0.82 on asks it had not seen) and
Jev overconfident in building; rank mode is the measured test of acting on it. A host can share each finished run's Tablua
rows between computers (`t:attach`), so each learns from every other's steps.

The loop is a state machine the host drives: `step` decides, `perform` does the verb (the agent's own here, a tool
verb in `world.act`), `close` records it and learns from its outcome. Nothing in it yields, so it runs on a Lua with
no coroutines; the desktop runs it inside its own coroutine because its Mac hands answer later.

Worlds: `app/desktop/agent/world.lua` (the person's Mac, by voice) and a host's computer world (the agent's
own computer, where it builds what the person asks).

Modules: `init.lua` (decide and the step machine), `history.lua`, `parts.lua`, `checkpoint.lua`, `learn.lua`,
`memory.lua`, `calibrate.lua`, `trace.lua`, `clip.lua`; one `_test.lua` each.
