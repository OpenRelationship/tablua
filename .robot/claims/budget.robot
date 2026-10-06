*** Settings ***
Documentation    Where overfull-hbox's 750 s went on the 14:13 run (2026-10-06): step 1 took 115 to 137 s, nearly all of it
...              apt-get installing tmux in the task's container; and 3 of 4 trials went silent at 14:19 within six
...              seconds of each other, no request reaching Modal, and their hosts ended about five minutes later with no
...              error logged. Fixes: a static tmux copied in before the first step, every slow container call and the
...              host's exit logged, the writer's calls given their own timeout. Measured on the trials fetched as budget
...              (overfull-hbox, 4 trials). Predictions committed before the fixes were built.

*** Variables ***
${LABEL}    budget

*** Test Cases ***
The First Step Is Quick
    [Documentation]    Step 1 (the decision at step 2 less the one at step 1) takes under 30 s: the terminal opens
    ...    without installing anything. Kill: under 90% of 4 or more trials. On the 14:13 run, 0 of 4.
    [Tags]    level:consistent    repair:tmux    predict:holds@0.85
    Use Trials    ${LABEL}
    First Steps Are Quick

The First Step Is Quick (red)
    Use Fixture    insert into tablua_decision (todo, n, chosen, by, at) values ('a', 1, 'explore', 'free', '2026-10-06T21:13:46Z'), ('a', 2, 'plan_tests', 'free', '2026-10-06T21:15:41Z'), ('b', 1, 'explore', 'free', '2026-10-06T21:13:46Z'), ('b', 2, 'plan_tests', 'free', '2026-10-06T21:13:50Z'), ('c', 1, 'explore', 'free', '2026-10-06T21:13:46Z'), ('c', 2, 'plan_tests', 'free', '2026-10-06T21:15:00Z'), ('d', 1, 'explore', 'free', '2026-10-06T21:13:46Z'), ('d', 2, 'plan_tests', 'free', '2026-10-06T21:13:59Z')
    First Steps Are Quick

No Trial Dies
    [Documentation]    Every trial ends by answering or at the benchmark's time limit; none ends with its host gone and
    ...    nothing said (the ledger's ended: died). The oracle is Harbor's result (its exception) and the run's own
    ...    record (whether it said anything). Kill: any trial died. On the 14:13 run, 3 of 4 did.
    [Tags]    level:consistent    repair:silent    predict:holds@0.55
    Use Trials    ${LABEL}
    None Died

No Trial Dies (red)
    Use Fixture    insert into trial (job, trial, task, reward, ended) values ('j', 'a', 'overfull-hbox', 0, 'timeout'), ('j', 'b', 'overfull-hbox', 0, 'died'), ('j', 'c', 'overfull-hbox', 1, 'answered'), ('j', 'd', 'overfull-hbox', 0, 'answered')
    None Died

Overfull Hbox Passes Half The Time With Its Budget Back
    [Documentation]    With the time back, the verifier passes at least 2 of 4 overfull-hbox trials. Kill: fewer than 2
    ...    of 4 scored trials pass.
    [Tags]    level:useful    repair:outcome    predict:holds@0.3
    Use Trials    ${LABEL}
    Half Pass

Overfull Hbox Passes Half The Time With Its Budget Back (red)
    Use Fixture    insert into trial (job, trial, task, reward) values ('j', 'a', 'overfull-hbox', 0), ('j', 'b', 'overfull-hbox', 0), ('j', 'c', 'overfull-hbox', 1), ('j', 'd', 'overfull-hbox', 0)
    Half Pass

*** Keywords ***
First Steps Are Quick
    ${all}=    Value Of    select count(*) from tablua_decision a join tablua_decision b on b.todo = a.todo and b.n = 2 where a.n = 1
    Needs At Least    ${all}    4    trials with a second step
    ${quick}=    Value Of    select count(*) from tablua_decision a join tablua_decision b on b.todo = a.todo and b.n = 2 where a.n = 1 and (julianday(b.at) - julianday(a.at)) * 86400 < 30
    Should Be True    ${quick} >= 0.9 * ${all}    ${quick} of ${all} first steps took under 30 s

None Died
    ${all}=    Value Of    select count(*) from trial where ended is not null and ended <> ''
    Needs At Least    ${all}    4    trials with a known ending
    ${died}=    Value Of    select count(*) from trial where ended = 'died'
    Should Be True    ${died} == 0    ${died} of ${all} trials died with nothing said

Half Pass
    ${scored}=    Value Of    select count(*) from trial where task = 'overfull-hbox' and reward is not null
    Needs At Least    ${scored}    4    scored overfull-hbox trials
    ${passed}=    Value Of    select count(*) from trial where task = 'overfull-hbox' and reward = 1
    Should Be True    ${passed} >= 2    ${passed} of ${scored} overfull-hbox trials passed
