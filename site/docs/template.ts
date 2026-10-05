// The page around each document: the bar with search, the sidebar of every page, the page itself with previous
// and next, and its contents on the right.
import { sections, type Page } from "./nav";

export type Built = Page & {
  section: string;
  description: string;
  html: string;
  text: string;
  toc: { depth: number; text: string; id: string }[];
};

const REPO = "https://github.com/OpenRelationship/tablua";
const SITE = "https://docs.tablua.com";
const attr = (s: string) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");

const logo = `<svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><rect x="2.5" y="3.5" width="19" height="17" rx="3.5" stroke="#0c0e13" stroke-width="1.6"/><rect x="2.5" y="9.5" width="19" height="5" fill="#2152e8"/><path d="M9 3.5v17" stroke="#0c0e13" stroke-width="1.6"/></svg>`;
const github = `<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/></svg>`;

function sidebar(current: string): string {
  return sections
    .map(
      (s) => `<div class="side-group"><p class="side-h">${s.name}</p><ul>${s.pages
        .map((p) => {
          const here = p.slug === current;
          return `<li><a href="/${p.slug}"${here ? ' aria-current="page" class="here"' : ""}>${p.nav ?? p.title}</a></li>`;
        })
        .join("")}</ul></div>`,
    )
    .join("");
}

function pager(prev?: Built, next?: Built): string {
  const link = (p: Built | undefined, dir: string) =>
    p ? `<a class="pg pg-${dir}" href="/${p.slug}"><small>${dir === "prev" ? "Previous" : "Next"}</small><span>${p.nav ?? p.title}</span></a>` : "<span></span>";
  return `<nav class="pager" aria-label="Previous and next">${link(prev, "prev")}${link(next, "next")}</nav>`;
}

function contents(b: Built): string {
  if (b.toc.length < 2) return "";
  return `<aside class="toc" aria-label="On this page"><p class="side-h">On this page</p><ul>${b.toc
    .map((t) => `<li class="d${t.depth}"><a href="#${t.id}">${t.text}</a></li>`)
    .join("")}</ul></aside>`;
}

export function layout(b: Built, all: Built[], prev?: Built, next?: Built): string {
  const title = b.slug === "" ? "Tablua docs" : `${b.title} · Tablua docs`;
  const url = `${SITE}/${b.slug}`;
  const edit = b.file ? `<a class="edit" href="${REPO}/blob/main/site/docs/content/${b.file}.md">Edit this page on GitHub</a>` : "";
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${attr(title)}</title>
<meta name="description" content="${attr(b.description)}">
${b.slug === "404" ? '<meta name="robots" content="noindex">' : `<link rel="canonical" href="${url}">`}
<meta property="og:title" content="${attr(title)}">
<meta property="og:description" content="${attr(b.description)}">
<meta property="og:url" content="${url}">
<meta property="og:type" content="article">
<meta name="theme-color" content="#ffffff">
<meta name="color-scheme" content="only light">
<meta name="darkreader-lock">
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="preload" href="/assets/fonts/geist.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="/assets/docs.css">
<script src="/assets/docs.js" defer></script>
</head>
<body>
<a class="skip" href="#main">Skip to the page</a>
<header class="bar">
  <button class="menu" type="button" aria-label="Open the list of pages" aria-expanded="false" aria-controls="side"><span></span></button>
  <a class="brand" href="/">${logo}<span>Tablua</span><span class="brand-docs">docs</span></a>
  <div class="search" role="search">
    <input id="q" type="search" placeholder="Search the docs" aria-label="Search the docs" autocomplete="off" spellcheck="false">
    <kbd>/</kbd>
    <ul id="results" role="listbox" hidden></ul>
  </div>
  <nav class="bar-links" aria-label="Elsewhere">
    <a class="opt" href="https://tablua.com">tablua.com</a>
    <a class="gh" href="${REPO}">${github}<span class="opt">GitHub</span></a>
  </nav>
</header>
<div class="shell">
  <nav class="side" id="side" aria-label="Pages">${sidebar(b.slug)}</nav>
  <main id="main">
    <article class="doc">
      ${b.section ? `<p class="crumb">${b.section}</p>` : ""}
      ${b.html}
      <footer class="doc-foot">${edit}${pager(prev, next)}</footer>
    </article>
    ${contents(b)}
  </main>
</div>
<footer class="site-foot"><span>Tablua · Apache-2.0</span><a href="${REPO}">GitHub</a><a href="https://tablua.com">tablua.com</a><span class="faint">${all.length} pages</span></footer>
</body>
</html>
`;
}
