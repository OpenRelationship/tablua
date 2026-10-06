*** Settings ***
Documentation    Claims about the terminal as a spreadsheet (core/term, tablua.term, the bench's shell).
...              Each measured claim has a red proof: the same check on rows known to be wrong, which must fail.

*** Variables ***
${LAST}     runs/overfull-hbox-1006a.sqlite
${ALL}      runs/*.sqlite
${MANY}     with recursive c(i) as (select 1 union all select i + 1 from c where i < 40)

*** Test Cases ***
Program Is Never A Setup Command When Another Program Ran
    [Documentation]    command.parse skips cd and export: "cd /app && make" is make.
    ...    Oracle: none, our parser against our own rule. Kill: any row breaks it.
    [Tags]    level:consistent    column:program    predict:holds@0.95
    Use Sheets    ${ALL}
    No Setup Command As Program

Program Is Never A Setup Command When Another Program Ran (red)
    Use Fixture    insert into tablua_term (todo, n, i, source, program, programs) values ('t', 1, 1, 'real', 'cd', 'cd,make')
    No Setup Command As Program

Programs Match What Bash Ran
    [Documentation]    The programs column (term.command, from the keys) names what bash itself started, in order.
    ...    Oracle: the ran column, bash's DEBUG trap, read apart from term.command. Kill: below 90% of 20 or more actions.
    [Tags]    level:correct    column:programs    predict:holds@0.6
    Use Sheets    ${ALL}
    Programs Agree With Bash

Programs Match What Bash Ran (red)
    Use Fixture    ${MANY} insert into tablua_term (todo, n, i, source, programs, ran) select 't', i, 1, 'real', 'make', 'cd,make' from c
    Programs Agree With Bash

First Output Time Is Measured, Not The Poll Interval
    [Documentation]    first_ms is when a command first printed, past its echo.
    ...    Kill: 90% or more of the values are 0 or exactly one poll (100 ms), so the column only counts polls.
    ...    Since 2026-10-06 11:17 (0ecafd3) it is timed in milliseconds; it reads only trials fetched after that fix
    ...    (label replicate), since sheets kept before it always counted polls.
    [Tags]    level:consistent    column:first_ms    predict:holds@0.75
    Use Trials    replicate
    First Output Is Not Just Polls

First Output Time Is Measured, Not The Poll Interval (red)
    Use Fixture    ${MANY} insert into tablua_term (todo, n, i, source, first_ms) select 't', i, 1, 'real', (i % 2) * 100 from c
    First Output Is Not Just Polls

Every Test Run Is Kept As Rows
    [Documentation]    When the bench runs the agent's tests, their keyword tree lands in tablua_result.
    ...    Kill: a sheet whose term rows show tests (passed is set) has no result rows.
    [Tags]    level:consistent    table:tablua_result    predict:KILLED@0.99
    Use Sheet    ${LAST}
    Tested Actions Have Results

Every Test Run Is Kept As Rows (red)
    Use Fixture    insert into tablua_term (todo, n, i, source, passed, total) values ('t', 1, 1, 'real', 1, 2)
    Tested Actions Have Results

Broken Detector Catches A Return Value Compared Whole
    [Documentation]    A test that assigns Run And Return Rc And Output to one variable compares a list to a number,
    ...    so it can never pass; the detector must call it broken. Taken from step 25's failing test.
    ...    Kill: the detector says not broken.
    [Tags]    level:correct    code:bench/tests.broken    predict:holds@0.95
    Detector Says Broken    [1, 0] != 0

Broken Detector Catches A Return Value Compared Whole (red)
    Detector Says Broken    'abc' does not contain 'x'

Read Events Predict A Failed Command
    [Documentation]    The events term.read finds on a screen rank failed commands (exit not 0) above the rest.
    ...    Kill: AUROC within 0.1 of its shuffled mean, or p above 0.05, over 10 or more of each.
    [Tags]    level:informative    column:events    predict:unknown@0.55
    Use Sheets    ${ALL}
    Events Rank Failures

Read Events Predict A Failed Command (red)
    Use Fixture    ${MANY} insert into tablua_term (todo, n, i, source, failed) select 't', i, 1, 'real', i % 2 from c
    Events Rank Failures

Red Lines Mark Failures
    [Documentation]    Lines in red in the raw bytes rank failed commands above the rest.
    ...    Kill: AUROC within 0.1 of its shuffled mean, or p above 0.05, once 20 commands have shown red.
    [Tags]    level:informative    column:red    predict:unknown@0.9
    Use Sheets    ${ALL}
    ${reds}=    Value Of    select count(*) from tablua_term where source = 'real' and red > 0
    Needs At Least    ${reds}    20    commands that showed red
    Red Ranks Failures

Red Lines Mark Failures (red)
    Use Fixture    ${MANY} insert into tablua_term (todo, n, i, source, failed, red) select 't', i, 1, 'real', i % 2, 1 from c
    Red Ranks Failures

Our Green Suite Means The Verifier Passes
    [Documentation]    When the agent's own tests all pass, Harbor's verifier passes too.
    ...    Kill: mean reward below 0.8 over 10 or more trials that went green.
    [Tags]    level:useful    loop:tests    predict:unknown@0.99
    Use Sheet    ledger.sqlite
    Green Trials Pass The Verifier

Our Green Suite Means The Verifier Passes (red)
    Use Fixture    ${MANY} insert into trial (job, trial, reward, green) select 'j', i, 0, 1 from c
    Green Trials Pass The Verifier

*** Keywords ***
No Setup Command As Program
    ${n}=    Count Of    select 1 from tablua_term where program in ('cd','export','set','source') and programs like '%,%'
    Should Be True    ${n} == 0    ${n} rows name a setup command while another program ran

Programs Agree With Bash
    ${g}=    Agreement Of    select programs as a, ran as b from tablua_term where source = 'real' and ran is not null    min=20
    ${d}=    Disagreements Of    select programs as a, ran as b from tablua_term where source = 'real' and ran is not null
    Should Be True    ${g} >= 0.9    agreement ${g}; ours vs bash: ${d}

First Output Is Not Just Polls
    ${all}=    Value Of    select count(*) from tablua_term where source = 'real' and first_ms is not null
    Needs At Least    ${all}    20    actions with a first output time
    ${polls}=    Value Of    select count(*) from tablua_term where source = 'real' and first_ms in (0, 100)
    Should Be True    ${polls} < 0.9 * ${all}    ${polls} of ${all} first_ms values are 0 or one poll

Tested Actions Have Results
    ${tested}=    Value Of    select count(*) from tablua_term where passed is not null
    ${results}=    Value Of    select count(*) from tablua_result
    Should Be True    ${tested} == 0 or ${results} > 0    ${tested} rows were tested but tablua_result has ${results} rows

Detector Says Broken
    [Arguments]    ${message}
    ${b}=    Bench Calls It Broken    ${message}
    Should Be True    ${b} == 1    tests.broken does not call "${message}" broken

Events Rank Failures
    ${r}=    AUROC Against Shuffled    select (select count(*) from tablua_event e where e.todo = t.todo and e.n = t.n and e.i = t.i and e.source = 'real') as score, failed as label from tablua_term t where t.source = 'real' and t.failed is not null
    Should Be True    $r[1] - $r[2] >= 0.1 and $r[3] <= 0.05    AUROC ${r}[0] against shuffled ${r}[1], p ${r}[2]

Red Ranks Failures
    ${r}=    AUROC Against Shuffled    select red as score, failed as label from tablua_term where source = 'real' and failed is not null and red is not null
    Should Be True    $r[1] - $r[2] >= 0.1 and $r[3] <= 0.05    AUROC ${r}[0] against shuffled ${r}[1], p ${r}[2]

Green Trials Pass The Verifier
    ${m}=    Mean Of    select reward from trial where green = 1 and reward is not null
    Should Be True    ${m} >= 0.8    mean reward ${m} over trials that went green
