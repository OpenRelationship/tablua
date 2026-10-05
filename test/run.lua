-- Runs Tablua's tests: every core/**/*_test.lua, each in its own process, with core/ and test/ on the module path.
--   luajit test/run.lua            -- all of them
--   luajit test/run.lua tree edit  -- only files whose path contains one of the words
-- The interpreter is LuaJIT unless TABLUA_LUA names another; tests that open SQLite need LuaJIT's FFI.
local lua = os.getenv("TABLUA_LUA") or "luajit"
local root = (arg[0]:match("^(.*)/test/run%.lua$") or ".")

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local files = {}
local list = io.popen("find " .. quote(root .. "/core") .. " -name '*_test.lua' | sort")
for path in list:lines() do
  local keep = #arg == 0
  for _, word in ipairs(arg) do
    if path:find(word, 1, true) then keep = true end
  end
  if keep then files[#files + 1] = path end
end
list:close()

local paths = string.format("%s/core/?.lua;%s/core/?/init.lua;%s/test/?.lua;", root, root, root)
local setup = "package.path=" .. string.format("%q", paths) .. "..package.path"

local failed = {}
for _, path in ipairs(files) do
  local name = path:sub(#root + 2)
  local out = io.popen(string.format("%s -e %s %s 2>&1; echo \"exit:$?\"", lua, quote(setup), quote(path)))
  local text = out:read("*a")
  out:close()
  local code = tonumber(text:match("exit:(%d+)%s*$"))
  local summary = text:match("# (%d+ passed, %d+ failed)") or "no TAP summary"
  if code == 0 then
    print(string.format("ok   %s  (%s)", name, summary))
  else
    failed[#failed + 1] = name
    print(string.format("FAIL %s  (%s)", name, summary))
    for line in text:gsub("exit:%d+%s*$", ""):gmatch("[^\n]+") do
      if not line:match("^ok ") then print("     " .. line) end
    end
  end
end

print(string.format("\n%d files, %d failed", #files, #failed))
if #failed > 0 then os.exit(1) end
