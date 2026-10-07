*** Settings ***
Documentation    The studio world on a real Moonsplice comp (owner, 2026-10-06; cadence/docs/ROWS.md). Each run is
...              tablua-local/studio/run.sh over a copy of a rows-form comp: openai/gpt-6-luna-decisions decides,
...              MiniMax M3 writes the patch moves and criticises the contact sheet, bin/moonsplice applies, lints
...              and checks. Its sheet is copied to runs/studio-<todo>.sqlite. The oracles are the engine's (its
...              findings, its applied and rejected patches) and the critic's scores, all rows the run kept.
...              Predictions committed before the first run.

*** Variables ***
${ALL}      runs/studio-*.sqlite
# the newest snapshot before step o.n: treat and look take none, so n - 1 may have no rows (fixed before measuring)
${BEFORE}    (select max(c.n) from tablua_msr_comp c where c.todo = o.todo and c.n < o.n)
${PATCH}    ('add_node', 'set_prop', 'add_key', 'move_key', 'drop_key', 'bind', 'add_system', 'edit_system', 'derive', 'solid', 'remove')

*** Test Cases ***
Patch Moves Land
    [Documentation]    At least 60% of patch-move steps land one patch or more (a tablua_action row: the engine
    ...    applied it). Kill: under 60% of 5 or more patch steps.
    [Tags]    level:consistent    studio:patch    predict:holds@0.6
    Use Sheets    ${ALL}
    Patches Land

Patch Moves Land (red)
    Use Fixture    with recursive c(i) as (select 1 union all select i + 1 from c where i < 6) insert into tablua_decision (todo, n, chosen, by) select 't', i, 'set_prop', 'jev' from c    insert into tablua_action (todo, n, i, cmd) values ('t', 1, 1, 'x'), ('t', 2, 1, 'x')
    Patches Land

No Complete Step Adds An Error
    [Documentation]    A step judged complete never leaves more error findings than the comp had before it
    ...    (snapshot n against n - 1). The oracle is the engine's lint and check. Kill: any, among 5 or more
    ...    complete patch steps.
    [Tags]    level:correct    studio:outcome    predict:holds@0.85
    Use Sheets    ${ALL}
    Complete Adds No Error

No Complete Step Adds An Error (red)
    Use Fixture    with recursive c(i) as (select 1 union all select i + 1 from c where i < 6) insert into tablua_outcome (todo, n, verb, outcome, progress) select 't', i, 'set_prop', 'complete', 1 from c    insert into tablua_msr_finding (todo, n, tier, code, severity) values ('t', 3, 'lint', 'off_frame', 'error')
    Complete Adds No Error

Every Look Is Scored
    [Documentation]    Every look step that ended complete left the critic's six scores (tablua_score). Kill: any
    ...    look without six, among 2 or more.
    [Tags]    level:consistent    studio:look    predict:holds@0.7
    Use Sheets    ${ALL}
    Looks Scored

Every Look Is Scored (red)
    Use Fixture    insert into tablua_outcome (todo, n, verb, outcome, progress) values ('t', 2, 'look', 'complete', 1), ('t', 5, 'look', 'complete', 1)    insert into tablua_score (todo, n, judge, dim, value) values ('t', 2, 'critic', 'rule', 4)
    Looks Scored

A Run Ends With The Gate Passing
    [Documentation]    Every run's last snapshot has no error findings: the agent does not hand in a comp the
    ...    engine rejects. Kill: any run ending with errors, among 3 or more runs.
    [Tags]    level:useful    studio:gate    predict:holds@0.5
    Use Sheets    ${ALL}
    Runs End Clean

A Run Ends With The Gate Passing (red)
    Use Fixture    insert into tablua_msr_node (todo, n, id, kind) values ('a', 4, 'x', 'rect'), ('b', 2, 'x', 'rect'), ('c', 6, 'x', 'rect')    insert into tablua_msr_finding (todo, n, tier, code, severity) values ('b', 2, 'lint', 'off_frame', 'error')
    Runs End Clean

No Complete Step Adds An Expectation Failed
    [Documentation]    A step judged complete never leaves more expect_failed findings than the snapshot before it:
    ...    a move cannot meet the ask by deleting what an expectation names (Moonsplice's ask, 2026-10-06; studio s2
    ...    removed the tide table at steps 12 to 14 and was scored complete). The oracle is the engine's lint of the
    ...    expectations written at treat. Kill: any, among 5 or more complete patch steps.
    [Tags]    level:correct    studio:expect    predict:holds@0.9
    Use Sheets    ${ALL}
    Complete Adds No Expect Failed

No Complete Step Adds An Expectation Failed (red)
    Use Fixture    with recursive c(i) as (select 1 union all select i + 1 from c where i < 6) insert into tablua_outcome (todo, n, verb, outcome, progress) select 't', i, 'remove', 'complete', 1 from c    insert into tablua_msr_comp (todo, n, key, value) values ('t', 11, 'fps', 30), ('t', 12, 'fps', 30)    insert into tablua_outcome (todo, n, verb, outcome, progress) values ('t', 12, 'remove', 'complete', 1)    insert into tablua_msr_finding (todo, n, tier, id, code, severity) values ('t', 12, 'lint', 't4', 'expect_failed', 'error')
    Complete Adds No Expect Failed

*** Keywords ***
Patches Land
    ${all}=    Value Of    select count(*) from tablua_decision where chosen in ${PATCH}
    Needs At Least    ${all}    5    patch-move steps
    ${landed}=    Value Of    select count(*) from tablua_decision d where chosen in ${PATCH} and exists (select 1 from tablua_action a where a.todo = d.todo and a.n = d.n)
    Should Be True    ${landed} >= 0.6 * ${all}    ${landed} of ${all} patch steps landed a patch

Complete Adds No Error
    ${all}=    Value Of    select count(*) from tablua_outcome where outcome = 'complete' and verb in ${PATCH}
    Needs At Least    ${all}    5    complete patch steps
    ${bad}=    Value Of    select count(*) from tablua_outcome o where o.outcome = 'complete' and o.verb in ${PATCH} and (select count(*) from tablua_msr_finding f where f.todo = o.todo and f.n = o.n and f.severity = 'error') > (select count(*) from tablua_msr_finding f where f.todo = o.todo and f.n = ${BEFORE} and f.severity = 'error')
    Should Be True    ${bad} == 0    ${bad} of ${all} complete steps added an error

Looks Scored
    ${all}=    Value Of    select count(*) from tablua_outcome where verb = 'look' and outcome = 'complete'
    Needs At Least    ${all}    2    complete looks
    ${short}=    Value Of    select count(*) from tablua_outcome o where o.verb = 'look' and o.outcome = 'complete' and (select count(*) from tablua_score s where s.todo = o.todo and s.n = o.n and s.judge = 'critic') < 6
    Should Be True    ${short} == 0    ${short} of ${all} looks lack the critic's six scores

Runs End Clean
    ${runs}=    Value Of    select count(distinct todo) from tablua_msr_node
    Needs At Least    ${runs}    3    runs
    ${dirty}=    Value Of    select count(*) from (select todo, max(n) as last from tablua_msr_node group by todo) r where (select count(*) from tablua_msr_finding f where f.todo = r.todo and f.n = r.last and f.severity = 'error') > 0
    Should Be True    ${dirty} == 0    ${dirty} of ${runs} runs ended with errors open

Complete Adds No Expect Failed
    ${all}=    Value Of    select count(*) from tablua_outcome where outcome = 'complete' and verb in ${PATCH}
    Needs At Least    ${all}    5    complete patch steps
    ${bad}=    Value Of    select count(*) from tablua_outcome o where o.outcome = 'complete' and o.verb in ${PATCH} and (select count(*) from tablua_msr_finding f where f.todo = o.todo and f.n = o.n and f.code = 'expect_failed') > (select count(*) from tablua_msr_finding f where f.todo = o.todo and f.n = ${BEFORE} and f.code = 'expect_failed')
    Should Be True    ${bad} == 0    ${bad} of ${all} complete steps added an expect_failed
