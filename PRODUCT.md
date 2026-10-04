# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

tablua.com (`site/`): React with Framer Motion (owner, 2026-10-04), built with Vite to static files and served
by a Cloudflare Worker's static assets on tablua.com (owner chose Workers static assets). TypeScript and Node
tooling live only in `site/`; the product itself is Elixir and Lua.

## Users

Agent researchers first (owner, 2026-10-04): people who follow continual-learning agents and judge a project by
its idea and its mechanism, then read the code.

## Product Purpose

Tablua is an embeddable agent and its own computer. Everything the agent is and does is kept as typed tables in
one SQLite file: where the work stands, every move it could make with each model's numbers, the move taken and by
whom, how each step turned out, and how each run ended. A tabular foundation model (TabPFN) learns from those rows
which moves make progress; a language model's probabilities (Jev) are its features; another model (Mercury)
writes the cells that need prose or code. The site's job: make that idea intelligible and send the visitor to
the GitHub repository.

## Positioning

The agent's memory, state and policy are rows, not a prompt or a vector store: continual learning by a tabular
model over the agent's own typed history, with the agent's computer (Moss) inside the same file. The host that
runs an agent is a stateless stepper over that file.

## Operating Context

Visitors arrive from links in research circles; they read on desktop mostly, also phones. The one action is going
to https://github.com/OpenRelationship/tablua (public, Apache-2.0).

## Capabilities and Constraints

- Parts: the harness (the `tablua_*` tables and the step loop), Moss (the agent's computer on the BEAM: a process
  per agent, its disk one SQLite file, its own shell, browser and mailbox, Lua as its language), Shroomi (how the
  agent publishes pages and apps, `.lui` files).
- Tables today: tablua_state, tablua_candidate, tablua_decision, tablua_action, tablua_outcome, tablua_run,
  tablua_fit, tablua_prediction, tablua_gate.
- No WebAssembly, no native code an agent can reach; Elixir and Lua.
- Arock (Mac and iPhone apps, and a server for thousands of computers) is built on Tablua.
- Undecided: docs site, hosted offering, waitlist. None exists; the site must not imply one.

## Brand Commitments

- Name: Tablua (table + Lua). Moss (🌿) and Shroomi (🍄) keep their names as parts.
- Visual brief pinned by the owner: blue primary, light and white theme, spreadsheets and graph paper, animated.
- Owner, 2026-10-04, after rejecting a dense coding-form grid design as ugly: clean, minimalist, white and light.
  Tables and graph paper are accents in one or two places, never the texture of the page. Never dark.

## Evidence on Hand

No published numbers yet (owner, 2026-10-04): describe the mechanism only. No customers, benchmarks, testimonials
or pricing exist; never invent them. Illustrative table rows are allowed when labelled as an example.

## Product Principles

- An agent is its file: state, history and policy are rows anyone can query.
- Learn from outcomes, not prompts: every step is labelled by what it did.
- Policy is data: gates and moves are rows that can be measured and removed.
- Small and legible: two languages, one file, a stateless host.
