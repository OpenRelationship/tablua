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
    // a course: the harness from nothing, one idea a module, for someone who knows none of its parts yet
    name: "Learn",
    pages: [
      { slug: "learn", file: "learn-index", title: "Learn Tablua: the course", nav: "The course" },
      { slug: "learn/loop", file: "learn-loop", title: "1. An agent is a loop" },
      { slug: "learn/rows", file: "learn-rows", title: "2. Writing it down as rows" },
      { slug: "learn/robot", file: "learn-robot", title: "3. Robot: saying what \"done\" means" },
      { slug: "learn/lua", file: "learn-lua", title: "4. Lua: the harness's language" },
      { slug: "learn/org", file: "learn-org", title: "5. Org: one file holds it all" },
      { slug: "learn/models", file: "learn-models", title: "6. Three models, three jobs" },
      { slug: "learn/learning", file: "learn-learning", title: "7. Learning from the past" },
      { slug: "learn/rules", file: "learn-rules", title: "8. Rules as data" },
      { slug: "learn/together", file: "learn-together", title: "9. Putting it together" },
    ],
  },
  {
    name: "Concepts",
    pages: [
      { slug: "concepts/log-and-build", file: "log-and-build", title: "The log and the build" },
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
      { slug: "guides/run-agent", file: "run-agent", title: "Run an agent in your host" },
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
