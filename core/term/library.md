---
name: term
description: The agent's terminal, one of Tablua's own parts (owner, 2026-10-06) — a shell session on the agent's computer driven by keystrokes and a wait and read back as its screen (tmux over the host's exec, or a plain session where tmux cannot be had), the screen read into typed events, and the session written as Qwen-AgentWorld's turns so a language world model foresees the next screen in the same form; use when changing how the agent works a terminal, how a screen is read, or how the world model is asked.
summary: term.new(exec, opts?) -> s; s:open() -> "tmux" | "plain"; s:send(keys, wait) -> { keys, wait, screen, exit, done, ms, first_ms, files, raw, trace } (returns when the command is back at the prompt, or after wait with it still running); term.command.parse(line) -> { program, programs, writes, reads, ... }; term.pty.read(bytes) -> { red, redraws, alt_screen, ... }; term.read.events(screen) -> { { kind, name, file, line, text, sig, count } }; term.turns.messages(session, keys, wait), term.turns.observed(reply) -> screen; ports.agentworld.new(chat):foresee(session, keys, wait) -> screen, record; the rows are tablua_term and tablua_event (t:term, t:term_features, t:surprise).
do:
  - Drive the terminal the way the world model's training data does: raw keystrokes ("cmd\n", "C-c", "" to wait) and a wait in seconds.
  - Read real and foreseen screens with the same reader, so their rows compare.
  - Ask AgentWorld with thinking off: 3 to 6 seconds a turn against 20 to 80 with it (2026-10-06).
  - Check a column read from what was typed against what bash itself ran (trace, ran): the oracle agreed on 22 of 22 actions (.robot/claims/terminal.robot).
dont:
  - Make a wait a limit on the command: a command still running when the wait ends keeps running, and the next send can wait for it or interrupt it.
  - Ask the world model to parse or label a screen: parsing is term.read's, deterministic; the model only foresees.
  - Edit term/agentworld_prompt.lua or agentworld_examples.lua: they are AgentWorld's own prompt, byte for byte.
---

# core/term

The terminal is where an agent's work meets its computer, so it is Tablua's own, not a host's. `init.lua` is the
session: tmux on its own socket (`tmux -L tablua`), its prompt and the count and exit code of every command kept in a
file by the shell's `PROMPT_COMMAND`, so one exec sends the keys, waits until the prompt is back (or the wait runs
out) and reads the screen from the prompt the keys were typed at. Without tmux it installs it, and failing that runs
a plain session whose screen is written as tmux's would be.

Each send also keeps what the screen loses. tmux's `pipe-pane` writes the raw bytes, which `pty.lua` reads into
columns (lines in red, yellow or green, redraws, the alternate screen); a mark file and `find -newer` list the files
written; bash's DEBUG trap logs every simple command it runs (each side of a pipe, each part of a chain) to a trace,
so what was typed can be checked against what ran; and the first output past the keys' echo is timed in milliseconds,
looked for every 5 ms (it once counted 100 ms polls). `command.lua` reads what was typed: its programs (past
`VAR=`, `sudo`, `timeout` and the commands that only set the shell up, so `cd /app && make` is make), the files its
redirections write, and whether it only looks.

`read.lua` reads a screen into events: compiler errors, exceptions (a Python traceback is one event), commands,
files, modules and packages not found, permission, network, build failures, crashes and syntax errors, each with a
signature that stays the same when the same thing goes wrong again.

`turns.lua` is AgentWorldBench's terminal format, character for character; `agentworld_prompt.lua` and
`agentworld_examples.lua` are its system prompt. `ports/agentworld.lua` asks the model.

The rows (`core/tablua/term.lua`, schemas 15 to 17): `tablua_term`, each action and its screen from a source (real or
world), `tablua_event`, each screen's events, and `tablua_surprise`, where the foreseen and the real part. A tabular
model reads `t:term_features` and learns from the real rows what the world model foresees, so the world model is
asked only where the rows leave it unsure.

Modules: `init.lua`, `command.lua`, `pty.lua`, `read.lua`, `turns.lua`, `agentworld_prompt.lua`,
`agentworld_examples.lua`; `init_test.lua`, `command_test.lua`, `pty_test.lua`, `read_test.lua`, `turns_test.lua`.
