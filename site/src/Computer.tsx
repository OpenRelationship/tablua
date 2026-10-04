import { computer, file } from "./data";

// Moss, the agent's own computer, and the tables of its one file.
export function Computer() {
  return (
    <section className="block" id="computer">
      <div className="wrap split">
        <div className="stack">
          <div>
            <h2>Each agent has a computer of its own.</h2>
            <p className="intro">
              Moss is the agent's computer, an operating system on the BEAM where it works, tests what it builds and
              keeps its files. Shroomi is how it shows its work: pages and apps a person can open.
            </p>
          </div>
          <ul className="facts">
            {computer.map((c) => (
              <li key={c.field}>
                <span className="k">{c.field.charAt(0) + c.field.slice(1).toLowerCase()}</span>
                <span>{c.value.charAt(0).toUpperCase() + c.value.slice(1)}</span>
              </li>
            ))}
          </ul>
        </div>
        <div className="panel">
          <div className="panel-head">
            <span className="mono">sqlite3 agent.sqlite .tables</span>
          </div>
          <ul className="file-list">
            {file.map((f) => {
              const [name, ...rest] = f.split(/\s{2,}/);
              return (
                <li key={name}>
                  <span className="tn">{name}</span>
                  <span className="td">{rest.join(" ")}</span>
                </li>
              );
            })}
          </ul>
        </div>
      </div>
    </section>
  );
}
