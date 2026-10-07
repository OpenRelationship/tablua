-- Rust and Bevy tools for the studio's model (Moonsplice's .robot/docs/plugins.robot): one tool, plugins, over the
-- host's plugin directory, the same rows `./moonsplice plugin search --json` prints. The model finds a tool for what
-- the piece needs and reads whether it can be used: the layers it serves (video, game, app), its determinism class,
-- and its status (listed, resolves in the engine's workspace, wired and usable from a comp).
--
--   local tool = require("studio.plugins").tool(s)      s: the session; s.o.plugins = { search, show }
--     search(text, limit) -> { row, ... }    show(name) -> row | nil
--     a row: { name, crate, release, category, layers, ways, class, status, description, conflict?, ... }
local M = {}

local function list(t) return table.concat(t or {}, ",") end

-- one row as one line the model reads
function M.line(e)
  return ("%s (%s) %s | %s | layers %s | ways %s | class %s | %s%s%s"):format(e.name, e.crate or "-",
    e.release and ("v" .. e.release) or "no release for the engine's Bevy", e.category or "", list(e.layers),
    list(e.ways), e.class or "unmeasured", e.status or "listed",
    e.conflict and (" (" .. e.conflict .. ")") or "", e.description and (": " .. e.description) or "")
end

local function result(text) return { content = text, details = { verb = "plugins", outcome = "complete" } } end

function M.tool(s)
  return { name = "plugins", description = "Find a Rust or Bevy tool for the piece in the engine's plugin directory: "
      .. "search (words) lists the best matches, show (name) gives one. Each says which layers it serves (video, game, "
      .. "app), its determinism class, and its status: only a wired tool can be used from a comp today.",
    parameters = { type = "object", required = { "action" }, properties = {
      action = { type = "string", enum = { "search", "show" } },
      words = { type = "string", description = "what the piece needs, in a few words" },
      name = { type = "string", description = "a tool's crate or name, as search gives it" } } },
    execute = function(args)
      local p = s.o.plugins
      if args.action == "search" then
        local rows = p.search(args.words or "", 8)
        if #rows == 0 then return result("nothing in the directory matches " .. tostring(args.words)) end
        local out = {}
        for _, e in ipairs(rows) do out[#out + 1] = "- " .. M.line(e) end
        return result(table.concat(out, "\n"))
      elseif args.action == "show" then
        local e = p.show(args.name or "")
        if not e then error("no tool called " .. tostring(args.name) .. " (search first)", 0) end
        return result(M.line(e) .. (e.link and ("\n" .. e.link) or "") .. (e.licence and ("\nlicence " .. e.licence) or ""))
      end
      error("action is search or show", 0)
    end }
end

return M
