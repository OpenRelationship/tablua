import { Nav } from "./Nav";
import { Hero } from "./Hero";
import { How } from "./How";
import { Learning } from "./Learning";
import { Policy } from "./Policy";
import { Computer } from "./Computer";
import { REPO } from "./links";
import { GitHub } from "./icons";

export default function App() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <How />
        <Learning />
        <Policy />
        <Computer />
        <section className="close">
          <div className="wrap">
            <h2>Read the source.</h2>
            <p className="intro">Portable Lua, embedded in any host's Lua VM. No WebAssembly, no native code.</p>
            <div className="actions">
              <a className="btn btn-primary" href={REPO}>
                <GitHub /> OpenRelationship/tablua
              </a>
            </div>
            <div className="clone">
              <span className="p">$</span> git clone {REPO}.git
            </div>
          </div>
        </section>
      </main>
      <footer>
        <div className="wrap">
          <span>Tablua · Apache-2.0</span>
          <a href={REPO}>GitHub</a>
        </div>
      </footer>
    </>
  );
}
