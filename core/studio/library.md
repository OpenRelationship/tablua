---
name: studio
description: Moonsplice as Tablua's world (owner, 2026-10-06) — the agent builds a game or a video as a comp of rows (msr/1, Moonsplice's .robot/docs/rows.robot), one typed patch move at a time; Jev decides the move, MiniMax M3 fills it as tool calls, the engine applies and checks it, the step's outcome comes from the findings, and look has the critic score a contact sheet; use when changing the moves, what TabICL reads of a comp, the prompts, or how a step is judged.
summary: studio.world.new{ engine, writer, critic, tablua, comp, sheet, ask, kind?, exec } -> world for agent.new; studio.moves (order, what, schema, tool(move), check(move, patch), patch(move, args)); studio.features (read(t, todo, n, extra), record, learner(t) for learn.new{ step = ... }, columns); studio.prompts (director, move, expect, eye, critic, scores, the bans and the rubric); studio.judge (ask, read: the eye's observations and Jev's typed judgement of a look); studio.context (history: the run as a line a step rendered from the sheet; card: the reference card's sections a move needs; shown: a request as kept). The engine is ports.moonsplice (./moonsplice rows | rows --brief | patch | expect | lint | check | sheet); the rows are tablua.studio (schema 22), every model call a tablua_prompt row. studio.connect.tool(s) is the connect tool (find, calls, call over connectory's port, with s.o.connect = { port, ask, approval? }): a missing credential and a call that changes something become asks the host shows the person (tablua_ask), each call a tablua_connect row, and studio.connect.open(s) what still waits on them.
do:
  - Edit a comp only through the moves; a whole-file rewrite is not a move.
  - Judge a step from the findings before and after it and what it touched (tablua.studio.outcome), never from the writer's word.
  - Keep a payload's fields the engine's (core/moonsplice/rows.lua MOVES); a change to them is a change to rows.robot first.
  - Keep every step's comp, findings and scores as rows, so a claim is a query over them.
dont:
  - Do not ask for, accept or pass on a credential in the conversation; the host's store and secret(name) hold it, and the person types it into the host's own field.
  - Run TabICL anywhere but the host (host.tabicl, Candle in Moonsplice's binary).
  - Put Moonsplice's engine code here; it lives in Moonsplice and is reached through ports.moonsplice.
