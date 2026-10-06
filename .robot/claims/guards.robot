*** Settings ***
Documentation    Fixes after the 0-of-8 run (2026-10-06, 13:26 and 12:51): the plan guessed facts about files the task
...              says must not change ("main.tex Should Not Be Edited: 16 != 17"), those tests failed from the start, and
...              fix steps chased them until the 750 s limit: 5 of 6 overfull-hbox trials never edited input.tex. python3,
...              not installed, was run again after exit 127. Measured on the trials fetched as guards (overfull-hbox, 4
...              trials). Predictions committed before the fixes were built.

*** Variables ***
${LABEL}    guards
${MANY}     with recursive c(i) as (select 1 union all select i + 1 from c where i < 40)

*** Test Cases ***
A Test Of What Must Not Change Passes Before Any Work
    [Documentation]    Tests named for a file that must not change (Unchanged, Not Modified, Not Edited) pass at the
    ...    suite's first run, when nothing has been done yet. A guess about such a file fails there and hijacks the run.
    ...    Kill: under 90% of 5 or more such first runs pass.
    [Tags]    level:consistent    repair:unchanged    predict:holds@0.75
    Use Trials    ${LABEL}
    Guards Pass At First

A Test Of What Must Not Change Passes Before Any Work (red)
    Use Fixture    ${MANY} insert into tablua_result (todo, n, run, file, test, path, parent, depth, type, keyword, args, status, message, ms, line) select 't' || i, 2, 1, 'f', 'Main Not Modified', '1', '', 0, 'test', 'M', '', 'FAIL', '16 != 17', 0, 1 from c
    Guards Pass At First

A Missing Program Is Not Run Again And Again
    [Documentation]    No trial runs a program more than twice after the shell said it was not found (exit 127).
    ...    Kill: any trial does.
    [Tags]    level:consistent    repair:missing    predict:holds@0.6
    Use Trials    ${LABEL}
    Missing Programs Stay Missing

A Missing Program Is Not Run Again And Again (red)
    Use Fixture    ${MANY} insert into tablua_term (todo, n, i, source, keys, exit, program) select 't', i, 1, 'real', 'python3 -c 1', 127, 'python3' from c
    Missing Programs Stay Missing

Overfull Hbox Passes Half The Time
    [Documentation]    The verifier passes at least 2 of 4 overfull-hbox trials. The oracle is Harbor's verifier, not
    ...    our code. Kill: fewer than 2 of 4 scored trials pass.
    [Tags]    level:useful    repair:outcome    predict:holds@0.35
    Use Trials    ${LABEL}
    Half Pass

Overfull Hbox Passes Half The Time (red)
    Use Fixture    insert into trial (job, trial, task, reward) values ('j', 'a', 'overfull-hbox', 0), ('j', 'b', 'overfull-hbox', 0), ('j', 'c', 'overfull-hbox', 1), ('j', 'd', 'overfull-hbox', 0)
    Half Pass

*** Keywords ***
Guards Pass At First
    ${all}=    Value Of    with first as (select todo, test, status, row_number() over (partition by todo, test order by n, run) as k from tablua_result where type = 'test' and (lower(test) like '%unchanged%' or lower(test) like '%not be modified%' or lower(test) like '%not modified%' or lower(test) like '%not be edited%' or lower(test) like '%not edited%')) select count(*) from first where k = 1
    Needs At Least    ${all}    5    first runs of tests of what must not change
    ${passed}=    Value Of    with first as (select todo, test, status, row_number() over (partition by todo, test order by n, run) as k from tablua_result where type = 'test' and (lower(test) like '%unchanged%' or lower(test) like '%not be modified%' or lower(test) like '%not modified%' or lower(test) like '%not be edited%' or lower(test) like '%not edited%')) select count(*) from first where k = 1 and status = 'PASS'
    Should Be True    ${passed} >= 0.9 * ${all}    ${passed} of ${all} passed at their first run

Missing Programs Stay Missing
    ${worst}=    Value Of    select coalesce(max(k), 0) from (select todo, program, count(*) as k from tablua_term t where source = 'real' and exists (select 1 from tablua_term m where m.todo = t.todo and m.program = t.program and m.exit = 127 and (m.n < t.n or (m.n = t.n and m.i < t.i))) group by todo, program)
    Should Be True    ${worst} <= 2    a program was run ${worst} times after the shell said it was not found

Half Pass
    ${scored}=    Value Of    select count(*) from trial where task = 'overfull-hbox' and reward is not null
    Needs At Least    ${scored}    4    scored overfull-hbox trials
    ${passed}=    Value Of    select count(*) from trial where task = 'overfull-hbox' and reward = 1
    Should Be True    ${passed} >= 2    ${passed} of ${scored} overfull-hbox trials passed
