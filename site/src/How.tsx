import { steps, tableOf } from "./data";

// One step, four tables.
export function How() {
  return (
    <section className="block" id="how">
      <div className="wrap">
        <h2>Every step leaves four rows.</h2>
        <p className="intro">
          Nothing about the agent lives anywhere else. The host that runs it is a stateless stepper: open the file,
          take one step, write the rows, close it.
        </p>
        <dl className="defs">
          {steps.map((s) => (
            <div key={s.code}>
              <dt>{tableOf[s.code]}</dt>
              <dd>
                <b>{s.name}.</b> {s.says}
              </dd>
            </div>
          ))}
        </dl>
      </div>
    </section>
  );
}
