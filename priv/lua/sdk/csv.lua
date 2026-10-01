-- csv: comma-separated text to rows and back (RFC 4180: quoted fields, "" for a quote, newlines inside quotes).
--
--   csv.parse(text)                      -> { {"a","b"}, {"1","2"} }
--   csv.parse(text, { header = true })   -> { {a="1", b="2"} }, the first row naming the fields
--   csv.encode(rows [, fields])          -> text; rows are lists, or records written in `fields` order
local csv = {}

function csv.parse(text, opts)
  opts = opts or {}
  local sep = opts.sep or ","
  local rows, row, field, i, n = {}, {}, {}, 1, #text
  local quoted = false
  local function cell() row[#row + 1] = table.concat(field) field = {} end
  local function line() cell() rows[#rows + 1] = row row = {} end
  while i <= n do
    local c = string.sub(text, i, i)
    if quoted then
      if c == '"' then
        if string.sub(text, i + 1, i + 1) == '"' then field[#field + 1] = '"' i = i + 1 else quoted = false end
      else
        field[#field + 1] = c
      end
    elseif c == '"' then
      quoted = true
    elseif c == sep then
      cell()
    elseif c == "\r" then
      -- part of \r\n
    elseif c == "\n" then
      line()
    else
      field[#field + 1] = c
    end
    i = i + 1
  end
  if #field > 0 or #row > 0 then line() end
  if not opts.header then return rows end
  local names, out = table.remove(rows, 1) or {}, {}
  for _, r in ipairs(rows) do
    local rec = {}
    for j, name in ipairs(names) do rec[name] = r[j] or "" end
    out[#out + 1] = rec
  end
  return out, names
end

local function quote(v)
  v = tostring(v == nil and "" or v)
  if string.find(v, '[,"\r\n]') then return '"' .. string.gsub(v, '"', '""') .. '"' end
  return v
end

function csv.encode(rows, fields)
  local lines = {}
  if fields then
    local head = {}
    for j, f in ipairs(fields) do head[j] = quote(f) end
    lines[1] = table.concat(head, ",")
  end
  for _, r in ipairs(rows) do
    local cells = {}
    if fields then
      for j, f in ipairs(fields) do cells[j] = quote(r[f]) end
    else
      for j, v in ipairs(r) do cells[j] = quote(v) end
    end
    lines[#lines + 1] = table.concat(cells, ",")
  end
  return table.concat(lines, "\n") .. "\n"
end

return csv
