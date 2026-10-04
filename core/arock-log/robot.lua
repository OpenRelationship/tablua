-- The log as Robot Framework rows: one test per task, one keyword call per
-- event, in the space-separated format. Values are escaped so that Robot's
-- own unescaping gives back every byte:
--   * a space is literal only between two other characters; leading,
--     trailing and repeated spaces are \x20 (Robot splits cells on any run of
--     two whitespace characters, escaped or not, so "\ " is not enough);
--   * backslash, newline, CR and tab are \\ \n \r \t; other control bytes
--     and every Unicode space or line break are \xHH or \uHHHH;
--   * variable openers ${ @{ &{ %{ and a leading # get a backslash;
--   * the empty value is a lone backslash.
local M = {}

local SEP = "    "

local unicode_spaces = {
  ["\194\133"] = "\\x85", ["\194\160"] = "\\xa0", ["\225\154\128"] = "\\u1680",
  ["\226\128\168"] = "\\u2028", ["\226\128\169"] = "\\u2029", ["\226\128\175"] = "\\u202f",
  ["\226\129\159"] = "\\u205f", ["\227\128\128"] = "\\u3000",
}
for b = 128, 138 do
  unicode_spaces["\226\128" .. string.char(b)] = ("\\u20%02x"):format(b - 128)
end

local named = { ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

function M.cell(v)
  if v == "" then return "\\" end
  local out, n, i = {}, #v, 1
  while i <= n do
    local c = v:sub(i, i)
    local b = c:byte()
    local wide = b >= 194 and b <= 227 and (unicode_spaces[v:sub(i, i + 1)] and 2
      or unicode_spaces[v:sub(i, i + 2)] and 3)
    if wide then
      out[#out + 1] = unicode_spaces[v:sub(i, i + wide - 1)]
      i = i + wide - 1
    elseif named[c] then
      out[#out + 1] = named[c]
    elseif b < 32 or b == 127 then
      out[#out + 1] = ("\\x%02x"):format(b)
    elseif c == " " then
      out[#out + 1] = (i == 1 or i == n or out[#out] == " ") and "\\x20" or " "
    elseif c == "{" and (out[#out] == "$" or out[#out] == "@" or out[#out] == "&" or out[#out] == "%") then
      out[#out] = "\\" .. out[#out]
      out[#out + 1] = c
    elseif c == "#" and i == 1 then
      out[#out + 1] = "\\#"
    else
      out[#out + 1] = c
    end
    i = i + 1
  end
  return table.concat(out)
end

-- tests: list of { name = task, rows = { { keyword, args = {...} } } }
function M.render(tests)
  local lines = { "*** Test Cases ***" }
  for _, t in ipairs(tests) do
    lines[#lines + 1] = t.name
    for _, row in ipairs(t.rows) do
      local cells = { SEP .. row.keyword }
      for _, v in ipairs(row.args) do cells[#cells + 1] = M.cell(v) end
      lines[#lines + 1] = table.concat(cells, SEP)
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

return M
