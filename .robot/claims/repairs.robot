*** Settings ***
Documentation    Repairs after reading the 11:23 replication run's logs (2026-10-06): a fix step cut build-pov-ray's
...              suite from 8 tests to 2 and passed the 2; circuit-fibsqrt ran 30 fix steps with no write, each one
...              writer call that only looked; nothing turned a long stall into a new plan. Measured on the trials
...              fetched as repaired (overfull-hbox, 4 trials). Predictions committed before the repairs were built.

*** Variables ***
${LABEL}    repaired
${MANY}     with recursive c(i) as (select 1 union all select i + 1 from c where i < 40)

*** Test Cases ***
The Suite Never Loses A Test
    [Documentation]    Safety: across a trial, the number of acceptance tests run never falls below an earlier count.
    ...    Kill: any trial's test count falls, at any step.
    [Tags]    level:consistent    repair:suite    predict:holds@0.9
    Use Trials    ${LABEL}
    Needs Tested Steps
    No Count Falls

The Suite Never Loses A Test (red)
    Use Fixture    insert into tablua_result (todo, n, run, file, test, path, parent, depth, type, keyword, args, status, message, ms, line) values ('t', 1, 1, 'f', 'A', '1', '', 0, 'test', 'A', '', 'FAIL', '', 0, 1), ('t', 1, 1, 'f', 'B', '2', '', 0, 'test', 'B', '', 'FAIL', '', 0, 1), ('t', 2, 1, 'f', 'A', '1', '', 0, 'test', 'A', '', 'PASS', '', 0, 1)
    No Count Falls

A Fix Step Changes Something
    [Documentation]    A work or fix step sends at least one action that does more than look (a write, a build, a run),
    ...    the second turn given to a step that only looked. Kill: under 90% of 10 or more work and fix steps.
    [Tags]    level:consistent    repair:act    predict:holds@0.6
    Use Trials    ${LABEL}
    Steps Act

A Fix Step Changes Something (red)
    Use Fixture    ${MANY} insert into tablua_decision (todo, n, chosen, by) select 't', i, 'fix', 'free' from c    ${MANY} insert into tablua_term (todo, n, i, source, keys, reads) select 't', i, 1, 'real', 'cat x', 1 from c
    Steps Act

No Stall Outlasts The Budget By Much
    [Documentation]    Liveness: after 3 work or fix steps with no gain the loop plans again, so no trial goes more than 8
    ...    steps in a row with nothing further (bench/terminal/labels.lua's live labels). Kill: any trial does.
    [Tags]    level:consistent    repair:liveness    predict:holds@0.5
    Use Trials    ${LABEL}
    Longest Stall Is Short

No Stall Outlasts The Budget By Much (red)
    Use Fixture    ${MANY} insert into tablua_label (todo, n, head, value, source, at) select 't', i, 'further', 0, 'bench', '' from c
    Longest Stall Is Short

*** Keywords ***
Needs Tested Steps
    ${n}=    Value Of    select count(distinct todo || n) from tablua_result where type = 'test'
    Needs At Least    ${n}    5    steps whose tests ran

No Count Falls
    ${fell}=    Value Of    with counts as (select todo, n, count(*) as k from tablua_result where type = 'test' and run = (select max(run) from tablua_result r where r.todo = tablua_result.todo and r.n = tablua_result.n) group by todo, n) select count(*) from counts a where exists (select 1 from counts b where b.todo = a.todo and b.n < a.n and b.k > a.k)
    Should Be True    ${fell} == 0    the test count fell at ${fell} steps

Steps Act
    ${all}=    Value Of    select count(*) from tablua_decision where chosen in ('work', 'fix')
    Needs At Least    ${all}    10    work and fix steps
    ${acted}=    Value Of    select count(*) from tablua_decision d where chosen in ('work', 'fix') and exists (select 1 from tablua_term t where t.todo = d.todo and t.n = d.n and t.source = 'real' and t.reads = 0)
    Should Be True    ${acted} >= 0.9 * ${all}    ${acted} of ${all} work and fix steps did more than look

Longest Stall Is Short
    ${steps}=    Value Of    select count(*) from tablua_label where head = 'further'
    Needs At Least    ${steps}    10    steps with a further label
    ${longest}=    Value Of    with f as (select todo, n, value, n - (select count(*) from tablua_label g where g.todo = l.todo and g.head = 'further' and g.n <= l.n and g.value = l.value) as grp from tablua_label l where head = 'further') select coalesce(max(k), 0) from (select count(*) as k from f where value = 0 group by todo, grp)
    Should Be True    ${longest} <= 8    ${longest} steps in a row with nothing further
