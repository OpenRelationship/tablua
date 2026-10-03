-- .lui: a page as HTML with Lua in it (Arock's feature file-kinds), compiled to Shroomi's elements so escaping, the
-- class check and the policy stay one path. A <lua> block on top, markup below:
--
--   <lua>
--     local d = db.open("data/plants.dbl")
--     page.title = "Plants"
--     function post.water(req) d:exec("update plant set watered = ? where name = ?", today, req.form.name) end
--   </lua>
--   <card title="Plants">
--     {% for _, p in ipairs(d:query("select * from plant")) do %}
--       <p>{{ p.name }} <button post="water" vals={{ {name = p.name} }}>Water</button></p>
--     {% end %}
--   </card>
--
--   {{ e }} text, escaped      {{{ e }}} markup as is (still cleaned)      {% lua %} a statement
--   attr="text {{ e }}"  a string     attr={{ e }}  the value itself (a table, a boolean)     attr  true
--   every tag closed (<x/> or </x>; br, hr, img, input, icon, empty, progress, checkbox and switch are whole
--   alone); kit components are tags
--   <slot name="footer">...</slot> inside an element gives it that prop as markup (a card's footer, say)
--   post="name" or get="name" is the page's action of that name (shroomi.page): the page is rendered again
--   req is { method, path, query = {k = v}, form = {k = v} } (nothing else); page.title is the title;
--   result is what the last action returned, {} when none (so write (result.errors or {}).email)
--   a page is its body (Shroomi writes <html>, <head> and <body>); db, fs, http, json, date and csv are there
--   already. The file is one <lua> block, closed by </lua>, then the markup, and
--   nothing around them (no <lui>, <html> or <layout>). lui.template(app) is a whole page to start from
--
--   lui.compile(text, name) -> Lua source, or nil and "name:line: why" (an unknown tag, class or action,
--     a tag left open, a Jinja habit)
--   lui.load(text, name [, src [, opts]]) -> def for shroomi.page.answer and { line } (the page line running), or
--     nil and why; src is lui.compile's output for this text and name, when the host kept it; opts.lines puts
--     each element's line in the page's source on it as data-line, for a host that looks at the page itself
--   lui.answer(text, name, req [, src [, opts]]) -> what shroomi.page.answer gives, and each {{ e }} that was nil
local ui = require("shroomi")
local css = require("shroomi.css")
local policy = require("shroomi.policy")
local page = require("shroomi.page")
local scan = require("shroomi.lui_scan")
local icons = require("shroomi.icons")

local lui = {}

local VOID = { area = true, br = true, col = true, hr = true, img = true, input = true, wbr = true, source = true }
-- kit components that never hold anything: <icon name="x"> is whole, as <br> is
local SELF = { icon = true, empty = true, progress = true, skeleton = true, checkbox = true, switch = true }
local KEEP = { pre = true, textarea = true, code = true }
local BODY = "a page is its body: Shroomi writes <html>, <head> and <body> (page.title sets the title)"
local NEVER = { script = "behaviour comes from Shroomi's own scripts, never a page's",
  html = BODY, head = BODY, body = BODY, title = BODY,
  style = "style with classes; Shroomi writes the CSS", iframe = "a page holds no other page",
  link = "Shroomi loads the only styles", meta = "Shroomi writes the head", base = "Shroomi writes the head" }

local function q(s)
  return '"' .. string.gsub(s, '[%c"\\]', function(c)
    if c == "\n" then return "\\n" end
    if c == '"' or c == "\\" then return "\\" .. c end
    return string.format("\\%03d", string.byte(c))
  end) .. '"'
end

-- what the page's own Lua declares: components, and its post and get actions
local function declared(block)
  local found = { components = {}, post = {}, get = {} }
  for n in string.gmatch(block, "ui%.component%(%s*[\"']([%w_]+)[\"']") do found.components[n] = true end
  for verb in pairs({ post = true, get = true }) do
    for n in string.gmatch(block, "function%s+" .. verb .. "%.([%a_][%w_]*)") do found[verb][n] = true end
    for n in string.gmatch(block, "%f[%w_]" .. verb .. "%.([%a_][%w_]*)%s*=[^=]") do found[verb][n] = true end
  end
  return found
end

-- Lua's complaint about the page's Lua as "name:line: why": luex says "Parse Error at line 2, column 13" and
-- shows the compiled source, which is not what the agent wrote
local function lua_error(why, name)
  local line = string.match(why, "at line (%d+)")
  if not line then return why end
  local what = string.match(why, "at line %d+[^\n]*\n%s*([^\n]+)")
  return name .. ":" .. line .. ": " .. (what or "the Lua does not parse")
end

-- a whole page to start from, as `new page` gives it: a table, a list, an action that adds and one that removes
function lui.template(app)
  app = app or "items"
  return (string.gsub([==[
<lua>
  local d = db.open("data/APP.dbl")
  d:exec("create table if not exists item (id integer primary key, name text not null)")
  page.title = "<A title>"

  function post.add(req)
    if (req.form.name or "") ~= "" then d:exec("insert into item (name) values (?)", req.form.name) end
  end

  function post.remove(req) d:exec("delete from item where id = ?", tonumber(req.form.id)) end

  local items = d:query("select * from item order by name")
</lua>
<container>
  <card title="<A title>" description="<what it is for>">
    {% if #items == 0 then %}<empty title="Nothing yet" description="Add the first one."/>{% end %}
    <ul class="space-y-2">
      {% for _, it in ipairs(items) do %}
        <li class="flex items-center justify-between">{{ it.name }}
          <button size="sm" variant="ghost" post="remove" vals={{ { id = it.id } }}><icon name="trash"/></button>
        </li>
      {% end %}
    </ul>
    <slot name="footer">
      <form post="add" class="flex gap-2">
        <input name="name" placeholder="New" required/>
        <button>Add</button>
      </form>
    </slot>
  </card>
</container>
]==], "APP", app):gsub("^\n", ""))
end

local KEYWORDS = {}
for w in string.gmatch("and break do else elseif end false for function goto if in local nil not or repeat return then"
  .. " true until while", "%a+") do KEYWORDS[w] = true end

function lui.compile(text, name)
  name = name or "page.lui"
  local ok, src = pcall(function()
    local st = scan.new(text, name)
    local out, oline = {}, 1
    local function emit(code, at)
      while oline < at do out[#out + 1] = "\n"; oline = oline + 1 end
      out[#out + 1] = code
      local _, n = string.gsub(code, "\n", "")
      oline = oline + n
    end
    local block = st:lua_block()
    local known = declared(block and block.code or "")
    emit("local req, post, get, page, ui, __el, __raw, __s, __at, __flag = ... ", 1)
    -- the line running, for a VM whose errors carry none (luex)
    local marked
    local function mark(line)
      if line ~= marked then emit("__at.line = " .. line .. " ", line); marked = line end
    end
    if block then mark(block.line); emit(block.code, block.line) end
    emit(" return function(result) local __c = {} ", st.line)

    local open = {}
    local function check_tag(tag, line)
      if NEVER[tag] then st:fail(line, "no <" .. tag .. "> on a page: " .. NEVER[tag]) end
      if tag == "lua" then st:fail(line, "a page has one <lua> block, at its top") end
      if not (policy.tags[tag] or known.components[tag] or ui[tag]) then
        st:fail(line, "<" .. tag .. "> is no element a page may use nor a kit component (ui.kit lists the kit)")
      end
    end
    local function check_attr(tag, a)
      if tag == "icon" and a.name == "name" and a.literal and not icons[a.literal] then
        st:fail(a.line, 'no icon "' .. a.literal .. '": the kit has ' .. table.concat(ui.icons, " "))
      elseif tag == "form" and (a.name == "action" or a.name == "method") then
        st:fail(a.line, a.name .. '= sends the browser away from the page: a form posts to its page with post="add"' ..
          ' and function post.add(req) in the <lua> block')
      elseif a.name == "class" then
        for _, word in ipairs(a.words) do
          if not css.known(word) then
            st:fail(a.line, 'no class "' .. word .. '": Shroomi knows Tailwind\'s utilities and the kit\'s classes' ..
              (string.find(word, "[", 1, true) and " (brackets hold only a length, in sizes and spacing: min-w-[200px])" or ""))
          end
        end
      elseif (a.name == "post" or a.name == "get") and a.literal and string.match(a.literal, "^[%a_][%w_]*$")
        and not known[a.name][a.literal] then
        st:fail(a.line, a.name .. '="' .. a.literal .. '" names no action: define function ' .. a.name .. "." ..
          a.literal .. "(req) in the <lua> block")
      end
    end
    local function attrs_code(tag, list)
      local parts = {}
      for _, a in ipairs(list) do
        if a.flag then
          parts[#parts + 1] = { "[__flag(" .. a.flag .. ")] = true, ", a.line }
        else
          check_attr(tag, a)
          -- a Lua word (<label for="name">) is a key only in brackets: for = ... is no Lua
          local key = string.match(a.name, "^[%a_][%w_]*$") and not KEYWORDS[a.name] and a.name or "[" .. q(a.name) .. "]"
          parts[#parts + 1] = { key .. " = " .. a.code .. ", ", a.line }
        end
      end
      return parts
    end

    -- space across lines between tags is layout, and dropped; beside text it is a space, as a browser shows it
    local CONTENT = { text = true, expr = true, raw = true }
    local last, pending
    while true do
      local tok = st:next(open[#open] and KEEP[open[#open].tag])
      if not tok then break end
      if tok.blank and not CONTENT[last] then
        pending = tok
      else
        if pending and CONTENT[tok.kind] then emit("__c[#__c + 1] = \" \" ", pending.line) end
        pending = nil
        if tok.kind ~= "stmt" then last = tok.kind end
      end
      mark(tok.line)
      if tok == pending then
        -- held until the next token says whether it is a space
      elseif tok.kind == "text" then
        emit("__c[#__c + 1] = " .. q(tok.text) .. " ", tok.line)
      elseif tok.kind == "expr" then
        emit("__c[#__c + 1] = __at.text((" .. tok.code .. "), " .. tok.line .. ", " .. q(tok.code) .. ") ", tok.line)
      elseif tok.kind == "raw" then
        emit("__c[#__c + 1] = __raw(" .. tok.code .. ") ", tok.line)
      elseif tok.kind == "stmt" then
        emit(" " .. tok.code .. " ", tok.line)
      elseif tok.kind == "open" and tok.tag == "slot" then
        -- <slot name="footer">...</slot>: markup given to the element around it as a prop
        local a = tok.attrs[1]
        if #tok.attrs ~= 1 or a.name ~= "name" or not a.literal or not string.match(a.literal, "^[%a_][%w_]*$") then
          st:fail(tok.line, 'a slot is <slot name="prop">, the prop of the element around it it fills')
        end
        if tok.closed then st:fail(tok.line, "a slot holds what it gives: <slot name=\"" .. a.literal .. "\">...</slot>") end
        if not open[#open] or open[#open].slot then st:fail(tok.line, "a slot fills a prop of the element around it") end
        emit(" do local __p, __c = __c, {} ", tok.line)
        open[#open + 1] = { tag = "slot", line = tok.line, slot = a.literal }
      elseif tok.kind == "open" then
        check_tag(tok.tag, tok.line)
        -- a field in a form sends its value under its name: without one the form sends nothing of it (a notes
        -- page's fields had id= and no name=, and its form added nothing)
        local in_form = false
        for _, o in ipairs(open) do in_form = in_form or o.tag == "form" end
        if in_form and (tok.tag == "input" or tok.tag == "textarea" or tok.tag == "select") then
          local named, kind = false, nil
          for _, a in ipairs(tok.attrs) do
            if a.name == "name" then named = true end
            if a.name == "type" then kind = a.literal end
          end
          if not named and kind ~= "submit" and kind ~= "button" and kind ~= "reset" then
            st:fail(tok.line, "<" .. tok.tag .. "> has no name=: a form sends a field's value as req.form.<name>")
          end
        end
        local alone = tok.closed or VOID[tok.tag] or SELF[tok.tag]
        emit(alone and "__c[#__c + 1] = __el(" .. tok.line .. ", " .. q(tok.tag) .. ", { "
          or " do local __p, __a, __c = __c, { ", tok.line)
        for _, p in ipairs(attrs_code(tok.tag, tok.attrs)) do emit(p[1], p[2]) end
        if alone then
          emit("}, {}) ", tok.line)
        else
          emit("}, {} ", tok.line)
          open[#open + 1] = { tag = tok.tag, line = tok.line }
        end
      elseif tok.kind == "close" and (VOID[tok.tag] or SELF[tok.tag]) then
        -- </br> or </icon> after one that was whole already: nothing to close, as a browser reads it
      elseif tok.kind == "close" then
        local top = open[#open]
        if not top then st:fail(tok.line, "</" .. tok.tag .. "> closes nothing") end
        if top.tag ~= tok.tag then
          st:fail(tok.line, "</" .. tok.tag .. "> closes <" .. top.tag .. ">, opened on line " .. top.line)
        end
        open[#open] = nil
        if top.slot then
          emit(" __a[" .. q(top.slot) .. "] = __c end ", tok.line)
        else
          emit("__p[#__p + 1] = __el(" .. top.line .. ", " .. q(top.tag) .. ", __a, __c) end ", tok.line)
        end
      end
    end
    if open[#open] then
      local top = open[#open]
      st:fail(top.line, "<" .. top.tag .. "> is never closed")
    end
    emit(" return __c end", st.line)
    return table.concat(out)
  end)
  if not ok then return nil, type(src) == "table" and src.why or tostring(src) end
  local chunk, why = load(src, "@" .. name, "t")
  if not chunk then return nil, lua_error(why, name) end
  return src
end

-- {{ e }} alone in a tag: the bare attribute e names, or none ("" is dropped by page.el)
local function flag(v)
  if type(v) == "string" and string.match(v, "^%a[%w%-]*$") then return v end
  return ""
end

local function cat(...)
  local out = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    out[i] = v == nil and "" or tostring(v)
  end
  return table.concat(out)
end

function lui.load(text, name, src, opts)
  name = name or "page.lui"
  local why
  if not src then src, why = lui.compile(text, name) end
  if not src then return nil, why end
  local chunk = load(src, "@" .. name, "t")
  -- at.nils: each {{ e }} that came out nil, once per line, for the host to show beside the page (a name the code
  -- never sets, e.days_left where it set days, shows as nothing and says nothing)
  local at = { line = 1, nils = {} }
  local seen = {}
  function at.text(v, line, code)
    if v == nil and not seen[line] then
      seen[line] = true
      at.nils[#at.nils + 1] = name .. ":" .. line .. ": {{ " .. string.gsub(code, "^%s*(.-)%s*$", "%1") .. " }}"
    end
    return v
  end
  return function(req, post, get, meta)
    at.nils, seen = {}, {}
    local el = page.el(req, post, get, name, opts and opts.lines)
    return chunk(req, post, get, meta, ui, el, ui.raw, cat, at, flag)
  end, at
end

function lui.answer(text, name, req, src, opts)
  name = name or "page.lui"
  local def, at = lui.load(text, name, src, opts)
  if not def then error(at, 0) end
  local ok, res = pcall(page.answer, def, req)
  if ok then return res, at.nils end
  res = tostring(res)
  if string.sub(res, 1, #name + 1) == name .. ":" then error(res, 0) end
  error(name .. ":" .. at.line .. ": " .. res, 0)
end

return lui
