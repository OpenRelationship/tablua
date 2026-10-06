*** Settings ***
Documentation    Labels other than "complete" for a step: further (the work moved on) and safe (nothing got worse),
...              against how the trial ended (Harbor's reward, viable in hindsight). Rows: runs/labels.sqlite, built by
...              tablua-local/tl/labels.py from the ledger's trials, their sheets and the decider history.
...              Predictions committed 2026-10-06 before the replication run (11:23, 12 trials) was fetched.

*** Variables ***
${SHEET}    runs/labels.sqlite
${MANY}     with recursive c(i) as (select 1 union all select i + 1 from c where i < 40)

*** Test Cases ***
Complete Barely Varies
    [Documentation]    Nearly every step completes, so the label the tabular part learns says little.
    ...    Kill: under 80% of the steps with a known outcome completed.
    [Tags]    level:consistent    label:complete    predict:holds@0.75
    Use Sheet    ${SHEET}
    Most Steps Complete

Complete Barely Varies (red)
    Use Fixture    create table step (trial, n, further, safe, complete)    ${MANY} insert into step select 't', i, 0, 1, i % 2 from c
    Most Steps Complete

Further Ranks Passing Trials Higher
    [Documentation]    Trials whose steps more often moved the work on are the ones that passed.
    ...    Kill: AUROC of the share of further steps for reward within 0.1 of shuffled, or p above 0.05, 5 or more of each.
    [Tags]    level:informative    label:further    predict:holds@0.5
    Use Sheet    ${SHEET}
    Share Ranks Passing    further

Further Ranks Passing Trials Higher (red)
    Use Fixture    create table trials (trial, reward, further, safe, complete)    ${MANY} insert into trials select i, i % 2, 0.5, 1, 0.9 from c
    Share Ranks Passing    further

Further Beats Complete At Ranking Trials
    [Documentation]    Done further, not done: the share of further steps ranks passing trials better than the share of
    ...    complete ones. Kill: its AUROC is not at least 0.05 above complete's, 5 or more trials of each kind.
    [Tags]    level:informative    label:further    predict:holds@0.55
    Use Sheet    ${SHEET}
    Further Above Complete

Further Beats Complete At Ranking Trials (red)
    Use Fixture    create table trials (trial, reward, further, safe, complete)    ${MANY} insert into trials select i, i % 2, 0.5, 1, 0.5 + (i % 2) * 0.3 from c
    Further Above Complete

Safe Ranks Passing Trials Higher
    [Documentation]    Trials whose steps made nothing worse are the ones that passed.
    ...    Kill: AUROC of the share of safe steps for reward within 0.1 of shuffled, or p above 0.05, 5 or more of each.
    [Tags]    level:informative    label:safe    predict:KILLED@0.6
    Use Sheet    ${SHEET}
    Share Ranks Passing    safe

Safe Ranks Passing Trials Higher (red)
    Use Fixture    create table trials (trial, reward, further, safe, complete)    ${MANY} insert into trials select i, i % 2, 0.5, 1, 0.9 from c
    Share Ranks Passing    safe

*** Keywords ***
Most Steps Complete
    ${all}=    Value Of    select count(*) from step where complete is not null
    Needs At Least    ${all}    20    steps with a known outcome
    ${done}=    Value Of    select count(*) from step where complete = 1
    Should Be True    ${done} >= 0.8 * ${all}    ${done} of ${all} steps completed

Share Ranks Passing
    [Arguments]    ${label}
    ${auc}    ${null}    ${p}=    AUROC Against Shuffled    select ${label} as score, reward > 0 as label from trials where ${label} is not null    min=5
    Should Be True    ${auc} - ${null} >= 0.1 and ${p} <= 0.05    AUROC ${auc} against shuffled ${null}, p ${p}

Further Above Complete
    ${f}    ${fn}    ${fp}=    AUROC Against Shuffled    select further as score, reward > 0 as label from trials where further is not null and complete is not null    min=5
    ${c}    ${cn}    ${cp}=    AUROC Against Shuffled    select complete as score, reward > 0 as label from trials where further is not null and complete is not null    min=5
    Should Be True    ${f} - ${c} >= 0.05    further's AUROC ${f} against complete's ${c}
