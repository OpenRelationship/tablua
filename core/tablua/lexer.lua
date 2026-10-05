-- Lua's tokens, as far as the program's rows need them: a unit's
-- columns (its code lines, a function's parameters, its deepest block, the names it uses) and a rename that
-- reaches every reference and never a string or a comment. Every byte is in some token, so the tokens' text
-- joined is the text.
--
--   local lexer = require("tablua.lexer")
--   lexer.tokens(text) -> { { t = "name"|"string"|"comment"|"number"|"op"|"space", s, line } }
--   lexer.columns(source) -> { lines, arity, depth }
--   lexer.refs(source) -> { [name] = true }       names it uses, dotted paths too (post.add)
--   lexer.rename(source, old, new) -> source, n   old and new names or dotted paths
local M = {}

M.keywords = {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true "
  .. "until while"):gmatch("%a+") do M.keywords[w] = true end

local TWO = { ["=="] = true, ["~="] = true, ["<="] = true, [">="] = true, [".."] = true, ["::"] = true,
  ["//"] = true, ["<<"] = true, [">>"] = true }

-- the end of a long bracket opened at i with level eq, or the text's end
local function long_end(text, from, eq)
  local _, j = text:find("]" .. eq .. "]", from, true)
  return j or #text
end

function M.tokens(text)
  local out, i, n, line = {}, 1, #text, 1
  local function push(t, j)
    local s = text:sub(i, j)
    out[#out + 1] = { t = t, s = s, line = line }
    local _, nl = s:gsub("\n", "")
    line, i = line + nl, j + 1
  end
  while i <= n do
    local c = text:sub(i, i)
    if c:match("%s") then
      push("space", (text:find("[^%s]", i) or n + 1) - 1)
    elseif c == "-" and text:sub(i + 1, i + 1) == "-" then
      local eq = text:match("^%[(=*)%[", i + 2)
      if eq then push("comment", long_end(text, i + 4 + #eq, eq))
      else push("comment", (text:find("\n", i, true) or n + 1) - 1) end
    elseif c == "[" and text:match("^%[=*%[", i) then
      local eq = text:match("^%[(=*)%[", i)
      push("string", long_end(text, i + 2 + #eq, eq))
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = text:sub(j, j)
        if d == "\\" then j = j + 2 elseif d == c or d == "\n" then break else j = j + 1 end
      end
      push("string", j > n and n or j)
    elseif c:match("[%a_]") then
      push("name", (text:find("[^%w_]", i) or n + 1) - 1)
    elseif c:match("%d") or (c == "." and text:sub(i + 1, i + 1):match("%d")) then
      local j = i
      while j < n do
        local d, e = text:sub(j + 1, j + 1), text:sub(j, j)
        if d:match("[%w%.]") or (d:match("[%+%-]") and e:match("[eEpP]")) then j = j + 1 else break end
      end
      push("number", j)
    elseif text:sub(i, i + 2) == "..." then
      push("op", i + 2)
    else
      push("op", TWO[text:sub(i, i + 1)] and i + 1 or i)
    end
  end
  return out
end

-- the tokens that are code: neither space nor comment
local function code(tokens)
  local out = {}
  for _, tk in ipairs(tokens) do
    if tk.t ~= "space" and tk.t ~= "comment" then out[#out + 1] = tk end
  end
  return out
end

function M.columns(source)
  local toks = code(M.tokens(source))
  local seen, lines, depth, deepest, arity = {}, 0, 0, 0, 0
  for _, tk in ipairs(toks) do
    if not seen[tk.line] then seen[tk.line], lines = true, lines + 1 end
    if tk.t == "name" then
      if tk.s == "function" or tk.s == "if" or tk.s == "do" or tk.s == "repeat" then
        depth = depth + 1
        if depth > deepest then deepest = depth end
      elseif tk.s == "end" or tk.s == "until" then
        depth = depth - 1
      end
    end
  end
  -- a function's parameters: the names in the first parentheses after the first `function`
  for k, tk in ipairs(toks) do
    if tk.t == "name" and tk.s == "function" then
      local j = k + 1
      while toks[j] and toks[j].s ~= "(" do j = j + 1 end
      j = j + 1
      while toks[j] and toks[j].s ~= ")" do
        if toks[j].t == "name" or toks[j].s == "..." then arity = arity + 1 end
        j = j + 1
      end
      break
    end
  end
  return { lines = lines, arity = arity, depth = deepest }
end

-- whether code token k starts a reference: a name that is not a keyword nor a field (after . or :)
local function starts(toks, k)
  local tk, prev = toks[k], toks[k - 1]
  return tk.t == "name" and not M.keywords[tk.s] and not (prev and (prev.s == "." or prev.s == ":"))
end

function M.refs(source)
  local toks, out = code(M.tokens(source)), {}
  for k = 1, #toks do
    if starts(toks, k) then
      local path, j = toks[k].s, k
      out[path] = true
      while toks[j + 1] and toks[j + 1].s == "." and toks[j + 2] and toks[j + 2].t == "name" do
        path, j = path .. "." .. toks[j + 2].s, j + 2
        out[path] = true
      end
    end
  end
  return out
end

function M.rename(source, old, new)
  local parts = {}
  for p in old:gmatch("[^%.]+") do parts[#parts + 1] = p end
  local all = M.tokens(source)
  local toks, at = {}, {}   -- code tokens, and each one's index in all
  for i, tk in ipairs(all) do
    if tk.t ~= "space" and tk.t ~= "comment" then
      at[#toks + 1] = i
      toks[#toks + 1] = tk
    end
  end
  local n, k = 0, 1
  while k <= #toks do
    local hit = starts(toks, k) and toks[k].s == parts[1]
    for p = 2, #parts do
      local dot, name = toks[k + 2 * p - 3], toks[k + 2 * p - 2]
      hit = hit and dot and dot.s == "." and at[k + 2 * p - 3] == at[k + 2 * p - 4] + 1 and name
        and name.s == parts[p] and at[k + 2 * p - 2] == at[k + 2 * p - 3] + 1
    end
    if hit then
      all[at[k]].s = new
      for j = at[k] + 1, at[k + 2 * #parts - 2] do all[j].s = "" end
      n, k = n + 1, k + 2 * #parts - 1
    else
      k = k + 1
    end
  end
  local out = {}
  for i, tk in ipairs(all) do out[i] = tk.s end
  return table.concat(out), n
end

return M
