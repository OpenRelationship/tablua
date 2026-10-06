*** Settings ***
Documentation    From the 14:42 run (2026-10-06): one host was killed by SIGPIPE mid-step (a socket closed under it; libcurl
...              sets NOSIGNAL but TLS writes can still raise it), and one trial answered at step 7, its suite made green by
...              a plan rewrite alone: a broken placeholder line was dropped, leaving "Command Should Succeed    grep -cv
...              'Overfull \hbox' out.txt", which succeeds whenever any other line exists. The verifier found the overfull
...              boxes still there. Fixes: the host ignores SIGPIPE; a revision whose rewritten tests pass with nothing done
...              since is refused; grep -c with -v counts as no check. Measured on the trials fetched as green
...              (overfull-hbox, 4 trials). Predictions committed before the fixes were built.

*** Variables ***
${LABEL}    green

*** Test Cases ***
No Trial Dies Of A Signal
    [Documentation]    Every trial ends by answering or at the time limit (the ledger's ended). Kill: any died.
    [Tags]    level:consistent    repair:sigpipe    predict:holds@0.7
    Use Trials    ${LABEL}
    None Died

No Trial Dies Of A Signal (red)
    Use Fixture    insert into trial (job, trial, task, reward, ended) values ('j', 'a', 'overfull-hbox', 0, 'timeout'), ('j', 'b', 'overfull-hbox', 0, 'died'), ('j', 'c', 'overfull-hbox', 1, 'answered'), ('j', 'd', 'overfull-hbox', 0, 'answered')
    None Died

An Answer Is Right
    [Documentation]    When a trial answers (its suite went green), the verifier passes it. The oracle is Harbor's
    ...    verifier. Kill: fewer than half of the answered trials pass, with 2 or more answered.
    [Tags]    level:useful    repair:green    predict:holds@0.4
    Use Trials    ${LABEL}
    Answers Pass

An Answer Is Right (red)
    Use Fixture    insert into trial (job, trial, task, reward, ended) values ('j', 'a', 'overfull-hbox', 0, 'answered'), ('j', 'b', 'overfull-hbox', 0, 'answered'), ('j', 'c', 'overfull-hbox', 1, 'answered'), ('j', 'd', 'overfull-hbox', 0, 'timeout')
    Answers Pass

Overfull Hbox Passes Half The Time
    [Documentation]    The verifier passes at least 2 of 4 overfull-hbox trials. Kill: fewer than 2 of 4 scored.
    [Tags]    level:useful    repair:outcome    predict:holds@0.25
    Use Trials    ${LABEL}
    Half Pass

Overfull Hbox Passes Half The Time (red)
    Use Fixture    insert into trial (job, trial, task, reward) values ('j', 'a', 'overfull-hbox', 0), ('j', 'b', 'overfull-hbox', 0), ('j', 'c', 'overfull-hbox', 1), ('j', 'd', 'overfull-hbox', 0)
    Half Pass

*** Keywords ***
None Died
    ${all}=    Value Of    select count(*) from trial where ended is not null and ended <> ''
    Needs At Least    ${all}    4    trials with a known ending
    ${died}=    Value Of    select count(*) from trial where ended = 'died'
    Should Be True    ${died} == 0    ${died} of ${all} trials died with nothing said

Answers Pass
    ${answered}=    Value Of    select count(*) from trial where ended = 'answered' and reward is not null
    Needs At Least    ${answered}    2    answered trials
    ${right}=    Value Of    select count(*) from trial where ended = 'answered' and reward = 1
    Should Be True    ${right} >= 0.5 * ${answered}    ${right} of ${answered} answers passed the verifier

Half Pass
    ${scored}=    Value Of    select count(*) from trial where task = 'overfull-hbox' and reward is not null
    Needs At Least    ${scored}    4    scored overfull-hbox trials
    ${passed}=    Value Of    select count(*) from trial where task = 'overfull-hbox' and reward = 1
    Should Be True    ${passed} >= 2    ${passed} of ${scored} overfull-hbox trials passed
