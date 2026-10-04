import { Run } from "./Run";
import { Step } from "./Step";
import { Learning } from "./Learning";
import { Policy } from "./Policy";
import { Computer } from "./Computer";
import { Tabs } from "./Tabs";
import { REPO } from "./Sheet";

export default function App() {
  return (
    <>
      <main>
        <Run />
        <Step />
        <Learning />
        <Policy />
        <Computer />
      </main>
      <footer className="foot">
        <span>Tablua · Apache-2.0</span>
        <a href={REPO}>github.com/OpenRelationship/tablua</a>
        <span>Moss and Shroomi are parts of Tablua.</span>
      </footer>
      <Tabs />
    </>
  );
}
