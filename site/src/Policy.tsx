import { useState } from "react";
import { LayoutGroup, motion } from "framer-motion";
import { gates, moves } from "./data";

// Policy is data: switch a gate off and the moves it withheld open again.
const applies = new Set(["green_before_publish", "look_after_pages"]);

export function Policy() {
  const [off, setOff] = useState<Set<string>>(new Set());
  const toggle = (id: string) =>
    setOff((s) => {
      const n = new Set(s);
      if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });
  const held = new Set(gates.filter((g) => applies.has(g.id) && !off.has(g.id)).flatMap((g) => g.withholds));
  return (
    <section className="block" id="policy">
      <div className="wrap split">
        <div>
          <h2>The rules are rows too.</h2>
          <p className="intro">
            A gate says when it applies and which moves it withholds. Since decisions and outcomes are rows, what a
            gate costs can be measured, and a gate that only blocks good moves can be taken out. Try switching one off.
          </p>
        </div>
        <div className="panel">
          <div className="panel-head">
            <span className="mono">tablua_gate</span>
            <span className="mono">stage=building · passed=2/4</span>
          </div>
          <ul className="gates">
            {gates.map((g) => {
              const on = !off.has(g.id);
              return (
                <li key={g.id}>
                  <button className="gate" role="switch" aria-checked={on} onClick={() => toggle(g.id)}>
                    <span className="switch" />
                    <span>
                      <span className="name">{g.id}</span>
                      <span className="rule">
                        when {g.when}, withholds {g.withholds.join(", ")}
                      </span>
                    </span>
                    <span className="state">{!on ? "off" : applies.has(g.id) ? "applies now" : "idle"}</span>
                  </button>
                </li>
              );
            })}
          </ul>
          <LayoutGroup>
            <div className="moves" aria-live="polite" aria-label="Moves allowed now">
              {[...moves]
                .sort((a, b) => Number(held.has(a)) - Number(held.has(b)))
                .map((m) => (
                  <motion.span layout key={m} className={`move${held.has(m) ? " held" : ""}`} transition={{ duration: 0.35, ease: [0.16, 1, 0.3, 1] }}>
                    {m}
                  </motion.span>
                ))}
            </div>
          </LayoutGroup>
        </div>
      </div>
    </section>
  );
}
