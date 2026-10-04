import { useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import { Comment, Line, Sheet } from "./Sheet";

// Sheet 3: shadow, then decide. The same candidates; who takes the step depends on the mode.
const cands = [
  { move: "write_page", jev: 0.48, pfn: 0.4 },
  { move: "write_steps", jev: 0.33, pfn: 0.71 },
  { move: "rewrite", jev: 0.19, pfn: 0.08 },
];
const fmt = (p: number) => p.toFixed(2).replace(/^0/, "");

export function Learning() {
  const [decide, setDecide] = useState(false);
  const chosen = decide ? "write_steps" : "write_page";
  const by = decide ? "tabpfn" : "jev";
  return (
    <Sheet id="learning" n={3} of={5} label="Columns" purpose="candidate.p_progress · decision.by">
      <h2 className="sheet-title" id="learning-title">The model learns from the agent's own record.</h2>
      <Comment>
        A tabular foundation model, TabPFN, is fitted on the agent's past candidate rows, each labelled by whether
        its step made progress. The language model's probabilities are among its features. It needs no training
        run of its own: the rows are the training set.
      </Comment>
      <Line>
        <span role="radiogroup" aria-label="Mode" style={{ display: "inline-flex", gap: "3ch" }}>
          <button className="box" role="radio" aria-checked={!decide} onClick={() => setDecide(false)}>
            <span className="sq" /> SHADOW
          </button>
          <button className="box" role="radio" aria-checked={decide} onClick={() => setDecide(true)}>
            <span className="sq" /> DECIDE
          </button>
        </span>
      </Line>
      {cands.map((c, i) => (
        <Line key={c.move} seq={String((i + 1) * 10).padStart(5, "0")} code="C" by="tabpfn" className={c.move === chosen ? "active" : ""}>
          {c.move.padEnd(13)}jev_p={fmt(c.jev)}  p_progress=
          <motion.b
            key={c.move + decide}
            initial={{ color: "var(--print)", backgroundColor: "var(--wash)" }}
            animate={{ backgroundColor: "rgba(233, 240, 253, 0)" }}
            transition={{ duration: 0.9 }}
          >
            {fmt(c.pfn)}
          </motion.b>
        </Line>
      ))}
      <Line seq="00040" code="D" by={by} className="active">
        <AnimatePresence mode="wait" initial={false}>
          <motion.span
            key={by}
            initial={{ clipPath: "inset(0 100% 0 0)" }}
            animate={{ clipPath: "inset(0 0% 0 0)" }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.4, ease: "linear" }}
            style={{ display: "inline-block" }}
          >
            chosen={chosen}  by={by}
          </motion.span>
        </AnimatePresence>
      </Line>
      <Comment>
        {decide
          ? "Deciding, it takes the step only when its best move clearly leads the language model's pick and the language model was unsure. Otherwise the pick stands."
          : "In shadow it scores every move and decides nothing, so its record and the language model's can be compared on the same steps before it is trusted with any."}
      </Comment>
      <Comment>Example values. Pooling rows across agents is a switch: each computer can learn from the others' steps.</Comment>
    </Sheet>
  );
}
