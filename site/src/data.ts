// Example rows for the page. Every value here is illustrative: the shape is Tablua's, the numbers are not results.

export type Code = "S" | "C" | "D" | "A" | "O" | "R" | "G";
export type Row = { code: Code; text: string; by: string; mark?: "shipped" | "regressed" };

export const tableOf: Record<Code, string> = {
  S: "tablua_state",
  C: "tablua_candidate",
  D: "tablua_decision",
  A: "tablua_action",
  O: "tablua_outcome",
  R: "tablua_run",
  G: "tablua_gate",
};

// An example run building a small plants app, step by step.
export const run: Row[] = [
  { code: "S", text: "n=1  stage=no_feature  passed=0/0  stalls=0", by: "host" },
  { code: "C", text: "write_feature   jev_p=.82", by: "jev" },
  { code: "D", text: "chosen=write_feature  by=jev", by: "jev" },
  { code: "A", text: "write features/plants.feature  (4 scenarios)", by: "mercury" },
  { code: "O", text: "complete  progress=1  passed=0/4", by: "host" },
  { code: "S", text: "n=2  stage=building  passed=0/4  last=write_feature", by: "host" },
  { code: "C", text: "write_steps     jev_p=.61  p_progress=.52", by: "tabpfn" },
  { code: "C", text: "write_page      jev_p=.27  p_progress=.31", by: "tabpfn" },
  { code: "C", text: "rewrite         jev_p=.12  p_progress=.07", by: "tabpfn" },
  { code: "D", text: "chosen=write_steps  by=jev  propensity=1", by: "jev" },
  { code: "A", text: "write code/steps/plants.lua  (38 lines)", by: "mercury" },
  { code: "O", text: "complete  progress=1  passed=2/4", by: "host" },
  { code: "S", text: "n=3  stage=building  passed=2/4  last=write_steps", by: "host" },
  { code: "C", text: "rewrite         jev_p=.55  p_progress=.09", by: "tabpfn" },
  { code: "D", text: "chosen=rewrite  by=jev", by: "jev" },
  { code: "A", text: "rewrite code/plants.lua  (52 lines)", by: "mercury" },
  { code: "O", text: "broken  progress=0  passed=1/4  regressed=1", by: "host", mark: "regressed" },
  { code: "S", text: "n=4  stage=building  passed=1/4  last=rewrite", by: "host" },
  { code: "D", text: "chosen=undo  by=jev", by: "jev" },
  { code: "O", text: "complete  progress=1  passed=2/4", by: "host" },
  { code: "S", text: "n=5  stage=building  passed=2/4  last=undo", by: "host" },
  { code: "C", text: "write_page      jev_p=.70  p_progress=.66", by: "tabpfn" },
  { code: "D", text: "chosen=write_page  by=jev", by: "jev" },
  { code: "A", text: "write ui/index.lui  (61 lines)", by: "mercury" },
  { code: "O", text: "complete  progress=1  passed=4/4", by: "host" },
  { code: "S", text: "n=6  stage=ready  passed=4/4  pages_ok=1", by: "host" },
  { code: "D", text: "chosen=publish  by=jev", by: "jev" },
  { code: "R", text: "shipped=1  works=1  steps=6", by: "host", mark: "shipped" },
];

// Real time: the median seconds of each model's call in Arock's port traces (368 calls, 2026-09-30 to 10-03): Jev's
// decide 0.20 s, Mercury's fill 0.77 s, TabPFN's predict 3.0 s (on a cached fit). The host's rows are writes to the
// agent's own SQLite file and its checks on the agent's own computer, a few milliseconds.
export const latency = { jev: 0.2, mercury: 0.77, tabpfn: 3.0, host: 0.005, checks: 0.05 };

// Seconds from the row before until row i is written: one TabPFN call ranks every candidate at once, and one Jev
// call gives both its probabilities and its choice.
export function secondsBefore(i: number): number {
  const r = run[i];
  const prev = run[i - 1];
  if (r.code === "C") {
    if (prev?.code === "C") return 0;
    return r.by === "tabpfn" ? latency.tabpfn : latency.jev;
  }
  if (r.code === "D") return prev?.code === "C" && prev.by === "jev" ? 0 : latency.jev;
  if (r.code === "A") return latency.mercury;
  if (r.code === "O") return latency.checks;
  return latency.host;
}

export const steps = [
  {
    code: "S" as Code,
    name: "State",
    columns: "stage  passed  total  stalls  last_verb  last_outcome  cause  pages_ok",
    says: "Where the work stands when the agent decides: the stage, how many checks pass, how long it has stalled, what the last step did.",
  },
  {
    code: "C" as Code,
    name: "Candidates",
    columns: "move  jev_p  jev_conf  jev_margin  p_progress  p_ship  cost_q50",
    says: "Every move the agent could make now, one row each, with every model's number for it: the language model's probability, the tabular model's chance of progress.",
  },
  {
    code: "D" as Code,
    name: "Decision",
    columns: "chosen  by  propensity  policy",
    says: "The move taken, and who took it. Knowing who decided, and how likely the choice was, is what lets the agent learn from its own record without fooling itself.",
  },
  {
    code: "O" as Code,
    name: "Outcome",
    columns: "verb  outcome  progress  regressed  same_failure  passed  total",
    says: "How the step turned out, labelled by what it did: did more checks pass, did anything break, is it the same failure as before.",
  },
];

export type Gate = { id: string; when: string; withholds: string[] };

export const gates: Gate[] = [
  { id: "green_before_publish", when: "passed < total", withholds: ["publish"] },
  { id: "feature_before_code", when: "stage = no_feature", withholds: ["write_page", "write_steps"] },
  { id: "look_after_pages", when: "pages_ok = 0", withholds: ["answer_task"] },
];

export const moves = ["write_feature", "write_steps", "write_page", "fix_failure", "run_test", "look_at_app", "publish", "answer_task"];

export const computer = [
  { field: "PROCESS", value: "one per agent, on the BEAM" },
  { field: "DISK", value: "one SQLite file, its own" },
  { field: "LANGUAGE", value: "Lua, bounded in steps, memory and time" },
  { field: "SHELL", value: "its own; no real shell on any machine" },
  { field: "BROWSER", value: "headless, under the computer's web rules" },
  { field: "MAIL", value: "agents talk only by mail" },
  { field: "PAGES", value: "published through Shroomi as .lui files" },
];

export const file = [
  "events            the log: every step as it happened",
  "files             the computer's disk",
  "tablua_meta       the schema's version",
  "tablua_state      where the work stood",
  "tablua_candidate  every move it could make",
  "tablua_decision   the move taken, and by whom",
  "tablua_action     what the move did",
  "tablua_outcome    how it turned out",
  "tablua_run        how each run ended",
  "tablua_fit        the models fitted on it",
  "tablua_prediction  what they predicted",
  "tablua_gate       the policy, as rows",
];
