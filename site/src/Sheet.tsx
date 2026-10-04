import type { ReactNode } from "react";

export const REPO = "https://github.com/OpenRelationship/tablua";

// One sheet of the form: its title block, the field ruler, then its lines on the cells.
export function Sheet(props: {
  id: string;
  n: number;
  of: number;
  label?: string;
  purpose: string;
  children: ReactNode;
  stamp?: ReactNode;
  after?: ReactNode;
}) {
  return (
    <section className="sheet" id={props.id} aria-labelledby={`${props.id}-title`}>
      <div className={`title-block${props.stamp ? " has-stamp" : ""}`}>
        <div>
          <span className="field-label">Program</span>
          <span className="field-value wordmark">TABLUA</span>
        </div>
        <div>
          <span className="field-label">{props.label ?? "Purpose"}</span>
          <span className="field-value">{props.purpose}</span>
        </div>
        <div>
          <span className="field-label">Sheet</span>
          <span className="field-value">{props.n} of {props.of}</span>
        </div>
        {props.stamp && <div className="stamp-cell">{props.stamp}</div>}
      </div>
      <div className="ruler" aria-hidden="true">
        <span>Seq</span>
        <span>T</span>
        <span>Statement</span>
        <span>By</span>
      </div>
      <Columns />
      <div className="cells">{props.children}</div>
      {props.after}
    </section>
  );
}

// The column ruler: a tick on every column, its number every tenth, on the sheet's major lines.
function Columns() {
  const tens = [10, 20, 30, 40, 50, 60, 70, 80];
  return (
    <div className="columns" aria-hidden="true">
      {tens.map((t) => (
        <span key={t} style={{ left: `calc(${t} * var(--cw))` }}>
          {t}
        </span>
      ))}
    </div>
  );
}

export function Line(props: { seq?: string; code?: string; by?: string; className?: string; children?: ReactNode }) {
  return (
    <span className={`line ${props.className ?? ""}`}>
      <span className="seq">{props.seq ?? ""}</span>
      <span className="code">{props.code ?? ""}</span>
      <span className="stmt">{props.children}</span>
      <span className="by">{props.by ?? ""}</span>
    </span>
  );
}

// A comment line: C in column 1, prose in the statement field.
export function Comment(props: { children: ReactNode }) {
  return (
    <Line className="comment" seq="C">
      {props.children}
    </Line>
  );
}

export const seq = (i: number) => String((i + 1) * 10).padStart(5, "0");
