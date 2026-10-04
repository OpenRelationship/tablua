import { useEffect, useRef, useState } from "react";
import { motion, useInView, useReducedMotion } from "framer-motion";
import { run } from "./data";
import { Line, Sheet, REPO, seq } from "./Sheet";
import { Arrow } from "./icons";

const WINDOW = 8;
const ease = [0.16, 1, 0.3, 1] as const;
// a typewriter's advance: the wipe moves one character at a time
const typed = (n: number) => (t: number) => Math.min(1, Math.ceil(t * n) / n);

// Sheet 1: the claim written large, and an example run filling the form one row at a time.
export function Run() {
  const ref = useRef<HTMLDivElement>(null);
  const seen = useInView(ref, { amount: 0.3 });
  const still = useReducedMotion();
  // the form starts empty and fills row by row; with motion reduced it shows how the run ended
  const [count, setCount] = useState(still ? run.length : 0);

  useEffect(() => {
    if (still) {
      setCount(run.length);
      return;
    }
    if (!seen) return;
    const done = count >= run.length;
    const t = setTimeout(() => setCount(done ? 0 : count + 1), done ? 5000 : count === 0 ? 500 : 1100);
    return () => clearTimeout(t);
  }, [count, seen, still]);

  const shown = run.slice(Math.max(0, count - WINDOW), count).map((r, k) => ({ r, i: Math.max(0, count - WINDOW) + k }));

  return (
    <Sheet
      id="run"
      n={1}
      of={5}
      purpose="An embeddable agent and its own computer"
      stamp={
        <a className="stamp" href={REPO}>
          Read the source <Arrow />
        </a>
      }
      after={<p className="example-note">Apache-2.0 · Elixir and Lua · the rows above are an example run, not results</p>}
    >
      <h1 className="headline" id="run-title">
        An agent is a <em>table.</em>
      </h1>
      <p className="lede">
        Tablua keeps everything an agent is and does as typed rows in one SQLite file: where the work stands,
        every move it could make, the move it took and who chose it, and how each step turned out. A tabular
        model learns from those rows which moves make progress.
      </p>
      <div ref={ref} className="run" role="figure" aria-label="An example run, written as rows">
          {shown.map(({ r, i }) => {
            const newest = i === count - 1;
            return (
              <motion.div
                key={i}
                layout={!still}
                transition={{ layout: { duration: 0.45, ease } }}
              >
                <Line seq={seq(i)} code={r.code} by={r.by} className={newest ? "active" : ""}>
                  <motion.span
                    style={{ display: "inline-block" }}
                    initial={still || !newest ? false : { clipPath: "inset(0 100% 0 0)" }}
                    animate={{ clipPath: "inset(0 0% 0 0)" }}
                    transition={{ duration: r.text.length * 0.018, ease: typed(r.text.length) }}
                  >
                    {r.text}
                  </motion.span>
                  {r.mark && (
                    <motion.span
                      className={`mark mark-${r.mark}`}
                      initial={still ? false : { scale: 1.6, opacity: 0 }}
                      animate={{ scale: 1, opacity: 1 }}
                      transition={{ delay: 0.5, duration: 0.35, ease }}
                    >
                      {r.mark.toUpperCase()}
                    </motion.span>
                  )}
                </Line>
              </motion.div>
            );
          })}
      </div>
    </Sheet>
  );
}
