-- What was typed, as columns: a command line cut into the commands it runs, each one's program (after any
-- VAR=value, sudo, env, nohup, time or timeout in front of it), the files its redirections and tee write, and whether
-- the whole line only looks at the computer (every program one that reads, writing nothing). Quotes and heredoc
-- bodies are kept whole, so an operator inside them cuts nothing; a comment is no command.
--
--   local command = require("term.command")
--   command.parse(line) -> { program, programs = { ... }, writes = { path, ... }, reads, pipes, chained, background,
--                            comments, heredoc }
--   command.only_reads(line) -> bool
--   command.readers     the programs that only look
local M = {}

M.readers = {}
for w in ([[cat ls head tail grep egrep fgrep rg wc find which whereis file stat pwd echo printf cd less more tree du
  df env printenv type diff cmp od xxd hexdump readelf objdump nm strings id whoami uname date sort uniq cut tr column
  basename dirname realpath readlink md5sum sha1sum sha256sum true false test [ ps top free uptime lsof jq yq man
  command hostname nproc lscpu locale history help ldd]]):gmatch("%S+") do M.readers[w] = true end

local PREFIX = { sudo = true, env = true, nohup = true, time = true, exec = true, command = false }
-- the shell's own words, which are no program, and commands that only set the shell up, which are no command's
-- program when another follows (cd /app && make is make)
local KEYWORD = {}
for w in ("if then else elif fi for do done while until case esac in function { } ( ) ! [[ ]] select"):gmatch("%S+") do
  KEYWORD[w] = true
end
local SETUP = { cd = true, export = true, set = true, source = true, ["."] = true, unset = true, alias = true,
  pushd = true, popd = true, ulimit = true, umask = true, shopt = true }

-- the line cut into commands: { text, sep } where sep is the operator after it (";", "&&", "||", "|", "&", "")
local function cut(line)
  local out, cur, i, n = {}, {}, 1, #line
  local quote, heredoc
  local function push(sep)
    local text = table.concat(cur):gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= "" or sep ~= "" then out[#out + 1] = { text = text, sep = sep } end
    cur = {}
  end
  while i <= n do
    local c = line:sub(i, i)
    if heredoc then
      -- a heredoc's body runs to a line holding only its word
      local stop = line:find("\n" .. heredoc .. "%s*\n", i - 1) or line:find("\n" .. heredoc .. "%s*$", i - 1)
      if stop then
        local after = line:find("\n", stop + 1) or n + 1
        cur[#cur + 1] = line:sub(i, after - 1)
        i, heredoc = after, nil
      else
        cur[#cur + 1] = line:sub(i)
        i = n + 1
      end
    elseif quote then
      cur[#cur + 1] = c
      if c == "\\" and quote == '"' then cur[#cur + 1] = line:sub(i + 1, i + 1) i = i + 1
      elseif c == quote then quote = nil end
      i = i + 1
    elseif c == "'" or c == '"' then
      quote = c cur[#cur + 1] = c i = i + 1
    elseif c == "\\" then
      cur[#cur + 1] = line:sub(i, i + 1) i = i + 2
    elseif line:sub(i, i + 1) == "<<" then
      local word, upto = line:match("^<<%-?%s*['\"]?([%w_]+)['\"]?()", i)
      cur[#cur + 1] = line:sub(i, (upto or i + 2) - 1)
      i = upto or i + 2
      if word then
        local eol = line:find("\n", i) or n + 1
        cur[#cur + 1] = line:sub(i, eol)
        i, heredoc = eol + 1, word
      end
    elseif line:sub(i, i + 1) == "&&" or line:sub(i, i + 1) == "||" then
      push(line:sub(i, i + 1)) i = i + 2
    elseif c == "&" and line:sub(i - 1, i - 1) ~= ">" and line:sub(i + 1, i + 1) ~= ">" then
      push("&") i = i + 1
    elseif c == "|" then
      push("|") i = i + 1
    elseif c == ";" or c == "\n" then
      push(";") i = i + 1
    else
      cur[#cur + 1] = c i = i + 1
    end
  end
  push("")
  return out
end

local function words(text)
  local out = {}
  for w in text:gsub("<<%-?%s*['\"]?[%w_]+['\"]?.*$", ""):gmatch("%S+") do out[#out + 1] = w end
  return out
end

local function unquote(s) return (s:gsub("^['\"]", ""):gsub("['\"]$", "")) end

local function program_of(ws)
  local i = 1
  while ws[i] do
    local w = ws[i]
    if w:find("^[%a_][%w_]*=") then i = i + 1
    elseif PREFIX[w] then i = i + 1
    elseif w == "timeout" then
      i = i + 1
      while ws[i] and (ws[i]:find("^%-") or ws[i]:find("^%d")) do i = i + 1 end
    else break end
  end
  while ws[i] and KEYWORD[ws[i]] do i = i + 1 end
  local w = ws[i]
  if not w then return nil, i end
  return (unquote(w):match("[^/]+$") or w), i
end

-- files a command writes: its > and >> targets (not /dev/null or a descriptor) and tee's arguments
local function writes_of(text, ws, at, out)
  for target in text:gmatch("%d?>>?%s*([^%s;&|<>]+)") do
    target = unquote(target)
    if not target:find("^&") and target ~= "/dev/null" and not target:find("^/dev/fd") then out[#out + 1] = target end
  end
  if ws[at] and (ws[at]:match("[^/]+$") == "tee") then
    for j = at + 1, #ws do if not ws[j]:find("^%-") then out[#out + 1] = unquote(ws[j]) end end
  end
end

function M.parse(line)
  line = tostring(line or ""):gsub("\r", "")
  local r = { programs = {}, writes = {}, reads = true, pipes = 0, chained = 0, background = 0, comments = 0,
    heredoc = line:find("<<%-?%s*['\"]?[%w_]+") ~= nil }
  for _, part in ipairs(cut(line)) do
    if part.sep == "|" then r.pipes = r.pipes + 1
    elseif part.sep == "&&" or part.sep == "||" or part.sep == ";" then r.chained = r.chained + 1
    elseif part.sep == "&" then r.background = r.background + 1 end
    if part.text:find("^#") then
      r.comments = r.comments + 1
    elseif part.text ~= "" then
      local ws = words(part.text)
      local prog, at = program_of(ws)
      local before = #r.writes
      writes_of(part.text, ws, at, r.writes)
      if prog then
        r.programs[#r.programs + 1] = prog
        local looks = M.readers[prog]
          or (prog == "sed" and part.text:find("%-n") and not part.text:find("%-i"))
          or (prog == "awk" and not part.text:find(">", 1, true))
          or (prog == "git" and (ws[at + 1] == "status" or ws[at + 1] == "log" or ws[at + 1] == "diff" or ws[at + 1] == "show"))
        if not looks or #r.writes > before then r.reads = false end
      end
    end
  end
  r.program = r.programs[1] or ""
  for _, p in ipairs(r.programs) do if not SETUP[p] then r.program = p break end end
  if #r.programs == 0 and r.comments == 0 then r.reads = false end
  return r
end

function M.only_reads(line) return M.parse(line).reads end

return M
