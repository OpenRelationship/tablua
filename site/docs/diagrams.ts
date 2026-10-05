// Diagrams a page places with a line {{diagram:<name>}}: plain HTML laid out by docs.css, so they read without
// JavaScript, reflow on a phone and stay text a screen reader and a search engine can read.

const step = (table: string, title: string, note: string) =>
  `<li><span class="t">${table}</span><b>${title}</b><small>${note}</small></li>`;

export const diagrams: Record<string, string> = {
  loop: `<figure class="dg">
  <ol class="flow">
    ${step("state", "Where the work stands", "written by the host from facts")}
    ${step("candidate", "Every move it could make", "with each model's number for it")}
    ${step("decision", "The move it took", "and who chose it")}
    ${step("action", "What the move did", "calls Mercury filled in")}
    ${step("outcome", "How it turned out", "checked by the host, not a model")}
  </ol>
  <p class="back"><span aria-hidden="true">↻</span> The outcome is the next step's starting point, and a labelled row the tabular model learns from.</p>
  <figcaption>One step of the loop. Each box is a row in a table of the agent's file.</figcaption>
</figure>`,

  file: `<figure class="dg">
  <div class="file">
    <div class="file-bar"><span class="mono">agent.sqlite</span><span>one file per agent</span></div>
    <div class="file-groups">
      <div><h4>The work</h4><p class="mono">state · candidate · decision · action · outcome · run</p></div>
      <div><h4>What it learns from</h4><p class="mono">label · effect · feature · fit · prediction</p></div>
      <div><h4>The program</h4><p class="mono">section · unit · scenario · line · link</p></div>
      <div><h4>Policy</h4><p class="mono">gate</p></div>
      <div><h4>The log</h4><p class="mono">events · args <span class="faint">(arock-log)</span></p></div>
      <div><h4>Its computer</h4><p class="mono">files · mail · pages <span class="faint">(Moss)</span></p></div>
    </div>
  </div>
  <figcaption>Everything an agent is and does lives in one SQLite file. Tablua's own tables all start with <code>tablua_</code>.</figcaption>
</figure>`,

  models: `<figure class="dg">
  <div class="cols3">
    <div class="card"><span class="t">Jev</span><b>Decides</b><p>Picks the next move from the moves allowed now, with a probability for each. Answers extra questions about the state in the same call.</p><small>median 0.20 s a call</small></div>
    <div class="card"><span class="t">TabPFN</span><b>Learns</b><p>Reads the agent's past rows and gives each move its chance of making progress. No training run: the rows are its context.</p><small>median 3.0 s a prediction</small></div>
    <div class="card"><span class="t">Mercury</span><b>Writes</b><p>Fills in the move it is given: the code, the test steps, the page. It never chooses what to do next.</p><small>median 0.77 s a call</small></div>
  </div>
  <figcaption>Three models, each with one job, each writing its own columns. Times are medians from 368 traced calls.</figcaption>
</figure>`,

  learn: `<figure class="dg">
  <ol class="flow flow4">
    ${step("rows", "Past steps", "this agent's, and others' when shared")}
    ${step("TabPFN", "Fit on the rows", "refit after 25 new outcomes")}
    ${step("ranking", "Each move's chance", "of making progress now")}
    ${step("decision", "Jev reads it, or it decides", "shadow, evidence or rank mode")}
  </ol>
  <p class="back"><span aria-hidden="true">↻</span> Every step's outcome becomes one more row, so the next ranking knows a little more.</p>
  <figcaption>The learning loop. Nothing is fine-tuned; the table grows and the model reads it.</figcaption>
</figure>`,

  share: `<figure class="dg">
  <div class="share">
    <div class="stack">
      <div class="box"><span class="mono">computer a</span><small>agent.sqlite</small></div>
      <div class="box"><span class="mono">computer b</span><small>agent.sqlite</small></div>
      <div class="box"><span class="mono">computer c</span><small>agent.sqlite</small></div>
    </div>
    <div class="arrow"><span>a run ends: its rows are copied, each task as <code>computer|task</code></span></div>
    <div class="box box-hi"><span class="mono">shared experience</span><small>one SQLite file per node</small></div>
    <div class="arrow"><span>attached and read beside the agent's own rows</span></div>
    <div class="box"><span class="mono">computer d</span><small>its next decision</small></div>
  </div>
  <figcaption>Agents on one node learn from each other's finished runs, never from a run still going.</figcaption>
</figure>`,
};

export function placeDiagrams(html: string): string {
  return html.replace(/<p>\{\{diagram:([a-z]+)\}\}<\/p>/g, (_, name) => {
    const d = diagrams[name];
    if (!d) throw new Error(`no diagram ${name}`);
    return d;
  });
}
