import { useState } from "react";
import { LayoutGroup, motion } from "framer-motion";
import { gates, moves } from "./data";
import { Comment, Line, Sheet } from "./Sheet";

// Sheet 4: policy is data. Strike a gate row and the moves it withheld open again.
const inForce = new Set(["green_before_publish", "look_after_pages"]);

export function Policy() {
  const [struck, setStruck] = useState<Set<string>>(new Set());
  const toggle = (id: string) =>
    setStruck((s) => {
      const n = new Set(s);
      n.has(id) ? n.delete(id) : n.add(id);
      return n;
    });
  const withheld = new Set(gates.filter((g) => inForce.has(g.id) && !struck.has(g.id)).flatMap((g) => g.withholds));
  return (
    <Sheet id="policy" n={4} of={5} label="Table" purpose="tablua_gate">
      <h2 className="sheet-title" id="policy-title">The rules are rows you can take out.</h2>
      <Line code="S" by="host">stage=building  passed=2/4  pages_ok=0</Line>
      {gates.map((g, i) => {
        const off = struck.has(g.id);
        return (
          <button
            key={g.id}
            className="gate-toggle"
            aria-pressed={!off}
            onClick={() => toggle(g.id)}
            title={`${off ? "Restore" : "Strike"} gate ${g.id}`}
          >
            <Line seq={String((i + 1) * 10).padStart(5, "0")} code="G" by={off ? "struck" : inForce.has(g.id) ? "in force" : "idle"} className={off ? "struck" : ""}>
              <span className="box">
                <span className="sq" />
              </span>{" "}
              {g.id}  when {g.when}  withholds {g.withholds.join(", ")}
            </Line>
          </button>
        );
      })}
      <Line code="M">
        <LayoutGroup>
          <span className="moves" aria-live="polite">
            {[...moves].sort((a, b) => Number(withheld.has(a)) - Number(withheld.has(b))).map((m) => (
              <motion.span layout key={m} className={`move ${withheld.has(m) ? "withheld" : "open"}`} transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}>
                {m}
              </motion.span>
            ))}
          </span>
        </LayoutGroup>
        {withheld.size > 0 && <span className="mark mark-blocked">{withheld.size} blocked</span>}
      </Line>
      <Comment>
        A gate says when it applies and which moves it withholds. Decisions and outcomes are rows too, so what a
        gate costs can be measured, and a gate that only ever blocks good moves can be taken out. Try striking one.
      </Comment>
    </Sheet>
  );
}
