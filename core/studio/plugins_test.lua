-- studio.plugins over a fake of the host's directory: search lists matches one per line with their layers, class and
-- status, show gives one with its link, an unknown name is an error, and the tool is in a session's tool list only
-- when the host gives it a directory.
local spec = require("spec")
local plugins = require("studio.plugins")

local ROWS = {
  { name = "bevy_mod_outline", crate = "bevy_mod_outline", release = "0.13.0", category = "3D",
    layers = { "video", "game" }, ways = { "W1" }, class = "unmeasured", status = "resolves",
    description = "A plugin for drawing outlines around meshes", link = "https://crates.io/crates/bevy_mod_outline",
    licence = "MIT OR Apache-2.0" },
  { name = "bevy_vello", crate = "bevy_vello", release = "0.14.0", category = "2D", layers = { "video", "game" },
    ways = { "W1", "W3" }, class = "unmeasured", status = "conflicts", conflict = "brings a second vello (0.9.0)",
    description = "Render vector assets with Vello" },
}

local function session()
  return { o = { plugins = {
    search = function(text) local out = {} for _, e in ipairs(ROWS) do if e.name:find(text, 1, true) then out[#out + 1] = e end end return out end,
    show = function(name) for _, e in ipairs(ROWS) do if e.crate == name then return e end end end,
  } } }
end

spec.test("search lists each match with its layers, class and status", function()
  local tool = plugins.tool(session())
  local r = tool.execute({ action = "search", words = "outline" })
  spec.ok(r.content:find("bevy_mod_outline (bevy_mod_outline) v0.13.0 | 3D | layers video,game | ways W1 | class unmeasured | resolves", 1, true), r.content)
  spec.eq(r.details.verb, "plugins")
end)

spec.test("a conflict is said, and show gives the link and licence", function()
  local tool = plugins.tool(session())
  spec.ok(tool.execute({ action = "search", words = "vello" }).content:find("brings a second vello", 1, true))
  local r = tool.execute({ action = "show", name = "bevy_mod_outline" })
  spec.ok(r.content:find("https://crates.io/crates/bevy_mod_outline", 1, true))
  spec.ok(r.content:find("licence MIT OR Apache-2.0", 1, true))
end)

spec.test("an unknown name is an error, and nothing matching says so", function()
  local tool = plugins.tool(session())
  spec.err(function() tool.execute({ action = "show", name = "nope" }) end, "no tool called nope")
  spec.ok(tool.execute({ action = "search", words = "zzz" }).content:find("nothing in the directory", 1, true))
end)

spec.test("the tool is offered only when the host gives a directory", function()
  local tools = require("studio.tools")
  local names = function(list) local out = {} for _, t in ipairs(list) do out[t.name] = true end return out end
  local with = names(tools.list({ o = { plugins = session().o.plugins } }))
  spec.ok(with.plugins)
  spec.ok(not names(tools.list({ o = {} })).plugins)
end)

spec.run()
