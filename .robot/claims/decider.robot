*** Settings ***
Documentation    Why the decider points at the same move again and again (81% of 2,499 picks repeat the one before).
...              Three explanations: it sees something real (signal); its context window pulls it back (context bias);
...              or what the tabular part learned, "the step completes", rewards busywork (wrong label).
...              Rows: runs/decider-history.sqlite, built by tablua-local/tl/history.py from every host.log's decisions
...              joined to ~/tb/minds.db's transitions, with TabICL and the nearest-states rate replayed per run on the
...              runs before it. Predictions committed 2026-10-06 before the sheet was built.

*** Variables ***
${HISTORY}    runs/decider-history.sqlite
${MANY}       with recursive c(i) as (select 1 union all select i + 1 from c where i < 40)

*** Test Cases ***
The History Joins Picks To States
    [Documentation]    Each logged pick lines up with its transition: the move the log says was taken is the one
    ...    minds.db recorded for that step. Kill: under 95% of joined rows agree, so every claim below reads noise.
    [Tags]    level:consistent    table:decision    predict:holds@0.8
    Use Sheet    ${HISTORY}
    Taken Moves Line Up

The History Joins Picks To States (red)
    Use Fixture    create table decision (run, n, said, taken, logged_taken)    ${MANY} insert into decision select 'r', i, 'work', 'work', 'fix' from c
    Taken Moves Line Up

The Tabular Part Alone Favours Busywork
    [Documentation]    Wrong label: TabICL, asked which offered move completes, most often names explore or work.
    ...    Kill: explore or work is its top move on under 70% of steps where both were offered with another.
    [Tags]    level:consistent    model:tabicl    predict:holds@0.6
    Use Sheet    ${HISTORY}
    Tabular Top Is Busywork

The Tabular Part Alone Favours Busywork (red)
    Use Fixture    create table replay (run, n, move, tab_p)    ${MANY} insert into replay select 'r', i, 'explore', 0.2 from c    ${MANY} insert into replay select 'r', i, 'work', 0.3 from c    ${MANY} insert into replay select 'r', i, 'plan_tests', 0.9 from c
    Tabular Top Is Busywork

The Tabular Part Barely Tells Moves Apart
    [Documentation]    Too powerful and not real: across the moves offered at a step, TabICL's p_complete spans little,
    ...    yet it scales every pick by 0.5 + p. Kill: the median spread (top less bottom) is 0.15 or more.
    [Tags]    level:consistent    model:tabicl    predict:holds@0.6
    Use Sheet    ${HISTORY}
    Tabular Spread Is Small

The Tabular Part Barely Tells Moves Apart (red)
    Use Fixture    create table replay (run, n, move, tab_p)    ${MANY} insert into replay select 'r', i, 'explore', 0.1 from c    ${MANY} insert into replay select 'r', i, 'work', 0.9 from c
    Tabular Spread Is Small

Picks Change When The State Changes
    [Documentation]    Signal: when the step before changed where the work stood (its outcome, the pass rate, the kind
    ...    of error), the decider changes its pick more often than when nothing changed.
    ...    Kill: the rate of changed picks is not at least 0.1 higher after a change, or p above 0.05.
    [Tags]    level:informative    hypothesis:signal    predict:KILLED@0.65
    Use Sheet    ${HISTORY}
    Changes Follow The State

Picks Change When The State Changes (red)
    Use Fixture    create table decision (run, n, pick_changed, state_changed)    ${MANY} insert into decision select 'r', i, i % 2, (i / 2) % 2 from c
    Changes Follow The State

The Nag Stops Once Its Move Is Taken
    [Documentation]    Signal: in the free loop, once the move the decider said is the move taken, it moves on.
    ...    Kill: it says the same move again on half or more of the steps after its move was taken (20 or more).
    [Tags]    level:informative    hypothesis:signal    predict:KILLED@0.6
    Use Sheet    ${HISTORY}
    Nag Moves On

The Nag Stops Once Its Move Is Taken (red)
    Use Fixture    create table decision (run, n, said, taken, free)    ${MANY} insert into decision select 'r', i, 'fix', 'fix', 1 from c
    Nag Moves On

Reach Predicts The Outcome Better Than Complete
    [Documentation]    Done further, not done: how far the failing tests reach rising ranks runs that end green above
    ...    the rest better than the share of steps that completed. Kill: its AUROC is not 0.05 above complete's.
    [Tags]    level:informative    label:reach    predict:holds@0.65
    Skip    needs test runs kept as rows with their reach (the terminal claim Every Test Run Is Kept As Rows)

*** Keywords ***
Taken Moves Line Up
    ${g}=    Agreement Of    select taken as a, logged_taken as b from decision where logged_taken is not null    min=20
    ${d}=    Disagreements Of    select taken as a, logged_taken as b from decision where logged_taken is not null
    Should Be True    ${g} >= 0.95    agreement ${g}: ${d}

Tabular Top Is Busywork
    ${steps}=    Value Of    select count(*) from (select run, n from replay group by run, n having count(*) >= 2 and sum(move in ('explore','work')) >= 1 and sum(move not in ('explore','work')) >= 1)
    Needs At Least    ${steps}    20    steps offering busywork and something else
    ${busy}=    Value Of    select count(*) from (select run, n, (select move from replay r2 where r2.run = r.run and r2.n = r.n order by tab_p desc limit 1) as top from replay r group by run, n having count(*) >= 2 and sum(move in ('explore','work')) >= 1 and sum(move not in ('explore','work')) >= 1) where top in ('explore','work')
    Should Be True    ${busy} >= 0.7 * ${steps}    TabICL tops with busywork on ${busy} of ${steps} steps

Tabular Spread Is Small
    ${steps}=    Value Of    select count(*) from (select run, n from replay group by run, n having count(*) >= 2)
    Needs At Least    ${steps}    20    steps with two or more moves
    ${median}=    Value Of    select s from (select max(tab_p) - min(tab_p) as s from replay group by run, n having count(*) >= 2) order by s limit 1 offset (select count(*) / 2 from (select 1 from replay group by run, n having count(*) >= 2))
    Should Be True    ${median} < 0.15    median spread ${median}

Changes Follow The State
    ${gap}    ${null}    ${p}=    Gap Against Shuffled    select pick_changed as value, state_changed as "group" from decision where pick_changed is not null and state_changed is not null
    Should Be True    ${gap} - ${null} >= 0.1 and ${p} <= 0.05    picks changed ${gap} more often after a change (shuffled ${null}), p ${p}

Nag Moves On
    ${n}=    Value Of    select count(*) from decision d where free = 1 and said = taken and exists (select 1 from decision e where e.run = d.run and e.n = d.n + 1)
    Needs At Least    ${n}    20    free-loop steps that took the decider's move
    ${again}=    Value Of    select count(*) from decision d join decision e on e.run = d.run and e.n = d.n + 1 where d.free = 1 and d.said = d.taken and e.said = d.said
    Should Be True    ${again} < 0.5 * ${n}    it said the same move again on ${again} of ${n} steps after it was taken
