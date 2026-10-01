-- markdown: Markdown to HTML, the common part of CommonMark. Text is escaped, so what a page shows from Markdown
-- carries no markup of its own.
--
--   markdown.html(text)  # headings, paragraphs, *em* _em_ **strong** `code`, [links](url) ![images](url),
--                        fenced ``` code, - * + and 1. lists, > quotes, --- rules, hard breaks (two spaces)
local markdown = {}

local function esc(s)
  return (string.gsub(s, "[&<>\"]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }))
end

-- a link's address (already escaped), kept only if it is the web, mail, a page anchor or a path
local function href(url)
  url = string.match(url, "^%s*<?(.-)>?%s*$")
  local scheme = string.match(url, "^([%a][%w+.-]*):")
  if scheme and not ({ http = true, https = true, mailto = true })[string.lower(scheme)] then return "#" end
  return url
end

local function inline(s)
  local codes = {}
  -- code spans first, so nothing inside them is read as markup
  s = string.gsub(s, "(`+)(.-)%1", function(_, c)
    codes[#codes + 1] = "<code>" .. esc(string.match(c, "^ ?(.-) ?$")) .. "</code>"
    return "\1" .. #codes .. "\2"
  end)
  s = esc(s)
  s = string.gsub(s, "!%[(.-)%](%b())", function(alt, url)
    return "<img src=\"" .. href(string.sub(url, 2, -2)) .. "\" alt=\"" .. alt .. "\">"
  end)
  s = string.gsub(s, "%[(.-)%](%b())", function(text, url)
    return "<a href=\"" .. href(string.sub(url, 2, -2)) .. "\">" .. text .. "</a>"
  end)
  s = string.gsub(s, "%*%*(.-)%*%*", "<strong>%1</strong>")
  s = string.gsub(s, "__(.-)__", "<strong>%1</strong>")
  s = string.gsub(s, "%*([^%*]-)%*", "<em>%1</em>")
  s = string.gsub(s, "([^%w_])_([^_]-)_([^%w_])", "%1<em>%2</em>%3")
  s = string.gsub(s, "^_([^_]-)_([^%w_])", "<em>%1</em>%2")
  s = string.gsub(s, "([^%w_])_([^_]-)_$", "%1<em>%2</em>")
  s = string.gsub(s, "^_([^_]-)_$", "<em>%1</em>")
  s = string.gsub(s, "  \n", "<br>\n")
  return (string.gsub(s, "\1(%d+)\2", function(i) return codes[tonumber(i)] end))
end

local function split(text)
  local lines = {}
  text = string.gsub(text, "\r\n?", "\n")
  for line in string.gmatch(text .. "\n", "(.-)\n") do lines[#lines + 1] = line end
  return lines
end

local blocks

local function list_item(line)
  local ind, mark, rest = string.match(line, "^( ? ? ?)([%-%*%+]) +(.*)$")
  if mark then return "ul", rest, #ind end
  ind, mark, rest = string.match(line, "^( ? ? ?)(%d+)[%.%)] +(.*)$")
  if mark then return "ol", rest, #ind, tonumber(mark) end
end

blocks = function(lines)
  local out, i, n = {}, 1, #lines
  while i <= n do
    local line = lines[i]
    local fence, lang = string.match(line, "^ ? ? ?(```+)%s*([%w_+-]*)")
    if fence then
      local code = {}
      i = i + 1
      while i <= n and not string.match(lines[i], "^ ? ? ?" .. fence) do
        code[#code + 1] = lines[i]
        i = i + 1
      end
      local cls = lang ~= "" and " class=\"language-" .. lang .. "\"" or ""
      out[#out + 1] = "<pre><code" .. cls .. ">" .. esc(table.concat(code, "\n")) .. (#code > 0 and "\n" or "") ..
        "</code></pre>"
      i = i + 1
    elseif string.match(line, "^%s*$") then
      i = i + 1
    elseif string.match(line, "^ ? ? ?#") and string.match(line, "^ ? ? ?(#+) ") or string.match(line, "^ ? ? ?#+$") then
      local hashes, title = string.match(line, "^ ? ? ?(#+)%s*(.-)%s*#*%s*$")
      local level = math.min(#hashes, 6)
      out[#out + 1] = "<h" .. level .. ">" .. inline(title) .. "</h" .. level .. ">"
      i = i + 1
    elseif string.match(line, "^ ? ? ?([%-%*_])%s*%1%s*%1[%s%-%*_]*$") then
      out[#out + 1] = "<hr>"
      i = i + 1
    elseif string.match(line, "^ ? ? ?>") then
      local quote = {}
      while i <= n and string.match(lines[i], "^ ? ? ?>") do
        quote[#quote + 1] = string.match(lines[i], "^ ? ? ?> ?(.*)$")
        i = i + 1
      end
      out[#out + 1] = "<blockquote>\n" .. blocks(quote) .. "\n</blockquote>"
    elseif list_item(line) then
      local kind, _, _, start = list_item(line)
      local items, cur = {}, nil
      while i <= n do
        local k, rest = list_item(lines[i])
        if k == kind then
          cur = { rest }
          items[#items + 1] = cur
        elseif cur and string.match(lines[i], "^%s%s+%S") then
          cur[#cur + 1] = string.match(lines[i], "^%s%s?%s?%s?(.*)$")
        elseif cur and string.match(lines[i], "^%S") and not k and not string.match(lines[i - 1], "^%s*$") then
          cur[#cur + 1] = lines[i]
        else
          break
        end
        i = i + 1
      end
      local lis = {}
      for _, it in ipairs(items) do
        local inner = blocks(it)
        inner = string.gsub(inner, "^<p>(.-)</p>$", "%1")
        lis[#lis + 1] = "<li>" .. inner .. "</li>"
      end
      local open = kind == "ol" and start and start ~= 1 and "<ol start=\"" .. start .. "\">" or "<" .. kind .. ">"
      out[#out + 1] = open .. "\n" .. table.concat(lis, "\n") .. "\n</" .. kind .. ">"
    else
      local para = {}
      while i <= n and not string.match(lines[i], "^%s*$") and not string.match(lines[i], "^ ? ? ?```") and
        not string.match(lines[i], "^ ? ? ?#+ ") and not string.match(lines[i], "^ ? ? ?>") and
        not (#para > 0 and list_item(lines[i])) do
        para[#para + 1] = lines[i]
        i = i + 1
      end
      local text = table.concat(para, "\n")
      local last = para[#para]
      local setext = #para > 1 and (string.match(last, "^ ? ? ?=+%s*$") and "=" or string.match(last, "^ ? ? ?%-+%s*$") and "-")
      if setext then
        local level = setext == "=" and 1 or 2
        out[#out + 1] = "<h" .. level .. ">" .. inline(table.concat(para, "\n", 1, #para - 1)) .. "</h" .. level .. ">"
      else
        out[#out + 1] = "<p>" .. inline(string.gsub(text, "^%s+", "")) .. "</p>"
      end
    end
  end
  return table.concat(out, "\n")
end

function markdown.html(text)
  local body = blocks(split(tostring(text or "")))
  return body == "" and "" or body .. "\n"
end

return markdown
