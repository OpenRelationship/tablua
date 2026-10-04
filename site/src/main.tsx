import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./styles.css";
import App from "./App";

// The sheet's cells are character cells: measure Martian Mono's advance once its face has loaded.
function measure() {
  const probe = document.createElement("span");
  probe.textContent = "0".repeat(100);
  probe.style.cssText = "position:absolute;visibility:hidden;font-family:var(--mono);font-stretch:87.5%;font-size:100px;white-space:pre";
  document.body.appendChild(probe);
  const chr = probe.getBoundingClientRect().width / 100 / 100;
  probe.remove();
  if (chr > 0.3 && chr < 1) document.documentElement.style.setProperty("--chr", chr.toFixed(4));
}
document.fonts.load('400 16px "Martian Mono Variable"').then(measure, measure);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
