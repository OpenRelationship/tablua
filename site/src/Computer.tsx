import { computer, file } from "./data";

// The computer a host gives the agent, and the tables of its one file.
export function Computer() {
  return (
    <section className="block" id="computer">
      <div className="wrap split">
        <div className="stack">
          <div>
            <h2>The host gives it a computer.</h2>
            <p className="intro">
              Tablua decides and records; the work happens on whatever computer the host embeds it in. The host
              hands the harness the facts and the moves, does each move, and keeps the rows.
            </p>
            <p className="intro" style={{ marginTop: -36 }}>
              Embeddable by default: it reaches nothing but the ports it is given. Give it an API or a sandbox and it
              can reach anything else.
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
