-- What a published page may hold. The host enforces it on every page, outside the agent's own run, so a page
-- written without Shroomi's helpers is held to it too: anything not named here is taken out.
--
--   tags        the elements a page may use (script, style, iframe, object, embed, base, meta, link: never)
--   attributes  every element's, then each element's own; data-*, aria-* and the hx- names in `hx` too
--   urls        the attributes that hold an address, and the schemes allowed (a relative address always is)
--   assets      the only scripts and styles a page loads, served by the host, by their SHA-384
-- Pure data: no require, no function, so any host reads it as a table.
local P = {}

local function set(list)
  local s = {}
  for _, k in ipairs(list) do s[k] = true end
  return s
end

P.tags = set({
  "a", "abbr", "address", "article", "aside", "b", "blockquote", "br", "button", "caption", "cite", "code", "col",
  "colgroup", "data", "dd", "del", "details", "dfn", "dialog", "div", "dl", "dt", "em", "fieldset", "figcaption",
  "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "i", "img", "input",
  "ins", "kbd", "label", "legend", "li", "main", "mark", "menu", "meter", "nav", "ol", "optgroup", "option",
  "output", "p", "picture", "pre", "progress", "q", "s", "samp", "search", "section", "select", "small", "source",
  "span", "strong", "sub", "summary", "sup", "table", "tbody", "td", "textarea", "tfoot", "th", "thead", "time",
  "tr", "u", "ul", "var", "wbr",
  -- icons: inline SVG shapes only
  "svg", "path", "circle", "rect", "line", "polyline", "polygon", "g", "ellipse",
})

P.attributes = {
  ["*"] = set({ "class", "id", "title", "role", "lang", "dir", "hidden", "tabindex", "style", "slot" }),
  a = set({ "href", "target", "rel", "download" }),
  img = set({ "src", "alt", "width", "height", "loading", "decoding", "srcset", "sizes" }),
  source = set({ "src", "srcset", "type", "media", "sizes" }),
  form = set({ "action", "method", "autocomplete", "novalidate" }),
  input = set({ "type", "name", "value", "placeholder", "checked", "disabled", "required", "readonly", "min", "max",
    "step", "pattern", "minlength", "maxlength", "autocomplete", "autofocus", "list", "multiple", "size", "accept" }),
  button = set({ "type", "name", "value", "disabled", "autofocus", "popovertarget", "popovertargetaction" }),
  select = set({ "name", "multiple", "disabled", "required", "size" }),
  option = set({ "value", "selected", "disabled", "label" }),
  optgroup = set({ "label", "disabled" }),
  textarea = set({ "name", "rows", "cols", "placeholder", "disabled", "required", "readonly", "maxlength", "wrap" }),
  label = set({ "for" }), output = set({ "for", "name" }), fieldset = set({ "disabled", "name" }),
  td = set({ "colspan", "rowspan", "headers" }), th = set({ "colspan", "rowspan", "scope", "headers", "abbr" }),
  col = set({ "span" }), colgroup = set({ "span" }),
  ol = set({ "start", "reversed", "type" }), li = set({ "value" }),
  time = set({ "datetime" }), data = set({ "value" }), del = set({ "datetime", "cite" }), ins = set({ "datetime", "cite" }),
  blockquote = set({ "cite" }), q = set({ "cite" }),
  details = set({ "open", "name" }), dialog = set({ "open" }),
  progress = set({ "value", "max" }), meter = set({ "value", "min", "max", "low", "high", "optimum" }),
  svg = set({ "viewBox", "width", "height", "fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
    "xmlns", "aria-hidden" }),
  path = set({ "d", "fill", "stroke", "stroke-width", "fill-rule", "clip-rule", "stroke-linecap", "stroke-linejoin" }),
  circle = set({ "cx", "cy", "r", "fill", "stroke" }), ellipse = set({ "cx", "cy", "rx", "ry", "fill", "stroke" }),
  rect = set({ "x", "y", "width", "height", "rx", "ry", "fill", "stroke" }),
  line = set({ "x1", "y1", "x2", "y2", "stroke" }), polyline = set({ "points", "fill", "stroke" }),
  polygon = set({ "points", "fill", "stroke" }), g = set({ "fill", "stroke", "transform" }),
}

-- htmx's attributes a page may use: requests and how their answers land; never hx-on (script) or hx-vars (eval)
P.hx = set({ "hx-get", "hx-post", "hx-put", "hx-patch", "hx-delete", "hx-target", "hx-swap", "hx-trigger",
  "hx-confirm", "hx-vals", "hx-select", "hx-include", "hx-indicator", "hx-push-url", "hx-boost", "hx-params",
  "hx-disabled-elt", "hx-swap-oob", "hx-select-oob", "hx-sync" })

P.urls = {
  attributes = set({ "href", "src", "action", "cite", "hx-get", "hx-post", "hx-put", "hx-patch", "hx-delete",
    "hx-push-url" }),
  schemes = set({ "http", "https", "mailto", "tel" }),
}

P.assets = {
  css = "/shroomi/basecoat-1.0.2.min.css",
  htmx = "/shroomi/htmx-2.0.4.min.js",
  basecoat = "/shroomi/basecoat-1.0.2.min.js",
  shroomi = "/shroomi/shroomi.js",
  files = {
    ["shroomi.js"] = "sha384-TSAT3IHLu70OM0/KHq++v+Ln+Ts3x4+Xn6USRI7tbB2ZWC4z06+XQJbppBnzAhul",
    ["basecoat-1.0.2.min.css"] = "sha384-XWKdrxzE2X33lI8Q03C9fIbqdLWV11whVNycR2/3bMNJY73EEQOa7rmN+SeiSCor",
    ["htmx-2.0.4.min.js"] = "sha384-HGfztofotfshcF7+8n44JQL2oJmowVChPTg48S+jvZoztPfvwD79OC/LTtG6dMp+",
    ["basecoat-1.0.2.min.js"] = "sha384-rD2ZCuReXV7nIneJcn1lsTn6yOv87YARLQyUsemVAxrYYHdy5hcAW8XZEQxx87Dj",
  },
}

return P
