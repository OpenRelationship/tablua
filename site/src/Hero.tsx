import { useEffect, useRef, useState } from "react";
import { motion, useInView, useReducedMotion } from "framer-motion";
import { run, secondsBefore, tableOf } from "./data";
import { REPO } from "./links";
import { Arrow, GitHub } from "./icons";

const WINDOW = 7;
const READABLE_MS = 1300;   // a row at a time, slowed for reading
const PAUSE_MS = 4500;      // between one run and the next

// seconds since the run began, when row i was written, at the models' real speed
const at: number[] = [];
run.forEach((_, i) => (at[i] = (at[i - 1] ?? 0) + secondsBefore(i)));

// The claim, and an example run writing itself into the agent's file one row at a time.
export function Hero() {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useInView(ref, { amount: 0.3 });
  const still = useReducedMotion();
  const [count, setCount] = useState(WINDOW);
  const [real, setReal] = useState(false);

  useEffect(() => {
    if (still || !seen) return;
    const done = count >= run.length;
    const wait = done ? PAUSE_MS : real ? secondsBefore(count) * 1000 : READABLE_MS;
    const t = setTimeout(() => setCount(done ? (real ? 1 : WINDOW) : count + 1), wait);
    return () => clearTimeout(t);
  }, [count, seen, still, real]);

  const toggle = () => {
    setReal(!real);
    setCount(real ? WINDOW : 1);   // real time starts the run over, so its clock means something
  };

  const end = still ? run.length : count;
  const start = Math.max(0, end - WINDOW);
  const rows = run.slice(start, end).map((r, k) => ({ r, i: start + k }));

  return (
    <section className="hero" id="top">
      <div className="wrap">
        <h1>
          An agent is a table<span className="dot">.</span>
        </h1>
        <p className="lede">
          Tablua is an embeddable agent and its own computer. Everything it is and does is a typed row in one
          SQLite file, and a tabular model learns from those rows which moves make progress.
        </p>
        <div className="actions">
          <a className="btn btn-primary" href={REPO}>
            <GitHub /> View on GitHub
          </a>
          <a className="btn btn-quiet" href="#how">
            How it works <Arrow />
          </a>
        </div>

        <div className="table-frame" ref={ref} role="figure" aria-label="An example run, written as rows in the agent's file">
          <div className="table-bar">
            <span className="file">agent.sqlite</span>
            <span className="sub">·</span>
            <span className="sub">an example run</span>
            <span className={`note${real ? " clock" : ""}`}>{real ? `t = ${at[Math.max(0, end - 1)].toFixed(2)} s` : "illustrative values"}</span>
            <button
              type="button"
              className={`speed${real ? " on" : ""}`}
              aria-pressed={real}
              onClick={toggle}
              title="Real time: each row appears when the model behind it would answer (median latencies from Arock's traces). Off: slowed for reading."
            >
              <span className="knob" aria-hidden="true" />
              Real time
            </button>
          </div>
          <table className="grid">
            <thead>
              <tr>
                <th className="n">#</th>
                <th className="t">table</th>
                <th>row</th>
                <th className="by">written by</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(({ r, i }) => (
                <motion.tr
                  key={i}
                  layout={!still}
                  className={i === end - 1 && !still ? "new" : ""}
                  initial={still || (!real && i < WINDOW) ? false : { opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: real ? 0.15 : 0.5, ease: [0.16, 1, 0.3, 1] }}
                >
                  <td className="n">{i + 1}</td>
                  <td className="t">{tableOf[r.code].replace("tablua_", "")}</td>
                  <td className="what">
                    {r.text}
                    {r.mark && <span className={`tag tag-${r.mark}`}>{r.mark}</span>}
                  </td>
                  <td className="by">{r.by}</td>
                </motion.tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </section>
  );
}
