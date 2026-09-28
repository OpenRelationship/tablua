-- Regenerates the LuaJIT side of the Colm outline parity test: runs
-- outline.wasm through Volvox's own suite.runner on LuaJIT (wasmtime through
-- the qubie-world wasm library, the same path python-edit's steps use) over
-- every file in Volvox's python-edit test data, and writes each run's stdout,
-- stderr and status next to this script.
--
--   cd ~/volvox-server && luajit test/fixtures/outline/generate.lua
--
-- VOLVOX_WASM_LUA (default ~/qubie-world/library) and VOLVOX_SUITE (default
-- ~/volvox/.cache/volvox/suite) name the wasm library and the built modules.
local home = os.getenv("HOME")
local wasm_lib = os.getenv("VOLVOX_WASM_LUA") or (home .. "/qubie-world/library")
local suite_dir = os.getenv("VOLVOX_SUITE") or (home .. "/volvox/.cache/volvox/suite")
local here = "test/fixtures/outline/"
local data = "submodules/volvox/context/projects/volvox/features/python-edit/test/data/"
package.path = "submodules/volvox/library/?.lua;submodules/volvox/library/?/init.lua;"
  .. wasm_lib .. "/?.lua;" .. wasm_lib .. "/?/init.lua;" .. package.path

local suite = require("suite")
local wasm = require("wasm")

local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function spit(path, s)
  local f = assert(io.open(path, "wb"))
  f:write(s)
  f:close()
end

local mod = wasm.compile(slurp(suite_dir .. "/outline.wasm"))
local run = suite.runner(function() return mod:instantiate() end)
local p = assert(io.popen("ls " .. data))
for name in p:lines() do
  local out, status, err = run(slurp(data .. name))
  spit(here .. name .. ".out", out)
  spit(here .. name .. ".err", err)
  spit(here .. name .. ".status", tostring(status) .. "\n")
  print(name, status, #out, #err)
end
p:close()
