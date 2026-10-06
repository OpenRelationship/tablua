*** Settings ***
Documentation    Whether the decision model's prior (GLiNER2.5-Decide, which made 36 of 37 picks in the rows-on run) reads
...              the work or the wording. Each rows-on decision's saved state text is asked again (tablua-local/tl/
...              perturb.py) as it was, with the moves in reverse order, with the state blanked, with the moves
...              reworded, and without the note "The last N moves were all X". Rows: runs/perturb.sqlite, table
...              perturb (todo, n, variant, top, logged, note). Predictions committed 2026-10-06 before it was built.

*** Variables ***
${SHEET}    runs/perturb.sqlite
${MANY}     with recursive c(i) as (select 1 union all select i + 1 from c where i < 40)

*** Test Cases ***
The Replay Reproduces The Logged Prior
    [Documentation]    Asked again as it was, the prior tops the same move it topped in the run.
    ...    Kill: under 90% of 30 or more agree, so the replay is not the run and the claims below read something else.
    [Tags]    level:consistent    replay:fidelity    predict:holds@0.7
    Use Sheet    ${SHEET}
    Variant Agrees    real    logged    0.9

The Replay Reproduces The Logged Prior (red)
    Use Fixture    create table perturb (todo, n, variant, top, logged, note)    ${MANY} insert into perturb select 't', i, 'real', 'work', 'fix', 0 from c
    Variant Agrees    real    logged    0.9

The Prior Survives Reordering The Moves
    [Documentation]    Context bias, order: with the offered moves in reverse order, the prior tops the same move.
    ...    Kill: it changes on more than 20% of 30 or more decisions.
    [Tags]    level:correct    hypothesis:context    predict:holds@0.6
    Use Sheet    ${SHEET}
    Variant Agrees    reversed    real    0.8

The Prior Survives Reordering The Moves (red)
    Use Fixture    create table perturb (todo, n, variant, top, logged, note)    ${MANY} insert into perturb select 't', i, 'real', 'work', 'work', 0 from c    ${MANY} insert into perturb select 't', i, 'reversed', 'fix', 'work', 0 from c
    Variant Agrees    reversed    real    0.8

The Prior Reads The State
    [Documentation]    Signal: with the state text blanked (N/A), the prior's top differs from its top on the real state.
    ...    Kill: the blank state tops the same move on more than 70% of 30 or more decisions: the state barely matters.
    [Tags]    level:informative    hypothesis:signal    predict:KILLED@0.55
    Use Sheet    ${SHEET}
    Variant Differs    blank    real    0.3

The Prior Reads The State (red)
    Use Fixture    create table perturb (todo, n, variant, top, logged, note)    ${MANY} insert into perturb select 't', i, 'real', 'work', 'work', 0 from c    ${MANY} insert into perturb select 't', i, 'blank', 'work', 'work', 0 from c
    Variant Differs    blank    real    0.3

The Prior Survives Rewording The Moves
    [Documentation]    Context bias, wording: with each move described in other words of the same meaning, the prior tops
    ...    the same move. Kill: it changes on more than 20% of 30 or more decisions.
    [Tags]    level:correct    hypothesis:context    predict:KILLED@0.55
    Use Sheet    ${SHEET}
    Variant Agrees    reworded    real    0.8

The Prior Survives Rewording The Moves (red)
    Use Fixture    create table perturb (todo, n, variant, top, logged, note)    ${MANY} insert into perturb select 't', i, 'real', 'work', 'work', 0 from c    ${MANY} insert into perturb select 't', i, 'reworded', 'fix', 'work', 0 from c
    Variant Agrees    reworded    real    0.8

The Run Note Does Not Drive The Pick
    [Documentation]    The state says "The last N moves were all X" after three of a row; the prior tops the same move
    ...    without that sentence. Kill: it changes on more than 20% of the 10 or more decisions that had the note.
    [Tags]    level:correct    hypothesis:context    predict:holds@0.5
    Use Sheet    ${SHEET}
    ${n}=    Value Of    select count(*) from perturb where variant = 'no_note' and note = 1
    Needs At Least    ${n}    10    decisions whose state had the note
    ${g}=    Agreement Of    select v.top as a, r.top as b from perturb v join perturb r on r.todo = v.todo and r.n = v.n and r.variant = 'real' where v.variant = 'no_note' and v.note = 1
    Should Be True    ${g} >= 0.8    the top stayed on ${g} of the decisions with the note

The Run Note Does Not Drive The Pick (red)
    Use Fixture    create table perturb (todo, n, variant, top, logged, note)    ${MANY} insert into perturb select 't', i, 'real', 'work', 'work', 1 from c    ${MANY} insert into perturb select 't', i, 'no_note', 'fix', 'work', 1 from c
    ${g}=    Agreement Of    select v.top as a, r.top as b from perturb v join perturb r on r.todo = v.todo and r.n = v.n and r.variant = 'real' where v.variant = 'no_note' and v.note = 1
    Should Be True    ${g} >= 0.8    the top stayed on ${g} of the decisions with the note

*** Keywords ***
Variant Agrees
    [Arguments]    ${variant}    ${against}    ${at_least}
    ${g}=    Agreement Of    select v.top as a, ${against} as b from (select p.*, (select top from perturb r where r.todo = p.todo and r.n = p.n and r.variant = 'real') as real from perturb p where p.variant = '${variant}') v    min=30
    ${d}=    Disagreements Of    select v.top as a, ${against} as b from (select p.*, (select top from perturb r where r.todo = p.todo and r.n = p.n and r.variant = 'real') as real from perturb p where p.variant = '${variant}') v
    Should Be True    ${g} >= ${at_least}    ${variant} agrees with ${against} on ${g}: ${d}

Variant Differs
    [Arguments]    ${variant}    ${against}    ${at_least}
    ${g}=    Agreement Of    select v.top as a, ${against} as b from (select p.*, (select top from perturb r where r.todo = p.todo and r.n = p.n and r.variant = 'real') as real from perturb p where p.variant = '${variant}') v    min=30
    Should Be True    1 - ${g} >= ${at_least}    ${variant} differs from ${against} on only ${g} agreement
