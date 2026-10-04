-- Markdown: text to safe HTML.
local spec = require("mono.spec")
local markdown = require("shroomi.markdown")

spec.test("markdown's common part becomes HTML, its text escaped and its links kept to safe schemes", function()
  spec.eq(markdown.html("# Plants\n\nA *fern* and **moss**, `x<y`.\n\n- one\n- [two](https://a.b/?q=1&r=2)\n\n" ..
    "```lua\nprint(1 < 2)\n```\n\n> quoted\n\n[bad](javascript:alert(1)) <script>"),
    "<h1>Plants</h1>\n<p>A <em>fern</em> and <strong>moss</strong>, <code>x&lt;y</code>.</p>\n<ul>\n<li>one</li>\n" ..
    "<li><a href=\"https://a.b/?q=1&amp;r=2\">two</a></li>\n</ul>\n<pre><code class=\"language-lua\">print(1 &lt; 2)\n" ..
    "</code></pre>\n<blockquote>\n<p>quoted</p>\n</blockquote>\n<p><a href=\"#\">bad</a> &lt;script&gt;</p>\n")
  spec.eq(markdown.html(""), "")
  spec.eq(markdown.html("Title\n====="), "<h1>Title</h1>\n")
  spec.eq(markdown.html("3. three\n4. four"), "<ol start=\"3\">\n<li>three</li>\n<li>four</li>\n</ol>\n")
end)

spec.run()
