-- The keywords arock-log knows, each with its arguments in order. A name ending
-- in "?" may be left off (only at the end), "#" must read as a number, and
-- "*" is content: the caller gives the bytes, the log keeps them once as a
-- blob and records the blob's id in their place. Any other keyword is free:
-- its arguments are strings, logged and recalled, and change nothing.
local M = {}

M.args = {
  -- the agent's tasks and versions (Arock)
  ["Start Task"] = { "machine", "goal?" },
  ["Enter State"] = { "state" },
  ["Test Result"] = { "result", "detail?" },
  ["Publish Artifact"] = { "name" },
  ["Undo"] = { "seq#" },
  ["Load Workspace"] = { "source", "count#" },
  -- a computer's disk (Moss): a remove or move takes a folder with all under it
  ["Write File"] = { "path", "content*" },
  ["Make Folder"] = { "path" },
  ["Delete File"] = { "path" },
  ["Move File"] = { "from", "to" },
  -- a computer's runs, its app and its post (Moss); ms is wall time in milliseconds
  ["Run Command"] = { "line", "cwd", "status#", "ms#", "out*", "err*" },
  ["Serve Request"] = { "method", "path", "status#", "ms#", "form*", "page*" },
  ["Send Mail"] = { "to", "subject", "body*", "outcome", "letter" },
  ["Receive Mail"] = { "from", "subject", "body*", "letter" },
  -- org on the log (arock-log.org_log): an entry's text is folded from Add and Edit; the rest say what changed
  ["Add Entry"] = { "path", "id", "entry*" },
  ["Edit Entry"] = { "id", "entry*" },
  ["Set State"] = { "id", "from", "to" },
  ["Set Date"] = { "id", "which", "date" },
  ["Set Property"] = { "id", "key", "value" },
  ["Link"] = { "id", "target" },
  ["Move Entry"] = { "path", "order" },
  ["Archive Entry"] = { "id" },
  ["Set Header"] = { "path", "header*" },
  -- what refine reads (feature refine): a choice with every option offered, a grade, an outcome; at and target
  -- are org: addresses or entry IDs, the keys a decision joins its outcome by (the desktop agent's own rows name
  -- "step" or "request" as their target, and a step its number)
  ["Decide"] = { "at", "who", "options", "choice", "confidence?" },
  ["Grade"] = { "target", "score", "confidence?", "why?" },
  ["Outcome"] = { "target", "outcome", "detail?", "step?" },
  -- reach (feature manifest): the person's yes to one request of a tool (NET and a host, MAIL and an address, ...),
  -- taken back when the request goes; a tool marked ASK waiting for the person
  ["Grant Reach"] = { "tool", "reach", "value" },
  ["Revoke Reach"] = { "tool", "reach", "value" },
  ["Ask Person"] = { "tool", "line" },
  -- the build loop (Arock feature file-kinds): the person's yes to a feature's scenarios as they stand (digest
  -- is the SHA-256 of its text, so a change takes the yes back)
  ["Agree Feature"] = { "feature", "digest" },
  -- the person's notes (Arock feature notes): each version's text as typed, kept whole; a note's task is its id
  ["Add Note"] = { "note", "folder", "text*" },
  ["Edit Note"] = { "note", "text*" },
  ["Move Note"] = { "note", "folder" },
  -- what a writ composed, after the person's yes (Arock feature notes, the composer): a rock's character or focus in
  -- the person's words ("" when the writ no longer says it), and from: the writ, its version and the sentences' bytes
  ["Set Character"] = { "rock", "part", "text*", "from" },
  -- every line a writ builds, after the person's yes: a rock's character or focus, a tool, reach, a term, a route
  -- or an asked feature (kind), under its key, its value as the composer wrote it ("" when the writ no longer says
  -- it); rock is "*" for a line every rock reads
  ["Set Writ Line"] = { "rock", "kind", "key", "value*", "from" },
}

-- Each declared argument as { name, optional, number, blob }.
M.spec = {}
for keyword, list in pairs(M.args) do
  local out = {}
  for i, a in ipairs(list) do
    out[i] = { name = a:match("^[%w_]+"), optional = a:sub(-1) == "?", number = a:sub(-1) == "#", blob = a:sub(-1) == "*" }
  end
  M.spec[keyword] = out
end

local function arity(spec)
  local need = 0
  for i, a in ipairs(spec) do if not a.optional then need = i end end
  return need, #spec
end

-- Raises unless args fit keyword's declaration (free keywords always fit).
function M.check(keyword, args)
  local spec = M.spec[keyword]
  if not spec then return end
  local least, most = arity(spec)
  if #args < least or #args > most then
    local names = {}
    for i, a in ipairs(spec) do names[i] = a.name .. (a.optional and "?" or "") end
    error(keyword .. " takes " .. table.concat(names, ", ") .. "; got " .. #args .. " arguments", 0)
  end
  for i, a in ipairs(spec) do
    if a.number and args[i] ~= nil and not tonumber(args[i]) then
      error(keyword .. ": " .. a.name .. " is not a number: " .. args[i], 0)
    end
  end
end

-- An event's arguments by name, as declared; a free keyword's by position.
function M.fields(e)
  local out, spec = {}, M.spec[e.keyword] or {}
  for i, v in ipairs(e.args) do out[spec[i] and spec[i].name or i] = v end
  return out
end

return M
