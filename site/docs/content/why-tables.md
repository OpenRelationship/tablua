---
description: Why Tablua keeps an agent's history as typed rows instead of text, and what that makes possible.
---

# Why an agent as tables

An agent that keeps its history as text can only use that history by reading it again. An agent that keeps its history as tables can query it, count it and learn from it. That is the idea Tablua is built on.

## The usual way: history as text

Most agents work like this. A language model reads a prompt that describes the todo and what has happened so far. It writes the next action. The result is added to the prompt, and the loop repeats. When the prompt gets too long, older parts are summarised or moved into a vector store to be searched later.

This works, and it is simple. But it leaves some questions hard to answer:

- **Which of the agent's choices actually helped?** The record is prose, so you have to read it, or ask another model to read it.
- **Is the agent getting better over time?** Each run starts again from a prompt. What went well last week is not something the agent can count.
- **Why did it do that?** The rules that steer it are mixed into instructions, so it is hard to tell which rule caused which behaviour.

## Tablua's way: history as rows

Tablua writes each step of the agent's work into tables with fixed columns. Here is one step, shortened:

| table | row |
| --- | --- |
| state | `stage=building  passed=2/4  stalls=0  last_verb=write_keywords` |
| candidate | `rewrite  jev_p=.55` |
| candidate | `write_page  jev_p=.30` |
| decision | `chosen=rewrite  by=jev` |
| outcome | `broken  progress=0  passed=1/4  regressed=1` |

Because the record is data, the questions above become queries:

- **Which choices helped?** Count the outcomes with `progress = 1` for each move, in each stage.
- **Is it getting better?** Compare runs by how many steps they took and whether they shipped.
- **Why did it do that?** The decision row says who chose the move, and the rules that hold moves back are rows too.

## What tables make possible

**A model can learn from the agent's own record.** TabPFN is a model built to learn from small tables in one pass, with no training run. Give it the agent's past rows and it gives each possible move a chance of making progress now. As the agent works, the table grows, and the next prediction knows more. See [How Tablua learns](/concepts/learning).

**Agents can learn from each other.** Rows from different agents line up, column for column. When one agent finishes a run, its rows can join a shared file that the next agent reads. See [Shared experience](/concepts/shared-experience).

**Rules can be tested like features.** Each rule that holds a move back is a named row with a stated reason. You can turn one off for some runs and compare. See [Policy as data](/concepts/policy-as-data).

**The record outlives the run.** Everything is in one SQLite file. You can copy it, open it with any SQLite tool, and move it to another machine. The host that runs the agent keeps nothing of its own: it reads the file, takes one step, and writes the file.

## What Tablua does not change

The language models are still there and still do what language models do well. Jev reads the situation and picks a move. Mercury writes code and pages. Tablua changes what surrounds them: what is recorded, who decides what, and how the agent learns from what happened.

{{diagram:file}}

## Next

Take [A tour of one step](/start/tour) to see the rows being written, one at a time.
