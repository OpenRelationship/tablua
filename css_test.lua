-- Utility classes as CSS: Tailwind's names over Basecoat's theme, variants, cascade order, and nothing unknown.
local spec = require("mono.spec")
local css = require("shroomi.css")

local function rule(name)
  local r = css.rule(name)
  return r and r.css
end

spec.test("spacing, sizing and layout use the theme's spacing", function()
  spec.eq(rule("p-4"), ".p-4{padding: calc(var(--spacing) * 4);}")
  spec.eq(rule("gap-x-1.5"), ".gap-x-1\\.5{column-gap: calc(var(--spacing) * 1.5);}")
  spec.eq(rule("-mt-2"), ".-mt-2{margin-top: calc(calc(var(--spacing) * 2) * -1);}")
  spec.eq(rule("w-1/2"), ".w-1\\/2{width: 50%;}")
  spec.eq(rule("p-0"), ".p-0{padding: 0;}")
  spec.eq(rule("grid-cols-3"), ".grid-cols-3{grid-template-columns: repeat(3, minmax(0, 1fr));}")
  spec.eq(rule("max-w-2xl"), ".max-w-2xl{max-width: 42rem;}")
  spec.eq(rule("space-y-2"), ".space-y-2 > :not(:last-child){margin-block-end: calc(var(--spacing) * 2);}")
  spec.eq(rule("flex"), ".flex{display: flex;}")
end)

spec.test("colours are the theme's, with opacity", function()
  spec.eq(rule("text-muted-foreground"), ".text-muted-foreground{color: var(--color-muted-foreground);}")
  spec.eq(rule("bg-primary/10"),
    ".bg-primary\\/10{background-color: color-mix(in oklab, var(--color-primary) 10%, transparent);}")
  spec.eq(rule("border-border"), ".border-border{border-color: var(--color-border);}")
  spec.eq(rule("text-red-500"), nil)
end)

spec.test("variants: screens, states, groups and dark", function()
  spec.eq(rule("md:flex"), "@media (min-width: 48rem){.md\\:flex{display: flex;}}")
  spec.eq(rule("hover:bg-accent"), ".hover\\:bg-accent:hover{background-color: var(--color-accent);}")
  spec.eq(rule("dark:text-white"), ".dark\\:text-white:where(.dark, .dark *){color: #fff;}")
  spec.eq(rule("group-hover:underline"), ".group:hover .group-hover\\:underline{text-decoration-line: underline;}")
  spec.eq(rule("2xl:p-2"), "@media (min-width: 96rem){.\\32 xl\\:p-2{padding: calc(var(--spacing) * 2);}}")
  spec.eq(rule("wiggle:p-2"), nil)
  spec.eq(rule("md:lg:p-2"), nil)
end)

spec.test("nonsense is unknown, never CSS", function()
  for _, bad in ipairs({ "p-97", "p-1.25", "p-abc", "w-1/0", "opacity-33", "z-7", "p-", "-p", "", "bg-}{x",
    "text-[red]", "p-4;color:red" }) do
    spec.eq(css.rule(bad), nil, bad)
  end
end)

spec.test("a sheet holds each class once, later families after earlier, screens last", function()
  local sheet, unknown = css.sheet({ "md:p-2", "px-2", "p-4", "px-2", "mystery" })
  spec.same(unknown, { "mystery" })
  local p, px, md = string.find(sheet, ".p-4{", 1, true), string.find(sheet, ".px-2{", 1, true),
    string.find(sheet, "@media", 1, true)
  spec.ok(p < px and px < md)
  local _, count = string.gsub(sheet, "%.px%-2{", "")
  spec.eq(count, 1)
  spec.eq(string.sub(sheet, 1, 17), "@layer utilities{")
end)

spec.test("classes are read from a page's class attributes", function()
  spec.same(css.classes('<div class="a  b"><p class="c">x</p><i title="class=\\"no\\""></i></div>'), { "a", "b", "c" })
end)

spec.run()
