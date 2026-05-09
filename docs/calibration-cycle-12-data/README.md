# v1.15 Calibration Cycle 12 — Empirical Data

Captured: 2026-05-09. swift-infer at `eb92975` (V1.15.1 — domain-marker counter on idempotence + round-trip + inverse-pair). Re-runs the cycle-1+...+11 corpora with V1.15.1's three-template counter active.

Cycle 12's diff target is the **cycle-11 post-SetAlgebra-veto baseline** (the 251-surface). Cycle-12's delta attributes 100% to V1.15.1.

## Attribution note — only V1.15.1 between cycle-11 and cycle-12

Cycle-11 capture was at the V1.14.1 commit; cycle-12 capture is at the V1.15.1 commit. v1.15 ships exactly one structural rule deployed across three templates: V1.15.1's `domainMarkerCounterSignal(for:)` extension methods on `IdempotenceTemplate` (single-function detection), `RoundTripTemplate` (both-sides detection), and `InversePairTemplate` (both-sides detection, defensive scaffold — no current candidates). All three consume `SwiftInferCore.DomainMarkerLabels.curated = {forScale, forCapacity, forBucketContents}` and emit a `-15` weight signal on the existing `Signal.Kind.directionLabel` case. Cycle-12's delta attributes 100% to V1.15.1.

## Corpora

Same four cycle-1..11 targets:

| Corpus | Target | Cycle-11 baseline | Cycle-12 post-counter snapshot |
|---|---|---|---|
| swift-collections | OrderedCollections | [`../calibration-cycle-11-data/post-setalgebra-veto-swift-collections-OrderedCollections.discover.txt`](../calibration-cycle-11-data/post-setalgebra-veto-swift-collections-OrderedCollections.discover.txt) | [`post-domain-marker-counter-swift-collections-OrderedCollections.discover.txt`](post-domain-marker-counter-swift-collections-OrderedCollections.discover.txt) |
| swift-numerics | ComplexModule | [`../calibration-cycle-11-data/post-setalgebra-veto-swift-numerics-ComplexModule.discover.txt`](../calibration-cycle-11-data/post-setalgebra-veto-swift-numerics-ComplexModule.discover.txt) | [`post-domain-marker-counter-swift-numerics-ComplexModule.discover.txt`](post-domain-marker-counter-swift-numerics-ComplexModule.discover.txt) |
| swift-algorithms | Algorithms | [`../calibration-cycle-11-data/post-setalgebra-veto-swift-algorithms-Algorithms.discover.txt`](../calibration-cycle-11-data/post-setalgebra-veto-swift-algorithms-Algorithms.discover.txt) | [`post-domain-marker-counter-swift-algorithms-Algorithms.discover.txt`](post-domain-marker-counter-swift-algorithms-Algorithms.discover.txt) |
| SwiftPropertyLaws | PropertyLawKit | [`../calibration-cycle-11-data/post-setalgebra-veto-SwiftPropertyLaws-PropertyLawKit.discover.txt`](../calibration-cycle-11-data/post-setalgebra-veto-SwiftPropertyLaws-PropertyLawKit.discover.txt) | [`post-domain-marker-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt`](post-domain-marker-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt) |

## Aggregate suppression delta

| Corpus | Cycle-11 total | Cycle-12 total | Δ |
|---|---:|---:|---:|
| swift-numerics / ComplexModule | 166 | 166 | 0 |
| swift-collections / OrderedCollections | 65 | 49 | **−16** |
| swift-algorithms / Algorithms | 13 | 13 | 0 |
| SwiftPropertyLaws / PropertyLawKit | 7 | 7 | 0 |
| **Total** | **251** | **235** | **−16 (−6.4%)** |

Cumulative across cycles 1–12: total surface 1167 → 235 (**−79.86%**). Just shy of the V1.15.0 plan's 80% projection (overoptimistic by 0.14 percentage points; 1167 × 0.20 = 233.4 needed to cross). Largest single-cycle structural-rule delta since cycle 9 (v1.12, −31).

**Plan vs actual: EXACT MATCH (third consecutive measurement cycle).** V1.15.0 projection: −16 aggregate (OC round-trip −9 both-sides, OC idempotence −7, others 0). Actual: −16 aggregate (OC round-trip −9, OC idempotence −7, others 0). Trajectory after v1.12 → v1.14 → v1.15 (with v1.13 being a no-measurement refactor cycle in between): three-for-three.

## Per-template breakdown

All −16 suppressions are on the OC round-trip + idempotence templates. Other corpora byte-identical to cycle-11; verified via `diff` returning empty against ComplexModule + Algorithms + PropertyLawKit baselines.

### swift-collections / OrderedCollections

| Template | Cycle-11 | Cycle-12 | Δ |
|---|---:|---:|---:|
| **round-trip** | **12** | **3** | **−9** |
| **idempotence** | **13** | **6** | **−7** |
| inverse-pair | 0 | 0 | 0 |
| associativity | 10 | 10 | 0 |
| commutativity | 10 | 10 | 0 |
| monotonicity | 20 | 20 | 0 |

#### Round-trip suppressions (9)

All 9 fit V1.15.1's both-sides gate: both `pair.forward.parameters.first?.label` and `pair.reverse.parameters.first?.label` in `DomainMarkerLabels.curated`.

| # | Forward | Reverse |
|---|---|---|
| 1 | `minimumCapacity(forScale:)` | `maximumCapacity(forScale:)` |
| 2 | `minimumCapacity(forScale:)` | `scale(forCapacity:)` |
| 3 | `minimumCapacity(forScale:)` | `wordCount(forScale:)` |
| 4 | `maximumCapacity(forScale:)` | `scale(forCapacity:)` |
| 5 | `maximumCapacity(forScale:)` | `wordCount(forScale:)` |
| 6 | `scale(forCapacity:)` | `wordCount(forScale:)` |
| 7 | `_minimumCapacity(forScale:)` | `_maximumCapacity(forScale:)` |
| 8 | `_minimumCapacity(forScale:)` | `_scale(forCapacity:)` |
| 9 | `_maximumCapacity(forScale:)` | `_scale(forCapacity:)` |

#### Round-trip survivors (3) — by design

| # | Forward | Reverse | Why preserved |
|---|---|---|---|
| 1 | `_value(forBucketContents:)` (UInt64) -> Int? | `_bucketContents(for:)` (Int?) -> UInt64 | Asymmetric labeling per V1.15.0 plan open decision #2 (both-sides default). Likely true-positive round-trip (encoding/decoding bucket contents). |
| 2 | `intersection(_:)` (Self) -> Self | `subtracting(_:)` (Self) -> Self | V1.14.1 SetAlgebra-shape veto only fires on inverse-pair, not round-trip; out of scope per V1.15 plan. Cycle-13 priority #1 candidate. |
| 3 | `intersection(_:)` (Self) -> Self | `subtracting(_:)` (Self) -> Self | Same SetAlgebra-shape pattern, second cross-file pair. |

#### Idempotence suppressions (7)

All 7 fit V1.15.1's single-function gate: `summary.parameters.first?.label` in `DomainMarkerLabels.curated`.

| # | Function |
|---|---|
| 1 | `minimumCapacity(forScale:)` (Int) -> Int |
| 2 | `maximumCapacity(forScale:)` (Int) -> Int |
| 3 | `scale(forCapacity:)` (Int) -> Int |
| 4 | `wordCount(forScale:)` (Int) -> Int |
| 5 | `_minimumCapacity(forScale:)` (Int) -> Int |
| 6 | `_maximumCapacity(forScale:)` (Int) -> Int |
| 7 | `_scale(forCapacity:)` (Int) -> Int |

#### Idempotence survivors (6) — non-domain-marker labels

| # | Function | Why preserved |
|---|---|---|
| 1 | `_description(type:)` (String) -> String | `type:` not in domain-marker set. |
| 2 | `firstOccupiedBucketInChain(with:)` (Bucket) -> Bucket | `with:` not in domain-marker set. |
| 3-4 | `intersection(_:)` × 2, `subtracting(_:)` × 2 (Self -> Self) | `_:` (no label); idempotence variant of the SetAlgebra-shape pattern (cycle-13 candidate to extend V1.14.1 to idempotence). |

### swift-algorithms / Algorithms

| Template | Cycle-11 | Cycle-12 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 13 | 13 | 0 |

Algorithms has zero domain-marker-labeled candidates on any of the three V1.15.1-targeted templates. Byte-identical to cycle-11 (`diff` returns empty).

The 1 remaining Algo round-trip + inverse-pair `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor uses `startingAt` / `endingAt` — stride-style anchors, not domain markers; cycle-13 priority #2 (stride-style label extension) closes this.

### swift-numerics / ComplexModule

| Template | Cycle-11 | Cycle-12 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 166 | 166 | 0 |

ComplexModule's binary ops use `_:` (unlabeled) parameters per Swift API conventions for arithmetic operators. Byte-identical to cycle-11.

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-11 | Cycle-12 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 7 | 7 | 0 |

PLK has no domain-marker-labeled candidates. Byte-identical to cycle-11.

## Cycle-11 priority-#1 candidate-set verification

The cycle-11 findings' priority-#1 candidate set (12 OC round-trip + 7 OC idempotence ≈ 19 aggregate) is now fully accounted for:

| Candidate class | Cycle-11 count | Cycle-12 outcome | Mechanism |
|---|---:|---|---|
| OC round-trip with both-sides domain markers | 9 | **all suppressed** | V1.15.1 round-trip counter |
| OC round-trip with one-side domain marker | 1 | **preserved** (likely true-positive) | V1.15.0 open decision #2 default (both-sides) |
| OC round-trip with SetAlgebra shape | 2 | preserved (out of scope) | cycle-13 priority #1 |
| OC idempotence with domain markers | 7 | **all suppressed** | V1.15.1 idempotence counter |
| OC idempotence non-domain | 4 | preserved | (not targeted) |
| OC idempotence with SetAlgebra shape | 2 | preserved (out of scope) | cycle-13 priority #1 |

**16 of 16 V1.15.1-targeted candidates suppressed**; 3 of 3 deliberately-preserved candidates remain surfaced (1 asymmetric true-positive + 2 SetAlgebra round-trip pairs as future-cycle territory). The both-sides design choice from open decision #2 paid off — the asymmetric `_value(forBucketContents:) ↔ _bucketContents(for:)` candidate stays as a possible true-positive for human triage.

## Reproducibility — capture commands

```sh
cd /Users/joecursio/xcode_projects/SwiftInferProperties
# Debug binary at .build/debug/swift-infer (rebuilt by `swift test`).
INFER=/Users/joecursio/xcode_projects/SwiftInferProperties/.build/debug/swift-infer
OUT=/Users/joecursio/xcode_projects/SwiftInferProperties/docs/calibration-cycle-12-data

# swift-numerics / ComplexModule
(cd /Users/joecursio/calibration/swift-numerics && \
  $INFER discover --target ComplexModule --include-possible) \
  > "$OUT/post-domain-marker-counter-swift-numerics-ComplexModule.discover.txt"

# swift-collections / OrderedCollections
(cd /Users/joecursio/xcode_projects/swift-collections && \
  $INFER discover --target OrderedCollections --include-possible) \
  > "$OUT/post-domain-marker-counter-swift-collections-OrderedCollections.discover.txt"

# swift-algorithms / Algorithms
(cd /Users/joecursio/calibration/swift-algorithms && \
  $INFER discover --target Algorithms --include-possible) \
  > "$OUT/post-domain-marker-counter-swift-algorithms-Algorithms.discover.txt"

# SwiftPropertyLaws / PropertyLawKit
(cd /Users/joecursio/xcode_projects/SwiftPropertyLaws && \
  $INFER discover --target PropertyLawKit --include-possible) \
  > "$OUT/post-domain-marker-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt"
```

## Handoff to V1.15.3 (cycle-12 findings writeup)

V1.15.3 reads this data + the cycle-12 surface and writes `docs/calibration-cycle-12-findings.md` documenting:

1. The **−16 / −6.4% headline aggregate suppression**, point-for-point match with V1.15.0's projection.
2. The **first cycle to ship a single mechanism applied to three templates simultaneously** framing — compresses cycles 7-9's three-release direction-counter cadence into one.
3. The **plan-vs-actual third consecutive exact match** — v1.12 → v1.14 → v1.15 (with v1.13 a no-measurement refactor cycle).
4. The **near-miss on 80% cumulative reduction** (79.86% actual vs the V1.15.0 plan's 80% projection — overoptimistic by 0.14pp; cycle-13 will cross unambiguously).
5. The **both-sides design validation** — V1.15.0 open decision #2 default preserved 1 likely true-positive (`_value(forBucketContents:) ↔ _bucketContents(for:)`) at the cost of 0 aggregate (either-side variant would have hit −17 at 234, also not crossing 80%).
6. The cumulative **1167 → 235 (−79.86%) trajectory** across 12 calibration cycles (10 mechanism + 1 refactor + cycle-12 mechanism) and **eight distinct mechanism classes** (the new class: parameter-label counter — semantic-intent variant).
7. **Cycle-13 priority list** rotated post-v1.15:
   - **SetAlgebra-shape veto extension to round-trip + idempotence** — closes the 4 remaining OC SetAlgebra survivors (2 round-trip + 2 idempotence). PROMOTED to cycle-13 #1 (was post-v1.14 future work).
   - **Stride-style label extension** — closes the 1 Algo `endOfChunk(startingAt:)` survivor on round-trip + inverse-pair simultaneously. Carried forward.
   - **Possible-tier re-sampling on the post-v1.15 surface (235 across 4 corpora)** — measures cycle-7+8+9+11+12 cumulative rate-improvement (349 → 235 = −32.7% across five mechanism cycles). Carried forward.
   - **Reference-type carrier counter-signal** — Carried forward.
   - **FP arm + math-lib op gate + surfacedAt + multi-rater + codec-set** — Carried forward.
