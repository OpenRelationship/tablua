*** Settings ***
Documentation    Goal step 4 (2026-10-06): the sidecar learns "further" in place of "complete". Under complete the tabular
...              model's p was 0.77 to 0.83 for every move, its mean spread across a decision's moves 0.05 to 0.11 on the
...              14:59 and 15:18 runs: nearly every step completes, so it cannot tell moves apart (Complete Barely Varies
...              holds). further is 1 on 34% of steps (104 of 310 since 12:51). In the free loop the policy picks the
...              move and the decider's answer is only kept, so the switch changes what is learned and logged, not what
...              a run does. tablua_candidate.p_complete holds the p of the sidecar's target, further from here on.
...              Measured on the trials fetched as further (overfull-hbox, 4 trials). Predictions committed before the
...              switch was made.

*** Variables ***
${LABEL}    further

*** Test Cases ***
Further Tells Moves Apart
    [Documentation]    The tabular p's spread across a decision's moves (max less min) averages 0.15 or more over 20 or
    ...    more decisions. Kill: under 0.15. Under complete it was 0.05 to 0.11.
    [Tags]    level:consistent    label:further    predict:holds@0.45
    Use Trials    ${LABEL}
    Spread Is Wide

Further Tells Moves Apart (red)
    Use Fixture    with recursive c(i) as (select 1 union all select i + 1 from c where i < 25) insert into tablua_candidate (todo, n, move, p_complete) select 't', i, 'work', 0.80 from c union all select 't', i, 'fix', 0.77 from c
    Spread Is Wide

Further Is Not Always Yes
    [Documentation]    The tabular p averages under 0.6 across all candidates, near further's base rate (34%), not
    ...    complete's near-certainty. Kill: 0.6 or more over 50 or more candidates.
    [Tags]    level:consistent    label:further    predict:holds@0.7
    Use Trials    ${LABEL}
    Mean Is Low

Further Is Not Always Yes (red)
    Use Fixture    with recursive c(i) as (select 1 union all select i + 1 from c where i < 60) insert into tablua_candidate (todo, n, move, p_complete) select 't', i, 'work', 0.8 from c
    Mean Is Low

*** Keywords ***
Spread Is Wide
    ${n}=    Value Of    select count(*) from (select todo, n from tablua_candidate where p_complete is not null group by todo, n having count(*) > 1)
    Needs At Least    ${n}    20    decisions with two or more moves scored
    ${spread}=    Value Of    select avg(s) from (select max(p_complete) - min(p_complete) as s from tablua_candidate where p_complete is not null group by todo, n having count(*) > 1)
    Should Be True    ${spread} >= 0.15    the mean spread was ${spread}

Mean Is Low
    ${n}=    Value Of    select count(*) from tablua_candidate where p_complete is not null
    Needs At Least    ${n}    50    candidates scored
    ${mean}=    Value Of    select avg(p_complete) from tablua_candidate where p_complete is not null
    Should Be True    ${mean} < 0.6    the mean p was ${mean}
