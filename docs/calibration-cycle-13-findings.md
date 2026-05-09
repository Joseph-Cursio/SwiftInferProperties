# Calibration Cycle 13 Findings — v1.16 (post-v1.15)

**Cycle 13 = v1.16.** Thirteenth execution of PRD §17.3's empirical-tuning loop. **Sixth data-driven cycle** (after cycles 7-9 + 11-12; cycle 10 was the v1.13 hoist refactor with no measurement). v1.16 closes post-v1.15 priority #1 (SetAlgebra-shape veto extension to round-trip + idempotence) and is **the cycle that crosses the 80% cumulative-reduction milestone** (1167 → 229 = −80.38%, with 4-candidate margin from the 233 threshold).

Captured: 2026-05-09. swift-infer at `6f32cde` (V1.16.1 — SetAlgebra-shape veto extension to round-trip + idempotence).

## Headline

**Aggregate 235 → 229 (−6, −2.55%) — fourth consecutive plan-vs-actual exact match.**

Per-corpus delta:
- swift-collections / OrderedCollections: 49 → 43 (**−6**)
- swift-numerics / ComplexModule: 166 → 166 (0; byte-identical)
- swift-algorithms / Algorithms: 13 → 13 (0; byte-identical)
- SwiftPropertyLaws / PropertyLawKit: 7 → 7 (0; byte-identical)

Per-template suppression (all on OC):
- **OC round-trip 3 → 1 (−2)** — both-sides SetAlgebra-shape pairs.
- **OC idempotence 6 → 2 (−4)** — single-function SetAlgebra-shape ops.

Cumulative across cycles 1-13: **1167 → 229 (−80.38%)** — **first cycle to cross 80%** with 4-candidate margin from the 233 threshold (1167 × 0.20 = 233.4 → ≤ 233 needed; landed at 229). Closes the V1.15.0 plan's 80% near-miss (overoptimistic by 0.14pp) cleanly.

## Cycle-13 mechanism class: function-name + type-shape composite (three-template family completion)

V1.16.1 extends V1.14.1's mechanism from inverse-pair to two more templates: round-trip + idempotence both consume `SwiftInferCore.SetAlgebraShape.binaryOps` + the V1.16.1-hoisted `SetAlgebraShape.isSelfTypedBinaryOp(_:)` helper. Both new helpers emit `-25` weight on the existing `Signal.Kind.protocolCoveredProperty` case (uniform with V1.14.1).

**Mechanism class continuity, not new.** The cycle-13 mechanism class is **not new** — it's the same function-name + type-shape composite class introduced in cycle 11 (V1.14.1). v1.16 extends the mechanism within its existing class, paralleling the cycles 7-9 direction-label counter family (which deployed across three templates over three releases) but applied to the function-name + type-shape composite class instead. The mechanism-class taxonomy stays at **8 distinct shapes** (no new class for cycle 13).

**Why all three templates fire on the same gate.** The structural argument "any function drawn from `{union, intersection, symmetricDifference, subtracting}` on `Self`-typed shape is a SetAlgebra partial-application surface" applies uniformly:
- **Inverse-pair** (V1.14.1, cycle 11): pair-based; `intersection ↔ subtracting` isn't an inverse.
- **Round-trip** (V1.16.1, cycle 13): pair-based; same shape isn't a forward+reverse round-trip either.
- **Idempotence** (V1.16.1, cycle 13): single-function; `intersection(_:)` viewed as `(T) -> T` is a partial application `(other) -> result`, not a self-mappable transformation.

**Three-template family completion in two releases.** Cycles 7-9 deployed direction-label counter across three releases (one per template); v1.14 + v1.16 deploy SetAlgebra-shape across two releases (cycle 11 introduced inverse-pair, cycle 13 added round-trip + idempetence in one commit). The two-release cadence beats the three-release cadence because V1.16.1 ships the round-trip + idempotence integration in a single commit — paralleling V1.15.1's three-template compression pattern but applied to two templates.

**Second-consumer-triggers-hoist pattern in action.** V1.14.1's private `isSelfTypedBinaryOp(_:)` helper crossed the second-consumer threshold when V1.16.1 wired round-trip + idempotence consumers — the hoist trigger v1.13's `DirectionLabels` move established. The helper now lives at `SwiftInferCore.SetAlgebraShape.isSelfTypedBinaryOp(_:)` as a `public static func` alongside `binaryOps`. All three template gate files consume it.

## Corpus selection

Same four cycle-1..12 corpora at the V1.16.1 commit. No new corpora added; the priority is depth on existing corpora (V1.16.1 targets a specific OC SetAlgebra noise pattern that V1.14.1 deliberately scoped to inverse-pair only).

## What v1.16 ships (the mechanism)

| File | Role |
|---|---|
| `Sources/SwiftInferCore/SetAlgebraShape.swift` | Hoisted `public static func isSelfTypedBinaryOp(_:)` lives alongside `binaryOps`. Mirrors V1.13.1's `DirectionLabels` hoist pattern. |
| `Sources/SwiftInferTemplates/RoundTripSetAlgebraShapeGate.swift` | Both-sides detection (paralleling V1.14.1's inverse-pair shape). Weight `-25`. |
| `Sources/SwiftInferTemplates/IdempotenceSetAlgebraShapeGate.swift` | Single-function detection. Weight `-25`. |
| `Sources/SwiftInferTemplates/InversePairSetAlgebraShapeGate.swift` (modified) | Updated to call the hoisted helper; private inline helper removed. |

**Score arithmetic.** Uniform `-25` weight across all three templates per V1.16.0 plan open decision #1:
- Round-trip / idempotence (baseline `+30`): bare → `+5` Suppressed (clean from `+20`); curated verb `+40` → `+45` Likely (preserved).
- Inverse-pair (baseline `+25`, V1.14.1 unchanged): bare → `0` Suppressed.

## Per-corpus suppression breakdown

### swift-collections / OrderedCollections

| Template | Cycle-12 | Cycle-13 | Δ |
|---|---:|---:|---:|
| **round-trip** | **3** | **1** | **−2** |
| **idempotence** | **6** | **2** | **−4** |
| inverse-pair | 0 | 0 | 0 |
| associativity | 10 | 10 | 0 |
| commutativity | 10 | 10 | 0 |
| monotonicity | 20 | 20 | 0 |

**6 of 6 V1.16.1-targeted candidates suppressed; 0 false positives.** All round-trip suppressions are `intersection ↔ subtracting` Self-typed pairs across `OrderedSet+Partial SetAlgebra` extensions × `OrderedSet+UnorderedView`. All idempotence suppressions are `intersection(_:)` and `subtracting(_:)` (Self -> Self) viewed as single-function candidates.

**1 round-trip survivor preserved by design:** `_value(forBucketContents:) ↔ _bucketContents(for:)` — non-Self typing makes V1.16.1's gate also nil; asymmetric domain-marker labeling makes V1.15.1's domain-marker gate also nil. Likely true-positive round-trip pair (bucket-contents encoding/decoding).

**2 idempotence survivors preserved:** `_description(type:)` (String) -> String and `firstOccupiedBucketInChain(with:)` (Bucket) -> Bucket — neither has a domain-marker label nor a SetAlgebra-shape function name; carrier `Bucket` ≠ `Self`.

### swift-algorithms / Algorithms

| Template | Cycle-12 | Cycle-13 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 13 | 13 | 0 |

Algorithms has zero SetAlgebra-shape candidates on V1.16.1's two target templates. Byte-identical to cycle-12 (`diff` returns empty). The 1 `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor uses stride-style anchors; cycle-14 priority #1 (stride-style label extension) closes this.

### swift-numerics / ComplexModule

| Template | Cycle-12 | Cycle-13 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 166 | 166 | 0 |

ComplexModule's binary ops are typed `(Complex, Complex) -> Complex` (free-function shape), not Self-typed protocol-extension shape. Byte-identical to cycle-12.

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-12 | Cycle-13 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 7 | 7 | 0 |

PLK has no SetAlgebra-shape candidates. Byte-identical to cycle-12.

## Cycle-12 priority-#1 candidate-set verification

The cycle-12 findings' priority-#1 candidate set (6 OC SetAlgebra survivors at v1.15) is now fully accounted for at v1.16:

| Candidate class | Cycle-12 count | Cycle-13 outcome | Mechanism |
|---|---:|---|---|
| OC round-trip with SetAlgebra shape | 2 | **all suppressed** | V1.16.1 round-trip gate |
| OC idempotence with SetAlgebra shape | 4 | **all suppressed** | V1.16.1 idempotence gate |

**6 of 6 V1.16.1-targeted candidates suppressed; 0 false positives.**

### Cycle-12 findings table correction

The cycle-12 findings doc's "Per-corpus suppression breakdown" table erroneously listed `OC idempotence with SetAlgebra shape | 2` — the narrative text correctly said "4 SetAlgebra `intersection`/`subtracting` (Self -> Self) idempotence claims". V1.16.3 amends the cycle-12 findings table to read `4` for consistency. Documented in the v1.16 plan + CHANGELOG as a calibration-data-quality note.

## Trajectory across all 13 cycles

| Cycle | Mechanism | Surface | Δ from prior | Cumulative Δ |
|---|---|---:|---:|---:|
| 1 (pre-tune) | none | 1167 | — | — |
| 1 (post-tune V1.4.3) | FP-storage + cross-type counter-signals | 358 | −809 | −69.32% |
| 2 (V1.5.2) | textual-only protocol-coverage suppression | 353 | −5 | −69.75% |
| 3 (V1.6.1) | identity-element pair-formation skip-list | 350 | −3 | −70.01% |
| 4 (V1.7.1) | stdlib-conformance bake-in | 326 | −24 | −72.06% |
| 5 (V1.8.1) | shape-gated Codable veto on round-trip | 349 | +23 | −70.10% |
| 6 (empirical-only) | (no surface change; baseline measured) | 349 | 0 | −70.10% |
| 7 (V1.10.1) | idempotence direction-label counter | 296 | −53 | −74.64% |
| 8 (V1.11.1) | inverse-pair direction-label counter | 288 | −8 | −75.32% |
| 9 (V1.12.1) | round-trip direction-label counter | 257 | −31 | −77.98% |
| 10 (V1.13.1) | hoist refactor (no surface change) | 257 | 0 | −77.98% |
| 11 (V1.14.1) | SetAlgebra-shape veto on inverse-pair | 251 | −6 | −78.49% |
| 12 (V1.15.1) | domain-marker counter on three templates | 235 | −16 | −79.86% |
| **13 (V1.16.1)** | **SetAlgebra-shape veto on round-trip + idempotence** | **229** | **−6** | **−80.38%** |

**−80.38% cumulative reduction across 13 cycles** (12 mechanism + 1 refactor). The V1.15.0 plan's near-miss on 80% (235 vs 233 needed = 1-candidate miss) closes at v1.16 with a 4-candidate margin (229 vs 233 needed).

## What v1.16 demonstrates

**Cycle-13 crosses 80%.** The first cycle below 233; cumulative trajectory across 13 cycles drops the surface by more than four-fifths of its pre-tune size. The narrative beat lands cleanly: the v1.15 plan's "would cross" projection was off by 1 candidate; v1.16 lands the crossing with 4-candidate margin.

**Three-template family completion within an existing mechanism class.** The function-name + type-shape composite class (introduced V1.14.1) now spans all three templates that surface SetAlgebra-shape false positives — paralleling the parameter-label direction-label sub-class (cycles 7-9) and the parameter-label semantic-intent sub-class (cycle 12). Mechanism-class taxonomy stays at 8 classes; the family-completion pattern is what cycle 13 ships.

**Fourth consecutive plan-vs-actual exact match.** The cycle-8 methodology fix (per-suggestion `^Template:` line counts via Python regex) now has four consecutive measurement cycles (v1.12 → v1.14 → v1.15 → v1.16) of point-for-point projection accuracy across all four corpora. Three was "consecutive"; four is a streak that demonstrates methodology stability across both calibration sub-classes (parameter-label cycles 9-12 and function-name + type-shape cycles 11+13).

**Two-release three-template family beats three-release cadence.** Cycles 7-9 (direction-label) shipped three templates in three releases; v1.14 + v1.16 (SetAlgebra-shape) shipped three templates in two releases. The compression came from V1.16.1 wiring round-trip + idempotence in one commit — uniform mechanism + already-canonicalized curated set + already-tested gate-shape (V1.14.1 inverse-pair) made the two new template integrations near-mechanical.

**Second-consumer-triggers-hoist pattern is now a verified workflow.** V1.13.1 introduced the pattern (`DirectionLabels` hoisted when round-trip became third consumer). V1.16.1 applied it in advance of need (`isSelfTypedBinaryOp` hoisted when round-trip + idempotence became second + third consumers). The pattern is now a calibration-engineering invariant: shared template-agnostic helpers live in `SwiftInferCore.<Namespace>.<helper>` from cycle N where N is the second-consumer cycle.

## Plan-vs-actual

The V1.16.0 plan f-bullet predicted:
> Algorithms: 13 → 13 (0; byte-identical)
> OrderedCollections round-trip: 3 → 1 (−2)
> OrderedCollections idempotence: 6 → 2 (−4)
> ComplexModule: 166 → 166 (0; byte-identical)
> PropertyLawKit: 7 → 7 (0; byte-identical)
> Aggregate 235 → 229 (−6, −2.55%)

**Actual outcome:**
- Algo: 13 → 13 (0). ✓
- OC round-trip: 3 → 1 (−2). ✓ **Exact.**
- OC idempotence: 6 → 2 (−4). ✓ **Exact.**
- ComplexModule: 166 → 166 (0). ✓
- PropertyLawKit: 7 → 7 (0). ✓
- Aggregate: 235 → 229 (−6, −2.55%). ✓ **Exact.**

**Fourth consecutive cycle in the loop's history with point-for-point projection match across all four corpora** (after v1.12 → v1.14 → v1.15 → v1.16, with v1.13 being a no-measurement refactor cycle).

**80% milestone landed cleanly.** The V1.16.0 plan projected 1167 → 229 = −80.4% with margin 4 from the 233 threshold; actual landed at exactly 229 with margin 4. No overoptimism; the plan-time projection used `floor(N × 0.20) = 233` as the threshold floor, matching the v1.15 methodology lesson.

## Methodology gaps observed

**No new methodology gaps. One inherited gap closed.**

**Cycle-12 findings table correction.** The cycle-12 findings doc's table mis-stated the OC idempotence SetAlgebra-shape count as 2 (the narrative text correctly said 4). v1.16 amends the table at V1.16.3 alongside this writeup. **Calibration-data-quality lesson:** when the findings doc has both a narrative text and a summary table referencing the same count, the table should be derived programmatically from the narrative or vice versa to prevent drift. Recorded as a future improvement; cycle-14+ findings docs may add a build-time check or template that enforces table-narrative consistency.

**Inherited gaps carry forward unchanged:**
- Possible-tier acceptance rate not re-measured at v1.10 / v1.11 / v1.12 / v1.14 / v1.15 / v1.16. The cycle-6 0/5 inverse-pair rate is now stale (rejected pool empty post-v1.14); the cycle-6 idempotence + round-trip pools have all rejection picks suppressed at v1.16. **Re-sampling now overdue across six mechanism cycles.** Cycle-14 priority #2.
- `surfacedAt` plumbing still pending (cycle-1 priority #4 territory).
- Multi-rater triage still pending (cycle-6 follow-up territory).

## Cycle-14 priority list (rotated post-v1.16)

The cycle-14 priority list rotates to drop the shipped SetAlgebra-shape extension. Post-v1.16 ordering:

1. **Stride-style label extension** — *(was post-v1.15 priority #2; PROMOTED to post-v1.16 priority #1.)* Add `startingAt`, `endingAt`, `from`, `until`, `offset` to a new `SwiftInferCore.StrideAnchorLabels.curated` set. Closes the 1 Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor on round-trip + inverse-pair simultaneously. Mechanism class: parameter-label counter (extends the cycles 7-9 + cycle-12 family with a third sub-class). ~1 hour to half a day.

2. **Possible-tier re-sampling on the post-v1.16 surface (229 across 4 corpora)** — *(was post-v1.15 priority #3; PROMOTED to post-v1.16 priority #2.)* Re-running the cycle-6 rubric on a fresh 50-decision sample at v1.16 should produce a measurably higher acceptance rate (cycle-7+8+9+11+12+13 combined noise-floor reductions: 349 → 229 = −34.4% across six mechanism cycles). **Now overdue across six mechanism cycles.** ~half a day.

3. **Reference-type carrier counter-signal** — *(was post-v1.15 priority #4; carried forward.)* `Signal.Kind.referenceTypeCarrier` counter on idempotence + round-trip + inverse-pair when carrier resolves to `kind == .class` or `kind == .actor`. Empirical effect projected small on cycle-1..13 corpora (struct+enum dominant). ~1 day.

4. **FP approximate-equality template arm** — *(carried forward from cycles 2-9.)* Real `KitFloatingPointTemplate`. ~1 day.

5. **Math-library op-name gate extension** — *(carried forward from cycle-4.)* Add `rescaledDivide` / `_relaxedAdd` / `_relaxedMul` to V1.6.1's stdlib operator gate. ~1 hour.

6. **`surfacedAt` plumbing** — *(carried forward from cycle-1 priority #4.)* ~half a day.

7. **Multi-rater triage methodology** — *(carried forward from cycle-6.)* ~1 day if a second rater is available.

8. **Codec set broadening + SuggestionIdentity continuity fixture** — *(carried forward.)*

9. **SemanticIndex** — *(carried forward; multi-cycle effort.)*

## Summary

Cycle 13 shipped one structural change: the SetAlgebra-shape veto extension to round-trip + idempotence (V1.16.1) — completes the function-name + type-shape composite three-template family that V1.14.1 introduced on inverse-pair. Hoists `isSelfTypedBinaryOp(_:)` from V1.14.1's private helper to `SwiftInferCore.SetAlgebraShape` (second-consumer-triggers-hoist pattern from v1.13).

The empirical effect was −6 of 235 surfaced suggestions (−2.55% aggregate) — same magnitude as cycle 11's −6 (also a SetAlgebra-shape mechanism, on inverse-pair). All −6 suppressions are on the OC corpus; other three corpora byte-identical to cycle-12.

The cycle-12 priority-#1 candidate set is fully accounted for: 6 of 6 V1.16.1-targeted candidates suppressed; 0 false positives. The 3 deliberately-preserved survivors (1 asymmetric `_value/_bucketContents` round-trip + 2 non-domain non-SetAlgebra idempotence) remain surfaced.

Plan-vs-actual was a point-for-point exact match across all four corpora **for the fourth consecutive measurement cycle** (v1.12 → v1.14 → v1.15 → v1.16). The 80% cumulative-reduction milestone landed cleanly at 1167 → 229 (−80.38%) with 4-candidate margin from the 233 threshold — closing the V1.15.0 plan's 1-candidate near-miss with margin to spare.

Cumulative trajectory across cycles 1–13: **1167 → 229 (−80.38%)** with 13 calibration cycles (12 mechanism + 1 refactor) and **8 distinct mechanism classes** (taxonomy unchanged from cycle 12; cycle-13 extension within the existing function-name + type-shape composite class). Cycle-14's priority list rotates to promote the stride-style label extension to priority #1 — closes the lone Algo survivor on round-trip + inverse-pair simultaneously.
