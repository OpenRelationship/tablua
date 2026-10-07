*** Settings ***
Documentation    The studio as a pi agent (owner, 2026-10-07): MiniMax M3 drives agent.loop with the studio's tools over
...              a Moonsplice comp; Jev judges each look; TabICL ranks the moves before a patch. Each run is
...              tablua-local/studio/run.sh over a copy of a seed, its sheet copied to runs/pi-<todo>.sqlite. The oracles
...              are the engine's (findings, expectations, its state line) and the rows the run kept. Predictions
...              committed before the first run; the first two of five are Moonsplice's (cadence-03, 2026-10-07).

*** Variables ***
${ALL}      runs/pi-*.sqlite
${PATCH}    ('add_node', 'set_prop', 'add_key', 'move_key', 'drop_key', 'bind', 'add_system', 'edit_system', 'derive', 'solid', 'remove')
# the newest snapshot at or before a message's step
${SNAP}     (select max(c.n) from (select n from tablua_msr_comp where todo = m.todo union select n from tablua_msr_node where todo = m.todo) c where c.n <= m.n)

*** Test Cases ***
A Run Ends Only Through The Gate
    [Documentation]    A run marked complete (tablua_run.works) has no error open at its last snapshot: a hand-in with
    ...    errors or failing expectations came back to the model, and a reply to that with no tool call ended the run
    ...    as partial. Kill: any complete run with an error open, among 3 or more runs.
    [Tags]    level:consistent    pi:gate    predict:holds@0.85
    Use Sheets    ${ALL}
    Complete Runs Are Clean

A Run Ends Only Through The Gate (red)
    Use Fixture    insert into tablua_run (todo, shipped, works, steps) values ('a', 1, 1, 4), ('b', 1, 0, 3), ('c', 1, 1, 2)    insert into tablua_msr_node (todo, n, id, kind) values ('a', 4, 'x', 'text'), ('b', 3, 'x', 'text'), ('c', 2, 'x', 'text')    insert into tablua_msr_finding (todo, n, tier, code, severity) values ('a', 4, 'check', 'text_overflow', 'error')
    Complete Runs Are Clean

No Run Is Complete At Its Seed
    [Documentation]    A run that hands in the comp as it was given (its last digest the seed's: tablua_run.changed = 0)
    ...    is partial, whatever its findings: pi-s4 changed nothing in 67 steps and scored complete (cadence-03,
    ...    2026-10-07). Kill: any complete run with changed 0 or unrecorded, among 3 or more runs.
    [Tags]    level:consistent    pi:seed    predict:holds@0.9
    Use Sheets    ${ALL}
    Complete Runs Changed The Comp

No Run Is Complete At Its Seed (red)
    Use Fixture    insert into tablua_run (todo, shipped, answered, works, changed, steps) values ('s4', 1, 1, 1, 0, 67), ('b', 1, 1, 1, 1, 30), ('c', 1, 1, 0, 0, 12)
    Complete Runs Changed The Comp

No Result Is Stale
    [Documentation]    Every patch, expect and look result ends with a state line whose error count is the engine's at
    ...    the newest snapshot of that step: the newest message in the transcript says what is true. Errors are counted
    ...    as the engine's own line counts them, a failing expectation under expect rather than among them (revised
    ...    after pi-s5 killed it, 2026-10-07: Tablua's line and the engine's counted two ways). Kill: any result
    ...    without one or with another count, among 10 or more results.
    [Tags]    level:consistent    pi:state    predict:holds@0.9
    Use Sheets    ${ALL}
    Results Carry The State

No Result Is Stale (red)
    Use Fixture    with recursive c(i) as (select 1 union all select i + 1 from c where i < 10) insert into tablua_message (todo, i, n, role, name, content) select 't', i, i, 'tool', 'patch', '1 applied. state: digest d; errors 0; warnings 0; expect 0/0; step ' || i from c    insert into tablua_msr_node (todo, n, id, kind) values ('t', 3, 'x', 'text')    insert into tablua_msr_finding (todo, n, tier, code, severity) values ('t', 3, 'lint', 'off_frame', 'error')
    Results Carry The State

The Learner Beats The Base Rate
    [Documentation]    TabICL's chance that the move taken closes something, made before the patch, has a lower
    ...    Brier score against the outcome than the base rate of the runs' own patch steps. The labels are Tablua's
    ...    progress (complete only: a step that opens an error or a failing expectation is broken). Kill: Brier not
    ...    below the base rate's, over 20 or more scored patch steps.
    [Tags]    level:informative    pi:learner    predict:holds@0.6
    Use Sheets    ${ALL}
    Learner Beats Base Rate

The Learner Beats The Base Rate (red)
    Use Fixture    with recursive c(i) as (select 1 union all select i + 1 from c where i < 20) insert into tablua_decision (todo, n, chosen, by) select 't', i, 'set_prop', 'model' from c    with recursive c(i) as (select 1 union all select i + 1 from c where i < 20) insert into tablua_outcome (todo, n, verb, outcome, progress) select 't', i, 'set_prop', case when i % 2 = 0 then 'complete' else 'neutral' end, i % 2 = 0 from c    with recursive c(i) as (select 1 union all select i + 1 from c where i < 20) insert into tablua_prediction (todo, n, head, move, p) select 't', i, 'progress', 'set_prop', case when i % 2 = 0 then 0.1 else 0.9 end from c
    Learner Beats Base Rate

Compaction Keeps The Ask
    [Documentation]    Every checkpoint a compaction left names the ask, the comp's state line and every step's line:
    ...    it is rendered from the tables, so nothing the run did is lost or reworded. Kill: any checkpoint without
    ...    them, among 1 or more.
    [Tags]    level:consistent    pi:compact    predict:holds@0.9
    Use Sheets    ${ALL}
    Checkpoints Keep The Ask

Compaction Keeps The Ask (red)
    Use Fixture    insert into tablua_message (todo, i, n, role, content) values ('t', 1, 5, 'user', 'The conversation history before this point was compacted into the following summary: ## Goal ... (no state, no steps)')
    Checkpoints Keep The Ask

Fewer Steps Are Wasted
    [Documentation]    Under a fifth more patch steps come out complete than in s3, the last run of the old harness:
    ...    there 16 of 20 patch steps were no_effect or neutral (0.8). Kill: the share of no_effect and neutral
    ...    patch steps at 0.8 or more, over 20 or more patch steps.
    [Tags]    level:useful    pi:waste    predict:holds@0.55
    Use Sheets    ${ALL}
    Wasted Share Below S3

Fewer Steps Are Wasted (red)
    Use Fixture    with recursive c(i) as (select 1 union all select i + 1 from c where i < 20) insert into tablua_outcome (todo, n, verb, outcome, progress) select 't', i, 'set_prop', case when i <= 17 then 'neutral' else 'complete' end, i > 17 from c
    Wasted Share Below S3

*** Keywords ***
Complete Runs Are Clean
    ${runs}=    Value Of    select count(*) from tablua_run
    Needs At Least    ${runs}    3    runs
    ${dirty}=    Value Of    select count(*) from tablua_run r where r.works = 1 and (select count(*) from tablua_msr_finding f where f.todo = r.todo and f.severity = 'error' and f.n = (select max(n) from (select n from tablua_msr_comp where todo = r.todo union select n from tablua_msr_node where todo = r.todo))) > 0
    Should Be True    ${dirty} == 0    ${dirty} of ${runs} runs marked complete with an error open

Complete Runs Changed The Comp
    ${runs}=    Value Of    select count(*) from tablua_run
    Needs At Least    ${runs}    3    runs
    ${seed}=    Value Of    select count(*) from tablua_run where works = 1 and coalesce(changed, 0) = 0
    Should Be True    ${seed} == 0    ${seed} of ${runs} runs marked complete on the comp as it was given

Results Carry The State
    ${all}=    Value Of    select count(*) from tablua_message where role = 'tool' and name in ('patch', 'expect', 'look')
    Needs At Least    ${all}    10    results
    ${stale}=    Value Of    select count(*) from tablua_message m where m.role = 'tool' and m.name in ('patch', 'expect', 'look') and (instr(m.content, 'state: digest') = 0 or cast(substr(m.content, instr(m.content, '; errors ') + 9, 6) as integer) != (select count(*) from tablua_msr_finding f where f.todo = m.todo and f.n = ${SNAP} and f.severity = 'error' and f.code != 'expect_failed'))
    Should Be True    ${stale} == 0    ${stale} of ${all} results with no state line or a stale one

Learner Beats Base Rate
    ${n}=    Value Of    select count(*) from tablua_prediction p join tablua_decision d on d.todo = p.todo and d.n = p.n and d.chosen = p.move join tablua_outcome o on o.todo = p.todo and o.n = p.n where p.head = 'progress' and d.chosen in ${PATCH}
    Needs At Least    ${n}    20    scored patch steps
    ${b}=    Value Of    select avg((p.p - o.progress) * (p.p - o.progress)) from tablua_prediction p join tablua_decision d on d.todo = p.todo and d.n = p.n and d.chosen = p.move join tablua_outcome o on o.todo = p.todo and o.n = p.n where p.head = 'progress' and d.chosen in ${PATCH}
    ${base}=    Value Of    with s as (select o.progress as y from tablua_prediction p join tablua_decision d on d.todo = p.todo and d.n = p.n and d.chosen = p.move join tablua_outcome o on o.todo = p.todo and o.n = p.n where p.head = 'progress' and d.chosen in ${PATCH}) select avg((y - (select avg(y) from s)) * (y - (select avg(y) from s))) from s
    Should Be True    ${b} < ${base}    TabICL Brier ${b} against the base rate's ${base} over ${n} steps

Checkpoints Keep The Ask
    ${all}=    Value Of    select count(*) from tablua_message where role = 'user' and content like 'The conversation history before this point was compacted%'
    Needs At Least    ${all}    1    checkpoints
    ${short}=    Value Of    select count(*) from tablua_message where role = 'user' and content like 'The conversation history before this point was compacted%' and (instr(content, '## Goal') = 0 or instr(content, 'state: digest') = 0 or instr(content, '## Progress') = 0 or instr(content, 'step 1 ') = 0)
    Should Be True    ${short} == 0    ${short} of ${all} checkpoints lack the ask, the state or the steps

Wasted Share Below S3
    ${all}=    Value Of    select count(*) from tablua_outcome where verb in ${PATCH}
    Needs At Least    ${all}    20    patch steps
    ${share}=    Value Of    select 1.0 * sum(outcome in ('no_effect', 'neutral')) / count(*) from tablua_outcome where verb in ${PATCH}
    Should Be True    ${share} < 0.8    ${share} of ${all} patch steps no_effect or neutral (s3: 0.8)
