*** Settings ***
Documentation    Is the writer the limit? Overfull-hbox passed 1 of 33 trials on 2026-10-06 with the quantized Qwen3.6-35B
...              writer on Modal, and a control on the 11:23 code scored 0 of 4 as the repaired code did: the harness keeps
...              its rules (main.tex untouched, no deaths, step 1 in seconds) but the writer does not find synonym swaps
...              that clear the overfull boxes. Three stronger writers through OpenRouter, everything else unchanged (the
...              decider, world model and encoder still the Modal Qwen pair, the policy picking moves): one arm of 4
...              overfull-hbox trials each, run at once. The oracle is Harbor's verifier. Predictions committed before the
...              runs.

*** Test Cases ***
Qwen Max Passes Half The Time
    [Documentation]    Writer qwen/qwen3.8-max-0902. Kill: fewer than 2 of 4 scored trials pass.
    [Tags]    level:useful    writer:qwen-max    predict:holds@0.35
    Use Trials    writer-qwen-max
    Half Pass

Gemini Flash Passes Half The Time
    [Documentation]    Writer google/gemini-3.8-flash. Kill: fewer than 2 of 4 scored trials pass.
    [Tags]    level:useful    writer:gemini-flash    predict:holds@0.35
    Use Trials    writer-gemini-flash
    Half Pass

Qwen Flash Passes Half The Time
    [Documentation]    Writer qwen/qwen3.8-flash. Kill: fewer than 2 of 4 scored trials pass.
    [Tags]    level:useful    writer:qwen-flash    predict:holds@0.2
    Use Trials    writer-qwen-flash
    Half Pass

A Stronger Writer Beats The Modal Qwen
    [Documentation]    At least one of the three arms passes more overfull-hbox trials than the Modal Qwen's 1 of 33.
    ...    Read across the three arms' trials. Kill: no arm passes any trial (all 12 scored, 0 passed).
    [Tags]    level:useful    writer:any    predict:holds@0.6
    Use Trials    writer-qwen-max    writer-gemini-flash    writer-qwen-flash
    Some Pass

Qwen Max Passes Half The Time (red)
    Use Fixture    insert into trial (job, trial, task, reward) values ('j', 'a', 'overfull-hbox', 0), ('j', 'b', 'overfull-hbox', 0), ('j', 'c', 'overfull-hbox', 1), ('j', 'd', 'overfull-hbox', 0)
    Half Pass

Gemini Flash Passes Half The Time (red)
    Use Fixture    insert into trial (job, trial, task, reward) values ('j', 'a', 'overfull-hbox', 0), ('j', 'b', 'overfull-hbox', 0), ('j', 'c', 'overfull-hbox', 1), ('j', 'd', 'overfull-hbox', 0)
    Half Pass

Qwen Flash Passes Half The Time (red)
    Use Fixture    insert into trial (job, trial, task, reward) values ('j', 'a', 'overfull-hbox', 0), ('j', 'b', 'overfull-hbox', 0), ('j', 'c', 'overfull-hbox', 1), ('j', 'd', 'overfull-hbox', 0)
    Half Pass

A Stronger Writer Beats The Modal Qwen (red)
    Use Fixture    with recursive c(i) as (select 1 union all select i + 1 from c where i < 12) insert into trial (job, trial, task, reward) select 'j', 't' || i, 'overfull-hbox', 0 from c
    Some Pass

*** Keywords ***
Half Pass
    ${scored}=    Value Of    select count(*) from trial where task = 'overfull-hbox' and reward is not null
    Needs At Least    ${scored}    4    scored overfull-hbox trials
    ${passed}=    Value Of    select count(*) from trial where task = 'overfull-hbox' and reward = 1
    Should Be True    ${passed} >= 2    ${passed} of ${scored} overfull-hbox trials passed

Some Pass
    ${scored}=    Value Of    select count(*) from trial where task = 'overfull-hbox' and reward is not null
    Needs At Least    ${scored}    12    scored trials across the three writers
    ${passed}=    Value Of    select count(*) from trial where task = 'overfull-hbox' and reward = 1
    Should Be True    ${passed} >= 1    ${passed} of ${scored} passed across the three writers
