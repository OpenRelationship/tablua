import { useEffect, useState } from "react";
import { REPO } from "./Sheet";
import { GitHub } from "./icons";

const sheets = [
  ["run", "The run"],
  ["step", "A step"],
  ["learning", "Learning"],
  ["policy", "Policy"],
  ["computer", "Computer"],
] as const;

// The sheet tabs along the bottom, a spreadsheet's; the one in view is current.
export function Tabs() {
  const [current, setCurrent] = useState("run");
  useEffect(() => {
    const io = new IntersectionObserver(
      (es) => es.forEach((e) => e.isIntersecting && setCurrent(e.target.id)),
      { rootMargin: "-45% 0px -50% 0px" },
    );
    sheets.forEach(([id]) => {
      const el = document.getElementById(id);
      if (el) io.observe(el);
    });
    return () => io.disconnect();
  }, []);
  return (
    <nav className="tabs" aria-label="Sheets">
      {sheets.map(([id, name], i) => (
        <a key={id} href={`#${id}`} aria-current={current === id}>
          <span className="n">{i + 1}</span>
          <span className="name">{name}</span>
        </a>
      ))}
      <a className="gh" href={REPO}>
        <GitHub />
        <span className="name">GitHub</span>
      </a>
    </nav>
  );
}
