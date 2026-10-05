// docs.tablua.com: content/*.md rendered to static HTML pages in dist/, one folder per page, with the sidebar,
// the page's contents, previous and next, a search index and a sitemap. No framework runs in the reader's
// browser; assets/docs.js adds search, copy buttons and the phone menu on top of pages that work without it.
//
//   bun docs/build.ts            build dist/
//   bun docs/build.ts --watch    build, serve on http://localhost:4318 and rebuild on every change
import { cpSync, mkdirSync, readFileSync, rmSync, statSync, watch, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { Marked, type Tokens } from "marked";
import { pages } from "./nav";
import { placeDiagrams } from "./diagrams";
import { layout, type Built } from "./template";

const here = dirname(new URL(import.meta.url).pathname);
const out = join(here, "dist");
export const SITE = "https://docs.tablua.com";

const slugify = (s: string) =>
  s.toLowerCase().replace(/<[^>]+>/g, "").replace(/&[a-z]+;/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const escape = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// front matter: a description line between --- fences, then the page's Markdown
function read(file: string): { description: string; body: string } {
  const text = readFileSync(join(here, "content", file + ".md"), "utf8");
  const m = text.match(/^---\n([\s\S]*?)\n---\n/);
  const description = m?.[1].match(/^description:\s*(.+)$/m)?.[1].trim() ?? "";
  return { description, body: m ? text.slice(m[0].length) : text };
}

// GitHub's alert syntax, > [!NOTE] and the rest, as asides
function callouts(html: string): string {
  const names: Record<string, string> = { NOTE: "Note", TIP: "Tip", IMPORTANT: "Important", WARNING: "Watch out" };
  return html.replace(
    /<blockquote>\s*<p>\[!(NOTE|TIP|IMPORTANT|WARNING)\]\s*/g,
    (_, k) => `<blockquote class="callout callout-${k.toLowerCase()}"><p class="callout-t">${names[k]}</p><p>`,
  );
}

function render(body: string) {
  const toc: { depth: number; text: string; id: string }[] = [];
  const md = new Marked({ gfm: true });
  md.use({
    renderer: {
      heading(this: any, { tokens, depth }: Tokens.Heading) {
        const inner = this.parser.parseInline(tokens);
        const id = slugify(inner);
        if (depth === 2 || depth === 3) toc.push({ depth, text: inner.replace(/<[^>]+>/g, ""), id });
        if (depth === 1) return `<h1>${inner}</h1>\n`;
        return `<h${depth} id="${id}"><a class="anchor" href="#${id}" aria-hidden="true" tabindex="-1">#</a>${inner}</h${depth}>\n`;
      },
      code({ text, lang }: Tokens.Code) {
        const label = lang ? `<span class="lang">${escape(lang)}</span>` : "";
        return `<div class="code">${label}<pre><code>${escape(text)}</code></pre></div>\n`;
      },
      table(this: any, token: Tokens.Table) {
        const cell = (c: Tokens.TableCell, tag: string) => `<${tag}>${this.parser.parseInline(c.tokens)}</${tag}>`;
        const head = `<tr>${token.header.map((c) => cell(c, "th")).join("")}</tr>`;
        const rows = token.rows.map((r) => `<tr>${r.map((c) => cell(c, "td")).join("")}</tr>`).join("");
        return `<div class="table"><table><thead>${head}</thead><tbody>${rows}</tbody></table></div>\n`;
      },
    },
  });
  const html = callouts(placeDiagrams(md.parse(body) as string));
  const entities: Record<string, string> = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": '"', "&#39;": "'" };
  const text = html.replace(/<figure[\s\S]*?<\/figure>/g, " ").replace(/<[^>]+>/g, " ")
    .replace(/&(amp|lt|gt|quot|#39);/g, (e) => entities[e]).replace(/\s+/g, " ").trim();
  return { html, toc, text };
}

export function build() {
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  const built: Built[] = pages.map((p) => ({ ...p, ...read(p.file), ...render(read(p.file).body) }));
  const index: object[] = [];
  built.forEach((b, i) => {
    const dir = join(out, b.slug);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "index.html"), layout(b, built, built[i - 1], built[i + 1]));
    index.push({ t: b.title, u: "/" + b.slug, s: b.section, h: b.toc.map((x) => x.text), x: b.text.slice(0, 3000) });
  });
  const missing: Built = {
    slug: "404", file: "", title: "Page not found", section: "", toc: [], text: "",
    description: "This page does not exist.",
    html: `<h1>Page not found</h1><p>There is no page here. Try the search above, or start from the <a href="/">introduction</a>.</p>`,
  };
  writeFileSync(join(out, "404.html"), layout(missing, built));
  writeFileSync(join(out, "search.json"), JSON.stringify(index));
  writeFileSync(join(out, "sitemap.xml"), `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${built.map((b) => `  <url><loc>${SITE}/${b.slug}</loc></url>`).join("\n")}
</urlset>
`);
  writeFileSync(join(out, "robots.txt"), `User-agent: *\nAllow: /\nSitemap: ${SITE}/sitemap.xml\n`);
  cpSync(join(here, "assets"), join(out, "assets"), { recursive: true });
  cpSync(join(here, "..", "public", "favicon.svg"), join(out, "favicon.svg"));
  const fonts = join(here, "..", "node_modules", "@fontsource-variable");
  mkdirSync(join(out, "assets", "fonts"), { recursive: true });
  cpSync(join(fonts, "geist", "files", "geist-latin-wght-normal.woff2"), join(out, "assets", "fonts", "geist.woff2"));
  cpSync(join(fonts, "geist-mono", "files", "geist-mono-latin-wght-normal.woff2"), join(out, "assets", "fonts", "geist-mono.woff2"));
  return built.length;
}

if (import.meta.main) {
  console.log(`built ${build()} pages into ${out}`);
  if (process.argv.includes("--watch")) {
    for (const d of ["content", "assets", "."]) {
      watch(join(here, d), { recursive: d !== "." }, (_, name) => {
        if (String(name).includes("dist")) return;
        try { console.log(`rebuilt ${build()} pages (${name})`); } catch (e) { console.error(String(e)); }
      });
    }
    Bun.serve({
      port: 4318,
      fetch(req) {
        const path = decodeURIComponent(new URL(req.url).pathname);
        const isFile = (f: string) => { try { return statSync(f).isFile(); } catch { return false; } };
        const file = [join(out, path), join(out, path, "index.html")].find(isFile);
        return new Response(Bun.file(file ?? join(out, "404.html")), { status: file ? 200 : 404 });
      },
    });
    console.log("serving http://localhost:4318");
  }
}
