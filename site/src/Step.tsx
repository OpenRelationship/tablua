import { useState } from "react";
import { motion } from "framer-motion";
import { steps, tableOf } from "./data";
import { Comment, Line, Sheet, seq } from "./Sheet";

// Sheet 2: one step is four tables. Each declaration line, then a comment saying what the table keeps.
export function Step() {
  const [on, setOn] = useState(0);
  return (
    <Sheet id="step" n={2} of={5} label="Tables" purpose="state · candidate · decision · outcome">
      <h2 className="sheet-title" id="step-title">Every step leaves four rows.</h2>
      {steps.map((s, i) => (
        <div key={s.code} onMouseEnter={() => setOn(i)}>
          <Line seq={seq(i)} code={s.code} by={tableOf[s.code].replace("tablua_", "")} className={on === i ? "active" : ""}>
            <strong>{tableOf[s.code]}</strong>
            {"  "}
            <span style={{ color: "var(--ink-2)" }}>{s.columns}</span>
          </Line>
          <motion.div
            initial={false}
            animate={{ opacity: on === i ? 1 : 0.62 }}
            transition={{ duration: 0.3 }}
          >
            <Comment>
              <b>{s.name}.</b> {s.says}
            </Comment>
          </motion.div>
        </div>
      ))}
      <Line seq="00050" code="O" by="host">
        broken  progress=0  passed=1/4  regressed=1<span className="mark mark-regressed">regressed</span>
      </Line>
      <Comment>
        An example outcome row: the step broke a check that passed before, so it is labelled no progress, and
        that label is what the tabular model trains on.
      </Comment>
      <Comment>
        Nothing about the agent lives anywhere else. The host that runs it is a stateless stepper: open the file,
        take one step, write the rows, close it.
      </Comment>
    </Sheet>
  );
}
