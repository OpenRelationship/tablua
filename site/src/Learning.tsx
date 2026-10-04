import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";

// Shadow, then decide: the same candidates; who takes the step depends on the mode.
const cands = [
  { move: "write_page", jev: 0.48, pfn: 0.4 },
  { move: "write_steps", jev: 0.33, pfn: 0.71 },
  { move: "rewrite", jev: 0.19, pfn: 0.08 },
];
const fmt = (p: number) => p.toFixed(2).replace(/^0/, "");
const modes = ["shadow", "decide"] as const;

export function Learning() {
  const [mode, setMode] = useState<(typeof modes)[number]>("shadow");
  const chosen = mode === "decide" ? "write_steps" : "write_page";
  const by = mode === "decide" ? "TabPFN" : "Jev";
  return (
    <section className="block" id="learning">
      <div className="wrap split">
        <div>
          <h2>It learns from its own record.</h2>
          <p className="intro">
            A tabular foundation model, TabPFN, is fitted on the agent's past candidate rows, each labelled by whether
            its step made progress. The language model's probabilities are among its features. There is no training
            run: the rows are the training set.
          </p>
        </div>
        <div className="panel">
          <div className="panel-head">
            <span>Candidates for step 3</span>
            <span className="segmented" role="radiogroup" aria-label="Mode">
              {modes.map((m) => (
                <button key={m} role="radio" aria-checked={mode === m} onClick={() => setMode(m)}>
                  {mode === m && <motion.span layoutId="pill" className="pill" transition={{ duration: 0.3, ease: [0.16, 1, 0.3, 1] }} />}
                  {m === "shadow" ? "Shadow" : "Decide"}
                </button>
              ))}
            </span>
          </div>
          <table className="grid">
            <thead>
              <tr>
                <th>move</th>
                <th>Jev</th>
                <th>TabPFN</th>
                <th className="by">taken</th>
              </tr>
            </thead>
            <tbody>
              {cands.map((c) => (
                <tr key={c.move} className={c.move === chosen ? "new" : ""}>
                  <td>{c.move}</td>
                  <td>{fmt(c.jev)}</td>
                  <td>{fmt(c.pfn)}</td>
                  <td className="by">
                    <AnimatePresence mode="wait" initial={false}>
                      {c.move === chosen && (
                        <motion.span key={by} initial={{ opacity: 0, x: 6 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0 }} transition={{ duration: 0.25 }}>
                          by {by}
                        </motion.span>
                      )}
                    </AnimatePresence>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="foot-note">
            {mode === "shadow"
              ? "In shadow, TabPFN scores every move and decides nothing, so its record can be compared with the language model's on the same steps."
              : "Deciding, it takes the step only when its best move clearly leads and the language model was unsure. Otherwise the language model's pick stands."}
          </p>
        </div>
      </div>
    </section>
  );
}
