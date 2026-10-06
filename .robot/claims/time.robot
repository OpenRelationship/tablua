*** Settings ***
Documentation    The agent did not know its time (2026-10-06): plan steps made 18 to 37 writer calls each, peeking at the
...              computer round after round, two lasting 286 and 384 s; work steps read web pages (9 in one trial) while
...              each round's actions were set aside, and a third of work and fix steps ran no command that changed
...              anything (24 of 36 did, on the 12:51 and 14:13 runs). Fix: the task's time limit (its task.toml) reaches
...              the host as a deadline; the state says the time left, and so does each round of lookups. Measured on
...              the trials fetched as green (overfull-hbox, 4 trials; the time fix ships in the same run as the green fixes). Predictions committed before the fix was built.

*** Variables ***
${LABEL}    green
${MANY}     with recursive c(i) as (select 1 union all select i + 1 from c where i < 12)

*** Test Cases ***
No Plan Step Outlasts Two Minutes
    [Documentation]    Every plan_tests step that ended took under 120 s (the next decision's time less its own).
    ...    Kill: any took longer, among 4 or more.
    [Tags]    level:consistent    repair:time    predict:holds@0.5
    Use Trials    ${LABEL}
    Plans Are Short

No Plan Step Outlasts Two Minutes (red)
    Use Fixture    ${MANY} insert into tablua_decision (todo, n, chosen, by, at) select 't', i, case when i % 2 = 1 then 'plan_tests' else 'work' end, 'free', datetime('2026-10-06 21:00:00', '+' || (i * 30 + case when i > 7 then 300 else 0 end) || ' seconds') from c
    Plans Are Short

Work Steps Act
    [Documentation]    At least 80% of work and fix steps run a command that does more than read (tablua_term reads = 0).
    ...    Kill: under 80% of 10 or more. On the 12:51 and 14:13 runs, 67%.
    [Tags]    level:consistent    repair:time    predict:holds@0.5
    Use Trials    ${LABEL}
    Work Acts

Work Steps Act (red)
    Use Fixture    ${MANY} insert into tablua_decision (todo, n, chosen, by) select 't', i, 'work', 'free' from c    ${MANY} insert into tablua_term (todo, n, i, source, keys, reads) select 't', i, 1, 'real', 'x', case when i % 2 = 0 then 0 else 1 end from c
    Work Acts

*** Keywords ***
Plans Are Short
    ${all}=    Value Of    select count(*) from tablua_decision a join tablua_decision b on b.todo = a.todo and b.n = a.n + 1 where a.chosen = 'plan_tests'
    Needs At Least    ${all}    4    plan steps that ended
    ${long}=    Value Of    select count(*) from tablua_decision a join tablua_decision b on b.todo = a.todo and b.n = a.n + 1 where a.chosen = 'plan_tests' and (julianday(b.at) - julianday(a.at)) * 86400 >= 120
    Should Be True    ${long} == 0    ${long} of ${all} plan steps took 120 s or more

Work Acts
    ${all}=    Value Of    select count(*) from tablua_decision where chosen in ('work', 'fix')
    Needs At Least    ${all}    10    work and fix steps
    ${acted}=    Value Of    select count(*) from tablua_decision d where chosen in ('work', 'fix') and exists (select 1 from tablua_term t where t.todo = d.todo and t.n = d.n and t.source = 'real' and t.reads = 0)
    Should Be True    ${acted} >= 0.8 * ${all}    ${acted} of ${all} work and fix steps ran a command that did more than read
