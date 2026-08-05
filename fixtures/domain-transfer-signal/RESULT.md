# Domain transfer — scored, and the rule does not work

Companion to `FROZEN-prediction.md`, which was committed **before** the scorer existed
(`5a6cff0`; git order is the proof). Scorer and standing verdict:
`Tests/SwiftInferCoreTests/DomainTransferDiscriminatorExperimentTests.swift`.

## The measurement

Rule: **the parameter does not appear in the returned expression.** Scored against the 47
`idempotence` rows that executed in the 2026-08-05 whole-corpus survey — 5 refuted, 42 held. The
scan reached all 5 of the class and 20 of the held names.

| | count | |
|---|---:|---|
| flagged, and genuinely the class | **4** | `markovSynthesized`, `regressionFileHash`, `seedString`, `seedTuple` |
| flagged, but a law that HELD | **8** | `arrayElementType`, `bareTypeName`, `booleanStem`, `dedupedByStateAndAction`, `normalisedTypeName`, `quoted`, `stripGenerics`, `unwrappingRepetition` |
| the class, missed | **1** | `codableRoundTripGenerator` |

**Recall 4/5 (80%). Precision 4/12 (33%).** Shipping it would suppress **two true laws for every
false one removed**.

## The frozen prediction was right, on both halves

It predicted recall 4 of 5 and named the miss — `codableRoundTripGenerator`, because it returns
`renderGenerator(for: typeName)` and so does mention its parameter. It predicted precision *below
50%* and named the suspect — `dedupedByStateAndAction`, which is indeed flagged.

That matters more than being right: the prediction was falsifiable and specific, so the measurement
is a test of the *idea* rather than a description of an outcome.

## Why it fails, and why the reason generalises

*"The parameter is absent from the return expression"* is true of **every function that binds a
local and returns it**. That is a coding style, not a semantic property. `dedupedByStateAndAction`
accumulates into a local and returns it — and dedup is idempotent.

So the signal for domain transfer is **not in the return expression's shape**. It is in
**dataflow**: whether the parameter's *value* survives into the result, or merely seeds something
that replaces it. `seedString` hashes its input and returns a rendering of the digest; the input is
gone. `normalisedTypeName` binds a trimmed copy and returns it; the input is right there, one name
removed. No return-expression rule can tell those apart, because they are the same shape.

That is a strictly more expensive analysis than anything `IdempotenceReturnShape` performs — which
means **the classifier's refusal to veto this class was correct, not merely cautious.** Its doc
said *"not characterised well enough to veto on"*; this is the number behind that sentence.

## Two names that keep attracting cheap rules

`unwrappingRepetition` and `dedupedByStateAndAction` were both wrongly vetoed by item 18's first
bare-`+` rule, and both are wrongly flagged here by a completely different rule. A handful of
functions keep tripping every cheap heuristic aimed at this template.

The transferable practice is in how they were caught both times: **score a candidate veto against
the laws that HELD, not against the class it targets.** Recall against the target class is easy and
tells you almost nothing; the 42 held rows are where a veto's real cost is.

## Status of #93

Closed as **measured-not-buildable**. Not "no signal exists" — a dataflow analysis would likely work
— but the cheap return-expression version is refuted with numbers, and the next person is spared
re-deriving it. Reopen with a dataflow proposal, and score it against the same 47 rows.
