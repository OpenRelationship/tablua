import { useEffect, useState } from "react";
import { REPO } from "./links";
import { GitHub, Logo } from "./icons";

export function Nav() {
  const [scrolled, setScrolled] = useState(false);
  useEffect(() => {
    const on = () => setScrolled(window.scrollY > 8);
    on();
    window.addEventListener("scroll", on, { passive: true });
    return () => window.removeEventListener("scroll", on);
  }, []);
  return (
    <header className={`nav${scrolled ? " scrolled" : ""}`}>
      <div className="wrap">
        <a className="brand" href="#top" aria-label="Tablua, home">
          <Logo />
          Tablua
        </a>
        <nav className="links" aria-label="Sections">
          <a className="opt" href="#how">How it works</a>
          <a className="opt" href="#learning">Learning</a>
          <a className="opt" href="#computer">Computer</a>
          <a className="btn btn-quiet btn-sm" href={REPO}>
            <GitHub /> GitHub
          </a>
        </nav>
      </div>
    </header>
  );
}
