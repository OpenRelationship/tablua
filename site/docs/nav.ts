// docs.tablua.com's pages, in reading order. Four kinds, after Diátaxis: Start (first contact), Concepts (why and
// how it works), Guides (doing one thing) and Reference (looking one thing up). Each page is content/<file>.md.

export type Page = { slug: string; file: string; title: string; nav?: string };
export type Section = { name: string; pages: Page[] };

export const sections: Section[] = [
  {
    name: "Start here",
    pages: [
      { slug: "", file: "index", title: "What is Tablua?", nav: "Introduction" },
      { slug: "start/why-tables", file: "why-tables", title: "Why an agent as tables" },
      { slug: "start/tour", file: "tour", title: "A tour of one step" },
      { slug: "start/quickstart", file: "quickstart", title: "Quickstart" },
    ],
  },
  {
    name: "Concepts",
    pages: [
      { slug: "concepts/step-loop", file: "step-loop", title: "The step loop" },
      { slug: "concepts/three-models", file: "three-models", title: "Three models, one table" },
      { slug: "concepts/learning", file: "learning", title: "How Tablua learns" },
      { slug: "concepts/shared-experience", file: "shared-experience", title: "Shared experience" },
      { slug: "concepts/policy-as-data", file: "policy-as-data", title: "Policy as data" },
      { slug: "concepts/program-as-rows", file: "program-as-rows", title: "The program as rows" },
      { slug: "concepts/computer", file: "computer", title: "The agent's computer" },
    ],
  },
  {
    name: "Guides",
    pages: [
      { slug: "guides/embed", file: "embed", title: "Embed the harness in Lua" },
      { slug: "guides/query", file: "query", title: "Read an agent's file with SQL" },
      { slug: "guides/learning-modes", file: "learning-modes", title: "Turn learning on" },
      { slug: "guides/run-agent", file: "run-agent", title: "Run an agent on its computer" },
      { slug: "guides/gate-ab", file: "gate-ab", title: "Retire a gate with an A/B" },
    ],
  },
  {
    name: "Reference",
    pages: [
      { slug: "reference/tables", file: "tables", title: "Tables" },
      { slug: "reference/lua-api", file: "lua-api", title: "Lua API" },
      { slug: "reference/moves", file: "moves", title: "Stages and moves" },
      { slug: "reference/effects", file: "effects", title: "Effects vocabulary" },
      { slug: "reference/glossary", file: "glossary", title: "Glossary" },
      { slug: "reference/status", file: "status", title: "Status and roadmap" },
    ],
  },
];

export const pages: (Page & { section: string })[] = sections.flatMap((s) =>
  s.pages.map((p) => ({ ...p, section: s.name })),
);
