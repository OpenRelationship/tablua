import { computer, file } from "./data";
import { Comment, Line, Sheet, REPO } from "./Sheet";
import { Arrow } from "./icons";

// Sheet 5: the computer is in the same file. Moss's fields, the file's tables, and the end of the form.
export function Computer() {
  return (
    <Sheet
      id="computer"
      n={5}
      of={5}
      label="Parts"
      purpose="Moss · Shroomi · agent.sqlite"
      after={
        <div style={{ marginTop: "calc(var(--row) * 2)", display: "grid", gap: "var(--row)" }}>
          <h2 className="headline" style={{ padding: 0 }}>
            Read the <em>source.</em>
          </h2>
          <code className="listing" style={{ padding: 0, color: "var(--ink)", whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>
            git clone {REPO}.git
          </code>
          <p style={{ margin: 0 }}>
            <a className="stamp" href={REPO}>
              OpenRelationship/tablua <Arrow />
            </a>
          </p>
        </div>
      }
    >
      <h2 className="sheet-title" id="computer-title">Each agent has a computer of its own.</h2>
      <Comment>
        Moss is the agent's computer: an operating system on the BEAM where the agent works, tests what it builds
        and keeps its files. Shroomi is how it shows its work, pages and apps a person can open.
      </Comment>
      {computer.map((c) => (
        <Line key={c.field} code="K">
          <span className="key">{c.field.padEnd(10)}</span>
          {c.value}
        </Line>
      ))}
      <Line code="$">sqlite3 agent.sqlite .tables</Line>
      {file.map((f) => {
        const [name, ...rest] = f.split(/\s{2,}/);
        return (
          <Line key={name} code="T">
            <span className="key">{name.padEnd(19)}</span>
            {rest.join(" ")}
          </Line>
        );
      })}
      <Comment>
        Two languages, Elixir and Lua. No WebAssembly, and no native code an agent can reach. Arock, a Mac and
        iPhone app and a server for thousands of computers, is built on Tablua.
      </Comment>
    </Sheet>
  );
}
