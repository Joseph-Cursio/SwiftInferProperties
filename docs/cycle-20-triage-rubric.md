# Cycle-20 Triage Rubric

Methodology document for v1.23's empirical Possible-tier sampling pass on the post-v1.22 152-surface. Defines accept/reject/unknown criteria per template, what counts as evidence in single-runner triage, and how the rubric handles edge cases.

**Scope:** v1.23 / cycle 20 — the **fourth empirical-only cycle** in the calibration loop (after cycle 6 = v1.9 on the 349-surface, cycle 14 = v1.17 on the 229-surface, cycle 17 = v1.20 on the 335-surface). Carries cycle-17's per-template criteria verbatim; adds a "Post-cycle-17 mechanism context" section documenting the suppression layers (cycles 18 + 19) a v1.22 survivor has cleared.

**Companion to `docs/cycle-17-triage-rubric.md`, not a replacement.** The cycle-6 / cycle-14 / cycle-17 rubrics stay unchanged for forensic comparability with their respective samples. Resolves v1.23 plan §"Open decisions" #3 in favor of (a): carry-forward verbatim with cycle-20 supplement.

## What we're measuring

Each triaged suggestion is a *claim* SwiftInfer makes — "this code looks like it satisfies a `<template-name>` property." The triage decision answers: **does the property actually hold?**

- **Accept** — yes, the property holds for the function(s) as written.
- **Reject** — no, the property doesn't hold.
- **Unknown** — the rater can't determine the answer from public-API + commit-history evidence alone.

The §19 acceptance-rate target ("≥ 70% acceptance after 6 months of dogfooding") is computed as `accept / (accept + reject)`.

## Single-runner triage caveat

Same caveats as cycles 6 + 14 + 17:
- Public API + commit history evidence only — no test execution, no internal-implementation reading, no multi-rater consensus.
- One rater (Claude).

## Post-cycle-17 mechanism context

The cycle-20 sample is drawn from the **v1.22 152-surface**, which has been suppressed 335 → 152 (-54.6%) across two mechanism cycles since cycle 17:

- **Cycle 18 / v1.21** — three workstreams, -170 candidates closed:
  - V1.21.A IteratorProtocol carrier veto on idempotence-lifted (-22).
  - V1.21.B composition-lifted monotone-bounded label counter (demote-only on the lone `BucketIterator.advance(until:)` pick).
  - V1.21.C math-library forward-function counter on idempotence + round-trip non-lifted (-148; largest single-cycle mechanism in the loop's history).

- **Cycle 19 / v1.22** — four workstreams, -13 candidates closed:
  - V1.22.A BucketIterator name extension on V1.21.A (-3 OC).
  - V1.22.B `RoundTripTemplate` both-sides direction-counter -15 → -25 magnitude bump (-8: 7 OC + 1 Algo).
  - V1.22.C fixed-point-name positive signal (NEW class 14, FIRST recall-positive signal post-V1.4.3; 0 surfacing on cycle-1..14 corpora).
  - V1.22.D stride-style label both-sides veto on round-trip + inverse-pair (-2 Algo).

A v1.22 survivor on **round-trip / idempotence / idempotence-lifted / inverse-pair** has cleared 6-7 distinct mechanism classes that didn't exist at cycle 17. The rater should know which gates each surviving candidate has already passed.

This context **does not change the verdict thresholds** for cycle-17-baseline templates. The accept/reject criteria carry forward verbatim.

### Per-template suppression layers cleared at v1.22

**Round-trip** (18 v1.22 candidates) — six post-cycle-6 mechanism layers cleared (cycle-17 had four; +2 in cycle-18+19):

| Cycle | Release | Mechanism | Suppression weight | Suppression criterion |
|---|---|---|---:|---|
| 9 | V1.12.1 | direction-label counter (single-side) | −15 | either pair-side's first-param label ∈ `DirectionLabels.curated` |
| 12 | V1.15.1 | domain-marker counter | −15 | both pair-sides' first-param label ∈ `DomainMarkerLabels.curated` |
| 13 | V1.16.1 | SetAlgebra-shape veto | −25 | both pair-sides have `(Self) -> Self` shape AND both names ∈ `SetAlgebraShape.binaryOps` |
| 15 | V1.18.A | reference-type carrier counter | −10 | either pair-side's containing type classifies as `.referenceType` |
| 18 | V1.21.C | math-library forward-function pair veto | veto | both names ∈ `MathForwardFunctions.curated` AND not in `canonicalInversePairs` allowlist |
| 19 | V1.22.B | direction-counter both-sides full-veto | −25 | **both** pair-sides direction-labeled (extends V1.12.1) |
| 19 | V1.22.D | stride-style label both-sides veto | −25 | both pair-sides' first-param label ∈ `StrideStyleLabels.curated` |

**Idempotence (non-lifted)** (23 v1.22 candidates) — five post-cycle-6 mechanism layers cleared (cycle-17 had four; +1 in cycle-18):

| Cycle | Release | Mechanism | Suppression weight | Suppression criterion |
|---|---|---|---:|---|
| 7 | V1.10.1 | direction-label counter | −15 | first-param label ∈ `DirectionLabels.curated` |
| 12 | V1.15.1 | domain-marker counter | −15 | first-param label ∈ `DomainMarkerLabels.curated` |
| 13 | V1.16.1 | SetAlgebra-shape veto | −25 | `(Self) -> Self` shape AND function name ∈ `SetAlgebraShape.binaryOps` |
| 15 | V1.18.A | reference-type carrier counter | −10 | containing type classifies as `.referenceType` |
| 18 | V1.21.C | math-library forward-function veto | veto | name ∈ `MathForwardFunctions.curated` AND `(T) -> T` shape |

**Idempotence-lifted** (21 v1.22 candidates) — three post-cycle-16 mechanism layers cleared (cycle-17 had zero; +3 in cycle-18+19):

| Cycle | Release | Mechanism | Suppression weight | Suppression criterion |
|---|---|---|---:|---|
| 18 | V1.21.A | IteratorProtocol carrier veto | veto | carrier ∈ `inheritedTypesByName` with IteratorProtocol OR carrier=`Iterator` or `*.Iterator` AND method ∈ `iteratorMethodNames` |
| 19 | V1.22.A | BucketIterator name extension on V1.21.A | veto | extends V1.21.A with `hasSuffix("Iterator")` carrier match + `findNext`/`advanceToNextUnoccupiedBucket` method names |

**Inverse-pair (non-lifted)** (3 v1.22 candidates) — five post-cycle-6 mechanism layers cleared (cycle-17 had four; +1 in cycle-19):

| Cycle | Release | Mechanism | Weight | Criterion |
|---|---|---|---:|---|
| 8 | V1.11.1 | direction-label counter | −10 | (as round-trip's V1.12.1) |
| 11 | V1.14.1 | SetAlgebra-shape veto | −25 | (as round-trip's V1.16.1) |
| 12 | V1.15.1 | domain-marker counter | −15 | both pair-sides' first-param label in `DomainMarkerLabels.curated` |
| 15 | V1.18.A | reference-type carrier counter | −10 | (as round-trip) |
| 19 | V1.22.D | stride-style label both-sides veto | −25 | both pair-sides' first-param label ∈ `StrideStyleLabels.curated` |

**Composition (lifted)** (1 v1.22 candidate) — one post-cycle-16 mechanism layer (V1.21.B demote-only):

| Cycle | Release | Mechanism | Effect | Criterion |
|---|---|---|---|---|
| 18 | V1.21.B | monotone-bounded label counter | demote (-25; Strong → Likely) | first-param label ∈ `monotoneBoundedLabels` |

**Other templates (commutativity / associativity / monotonicity / identity-element / dual-style-consistency)** — **no new per-template mechanisms cycles 18+19**. Cycle-17 verdict thresholds apply to v1.22 survivors without modification.

### Curated suppression sets (for rationale-writing reference)

Carries forward from cycle-17 + adds v1.22 sets:

- (Carries forward, full list in `docs/cycle-17-triage-rubric.md`): `DirectionLabels.curated`, `DomainMarkerLabels.curated`, `SetAlgebraShape.binaryOps`, `CarrierKindResolver` allow-list, `Vocabulary.dualStyleNamePairs`, `CompositionTemplate.curatedAdditiveTypes`, `CompositionTemplate.curatedVerbs`, `InverseLiftedPairing.curatedPairs`, `IdentityNames.curated`, `MathForwardFunctions.curated`, `MathForwardFunctions.canonicalInversePairs`, `monotoneBoundedLabels`, `iteratorMethodNames` (V1.21.A), `IdempotenceTemplate.curatedVerbs`.
- **NEW V1.22.A:** extended `iteratorMethodNames` with `{findNext, advanceToNextUnoccupiedBucket}`; carrier-name fallback now matches `*Iterator` suffix (not just `*.Iterator`).
- **NEW V1.22.C:** `FixedPointNames.curated = {dedupe, simplify, clamp, truncate, standardize}` — recall-positive `+10` signal on non-lifted idempotence.
- **NEW V1.22.D:** `StrideStyleLabels.curated = {startingAt, endingAt, fromIndex, toIndex, startingFrom, from, to}` — both-sides veto on round-trip + inverse-pair.

### Cycle-17 → cycle-20 picks-status framing

Cycle-18 + cycle-19 findings have already documented which cycle-17 picks were closed by which subsequent mechanism. Cycle 20 is **fresh stratified sampling**, not cycle-17 picks reuse (v1.23 plan §"Open decisions" #4). Some natural overlap occurs (the lone CM identity-element survivor is the same cycle-6/14/17 pick); the per-pick verdict is re-derived freshly.

## Per-template criteria

The criteria for the **10 template classes** (round-trip, idempotence non-lifted, commutativity, associativity, inverse-pair non-lifted, monotonicity, identity-element non-lifted, dual-style-consistency, idempotence-lifted, composition-lifted) are carried forward verbatim from `docs/cycle-17-triage-rubric.md`. Edits would compromise cycle-17 ↔ cycle-20 rate-shift comparability. **Refer to `docs/cycle-17-triage-rubric.md` §"Per-template criteria"** for the full text.

The cycle-19 finding asymmetric-pair class (round-trip cross-pairs where one side is direction-labeled and the other is domain-marker-labeled) follows the cycle-17 round-trip rubric §"Reject" criterion: "the pair is *related* but semantically not inverses (e.g., `minimumCapacity(forScale:)` and `maximumCapacity(forScale:)` both take `scale` and return capacity but yield *different* capacities — `min(scale(c)) == c` doesn't hold across the cross-product)." The asymmetric `index(after:) × _minimumCapacity(forScale:)` pair fits this REJECT pattern: index-advance and capacity-from-scale are unrelated functions on the same Int domain.

## NEW per-template criteria addition (V1.22.D-specific)

The V1.22.D stride-style label veto is a structural suppression of the cycle-14-demoted Algo `endOfChunk(startingAt:) × startOfChunk(endingAt:)` triple. Pre-V1.22.D this triple was cycle-14/17-ACCEPT (correctness-positive on chunk-boundary domain). V1.22.D's calibration trade-off documents that **auto-emit usability** is the suppression target, not correctness — the chunk-boundary generator complexity exceeds the standard `Gen<Int>` template. Cycle-20 doesn't sample the V1.22.D-suppressed picks (they're filtered from `--include-possible`); the trade-off is logged here for trajectory analysis at cycle-21+.

## Evidence sources

Per-decision rationale should cite at least one of:
- The function signature
- The file path + line number
- Curated rubric reasoning
- Public documentation snippets
- Commit history
- Type-shape patterns
- For lifted-suggestion picks: the underlying `mutating func`'s semantic class

## Decision JSON schema

Decisions are committed to `docs/calibration-cycle-20-data/triage-decisions.json`. Schema mirrors cycle-17's verbatim:

```json
{
  "version": "cycle-20",
  "raters": ["Claude/single-runner"],
  "captured_at": "2026-05-10",
  "swift_infer_commit": "b7c9477",
  "swift_infer_tag": "v1.22.0",
  "rubric_path": "docs/cycle-20-triage-rubric.md",
  "manifest_path": "docs/calibration-cycle-20-data/sample-manifest.md",
  "notes_path": "docs/calibration-cycle-20-data/triage-notes.md",
  "single_runner_caveat": "Single rater (Claude). Public API + commit history evidence only.",
  "decisions": [
    {
      "id": 1,
      "template": "round-trip" | "idempotence" | "commutativity" | "associativity" | "inverse-pair" | "monotonicity" | "identity-element" | "dual-style-consistency" | "composition",
      "lifted": true | false,
      "corpus": "OC" | "CM" | "Algo" | "PLK",
      "decision": "reject" | "accept" | "unknown",
      "site": "Sources/<path>:<line>[/<line>]",
      "summary": "<short rubric-citation rationale>"
    }
  ]
}
```

## Acceptance-rate computation

Per-template (and per-corpus) rates:

```
acceptance_rate(t) = accept_count(t) / (accept_count(t) + reject_count(t))
uncertainty_rate(t) = unknown_count(t) / total_count(t)
```

Cycle-20 reports:

- **Aggregate acceptance rate** vs cycle-6 (26.7%) + cycle-14 (34.8%) + cycle-17 (52.3%).
- **Per-template rate** for each cycle-17-baseline template (10 templates).
- **First per-template rate** for the cycle-19 finding asymmetric-pair class (within the round-trip 8 picks).
- **First per-template rate for OC sort/shuffle/reverse idempotence-lifted sub-class** (within the 6 idempotence-lifted picks).
- **Rate-stability check on V1.21.B composition-lifted demotion** (the 1 composition-lifted pick is the same `BucketIterator.advance(until:)` cycle-17 reject; cycle-20 verdict expected to match cycle-17 for the same underlying mathematical relation).

Single-runner triage produces *one* rater's view; cross-rater agreement is its own quality metric (deferred to multi-rater cycle).

## Cycle-20 vs cycle-17 vs cycle-14 vs cycle-6 methodology delta

| Aspect | Cycle 6 (v1.9) | Cycle 14 (v1.17) | Cycle 17 (v1.20) | Cycle 20 (v1.23) |
|---|---|---|---|---|
| Surface measured | post-V1.8.1 349-surface | post-V1.16.1 229-surface | post-V1.19.0 335-surface | post-V1.22.0 152-surface |
| Sample size | 50 | 50 | 46 | **50** (+4 vs cycle-17 redistributed to round-trip + idempotence-lifted) |
| Stratification | per-template + per-corpus | per-template + per-corpus | new-class-weighted | v1.22-rebased (round-trip 8 + idempotence-lifted 6 covers new classes) |
| Rater | Claude/single-runner | Claude/single-runner | Claude/single-runner | Claude/single-runner |
| Tier mix | Possible + 1 Likely | Possible + 1 Likely | Possible + 2 Likely | Possible + 2 Likely (identity-element + composition-lifted carry-forwards) |
| Picks reuse | n/a | fresh | fresh | fresh |
| Per-template criteria — 10 existing | this rubric | verbatim | verbatim | **verbatim** carry-forward |
| Per-template criteria — new classes | n/a | n/a | dual-style + lifted | (none — same 10 classes as cycle 17) |
| Post-cycle-N mechanism context | n/a | post-cycle-6 (cycles 7-13) | post-cycle-14 (cycles 15+16) | **post-cycle-17 (cycles 18+19)** |

The methodology delta is intentionally minimal **on the 10 template classes** so that per-template rate-shifts between cycles 17 and 20 are attributable to the cycle-18 + cycle-19 mechanism work, not to triage methodology drift.
