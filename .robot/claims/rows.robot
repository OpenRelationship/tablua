*** Settings ***
Documentation    Claims about what a run keeps as rows since schema 18 (2026-10-06): each test run's keyword tree, and
...              each decision with what the decision model said, the text it read and the parts of its probabilities.
...              They read every trial fetched with the label rows-on (run.lua fetch rows-on), pooled. Run 3 read only
...              the latest trial, too few decisions for two claims; the scope widened 2026-10-06, no kill number moved.

*** Variables ***
${LABEL}    rows-on
${MANY}     with recursive c(i) as (select 1 union all select i + 1 from c where i < 40)

*** Test Cases ***
Test Runs Are Kept As Rows
    [Documentation]    Every action run while tests existed is matched by keyword rows in tablua_result.
    ...    Kill: a rows-on sheet whose term rows show tests (passed is set) has no result rows.
    [Tags]    level:consistent    table:tablua_result    predict:holds@0.85
    Use Trials    ${LABEL}
    Tested Actions Have Results

Test Runs Are Kept As Rows (red)
    Use Fixture    insert into tablua_term (todo, n, i, source, passed, total) values ('t', 1, 1, 'real', 1, 2)
    Tested Actions Have Results

Failing Tests Have A Reach
    [Documentation]    Done further: a failing test's rows show how many of its keywords passed before it failed, and
    ...    that reach is above 0 for some, so it can rise while the test is still red.
    ...    Kill: no failing test in the sheet passed a keyword before failing.
    [Tags]    level:consistent    label:reach    predict:holds@0.7
    Use Trials    ${LABEL}
    Some Failing Test Reached Further

Failing Tests Have A Reach (red)
    Use Fixture    insert into tablua_result (todo, n, run, file, test, path, parent, depth, type, keyword, args, status, message, ms, line) values ('t', 1, 1, 'f', 'T', '1', '', 0, 'test', 'T', '', 'FAIL', 'x', 0, 1), ('t', 1, 1, 'f', 'T', '1.1', '1', 1, 'keyword', 'Should Be Equal', '', 'FAIL', 'x', 0, 2)
    Some Failing Test Reached Further

Decisions Keep What Was Read And Said
    [Documentation]    Every decision row keeps the state text the decision model read and what it said.
    ...    Kill: under 95% of 10 or more decisions have both.
    [Tags]    level:consistent    table:tablua_decision    predict:holds@0.8
    Use Trials    ${LABEL}
    Decisions Are Whole

Decisions Keep What Was Read And Said (red)
    Use Fixture    ${MANY} insert into tablua_decision (todo, n, chosen, by, said) select 't', i, 'work', 'free', 'work' from c
    Decisions Are Whole

The Prior Makes The Pick
    [Documentation]    From the history (TabICL barely tells moves apart): the decision model's own prior, not the
    ...    tabular part, decides. Kill: the move with the highest final p is the prior's top on under 90% of 20 or more.
    [Tags]    level:informative    hypothesis:prior    predict:holds@0.75
    Use Trials    ${LABEL}
    Prior Tops Agree

The Prior Makes The Pick (red)
    Use Fixture    ${MANY} insert into tablua_candidate (todo, n, move, jev_p, prior) select 't', i, 'work', 0.6, 0.2 from c    ${MANY} insert into tablua_candidate (todo, n, move, jev_p, prior) select 't', i, 'explore', 0.4, 0.8 from c
    Prior Tops Agree

*** Keywords ***
Tested Actions Have Results
    ${tested}=    Value Of    select count(*) from tablua_term where passed is not null
    ${results}=    Value Of    select count(*) from tablua_result
    Should Be True    ${tested} == 0 or ${results} > 0    ${tested} rows were tested but tablua_result has ${results} rows

Some Failing Test Reached Further
    ${failing}=    Value Of    select count(*) from tablua_result where type = 'test' and status = 'FAIL'
    Needs At Least    ${failing}    1    failing test runs
    ${reached}=    Value Of    select count(*) from tablua_result t where t.type = 'test' and t.status = 'FAIL' and exists (select 1 from tablua_result k where k.todo = t.todo and k.n = t.n and k.run = t.run and k.parent = t.path and k.status = 'PASS')
    Should Be True    ${reached} > 0    none of ${failing} failing test runs passed a keyword before failing

Decisions Are Whole
    ${all}=    Value Of    select count(*) from tablua_decision
    Needs At Least    ${all}    10    decisions
    ${whole}=    Value Of    select count(*) from tablua_decision where state is not null and state != '' and said is not null
    Should Be True    ${whole} >= 0.95 * ${all}    ${whole} of ${all} decisions keep both

Prior Tops Agree
    ${all}=    Value Of    select count(*) from (select todo, n from tablua_candidate where prior is not null group by todo, n having count(*) >= 2)
    Needs At Least    ${all}    20    decisions with two or more priors
    ${same}=    Value Of    select count(*) from (select todo, n, (select move from tablua_candidate c2 where c2.todo = c.todo and c2.n = c.n order by jev_p desc limit 1) as final, (select move from tablua_candidate c3 where c3.todo = c.todo and c3.n = c.n order by prior desc limit 1) as top from tablua_candidate c where prior is not null group by todo, n having count(*) >= 2) where final = top
    Should Be True    ${same} >= 0.9 * ${all}    the final pick is the prior's top on ${same} of ${all}
