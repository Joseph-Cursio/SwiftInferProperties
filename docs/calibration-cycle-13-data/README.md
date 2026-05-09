# v1.16 Calibration Cycle 13 — Empirical Data

Captured: 2026-05-09. swift-infer at `6f32cde` (V1.16.1 — SetAlgebra-shape veto extension to round-trip + idempotence). Re-runs the cycle-1+...+12 corpora with V1.16.1's two-template extension active.

Cycle 13's diff target is the **cycle-12 post-domain-marker-counter baseline** (the 235-surface). Cycle-13's delta attributes 100% to V1.16.1.

## Attribution note — only V1.16.1 between cycle-12 and cycle-13

Cycle-12 capture was at the V1.15.1 commit; cycle-13 capture is at the V1.16.1 commit. v1.16 ships exactly one structural change: V1.16.1's `setAlgebraShapeVeto(for:)` extension methods on `RoundTripTemplate` (both-sides detection) and `IdempotenceTemplate` (single-function detection). Both reuse the existing `Signal.Kind.protocolCoveredProperty` case (V1.14.1's reuse posture) and emit `-25` weight (uniform with V1.14.1's inverse-pair calibration). Both consume the V1.16.1-hoisted `SwiftInferCore.SetAlgebraShape.isSelfTypedBinaryOp(_:)` helper (lifted from V1.14.1's private helper when round-trip + idempotence became consumers — second-consumer-triggers-hoist pattern from v1.13). Cycle-13's delta attributes 100% to V1.16.1.

## Corpora

Same four cycle-1..12 targets:

| Corpus | Target | Cycle-12 baseline | Cycle-13 post-extension snapshot |
|---|---|---|---|
| swift-collections | OrderedCollections | [`../calibration-cycle-12-data/post-domain-marker-counter-swift-collections-OrderedCollections.discover.txt`](../calibration-cycle-12-data/post-domain-marker-counter-swift-collections-OrderedCollections.discover.txt) | [`post-setalgebra-extension-swift-collections-OrderedCollections.discover.txt`](post-setalgebra-extension-swift-collections-OrderedCollections.discover.txt) |
| swift-numerics | ComplexModule | [`../calibration-cycle-12-data/post-domain-marker-counter-swift-numerics-ComplexModule.discover.txt`](../calibration-cycle-12-data/post-domain-marker-counter-swift-numerics-ComplexModule.discover.txt) | [`post-setalgebra-extension-swift-numerics-ComplexModule.discover.txt`](post-setalgebra-extension-swift-numerics-ComplexModule.discover.txt) |
| swift-algorithms | Algorithms | [`../calibration-cycle-12-data/post-domain-marker-counter-swift-algorithms-Algorithms.discover.txt`](../calibration-cycle-12-data/post-domain-marker-counter-swift-algorithms-Algorithms.discover.txt) | [`post-setalgebra-extension-swift-algorithms-Algorithms.discover.txt`](post-setalgebra-extension-swift-algorithms-Algorithms.discover.txt) |
| SwiftPropertyLaws | PropertyLawKit | [`../calibration-cycle-12-data/post-domain-marker-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt`](../calibration-cycle-12-data/post-domain-marker-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt) | [`post-setalgebra-extension-SwiftPropertyLaws-PropertyLawKit.discover.txt`](post-setalgebra-extension-SwiftPropertyLaws-PropertyLawKit.discover.txt) |

## Aggregate suppression delta

| Corpus | Cycle-12 total | Cycle-13 total | Δ |
|---|---:|---:|---:|
| swift-numerics / ComplexModule | 166 | 166 | 0 |
| swift-collections / OrderedCollections | 49 | 43 | **−6** |
| swift-algorithms / Algorithms | 13 | 13 | 0 |
| SwiftPropertyLaws / PropertyLawKit | 7 | 7 | 0 |
| **Total** | **235** | **229** | **−6 (−2.55%)** |

Cumulative across cycles 1–13: total surface 1167 → 229 = **−80.38%** — **first cycle to cross 80%** with 4-candidate margin from the threshold (1167 × 0.20 = 233.4 → ≤ 233 needed; landed at 229).

**Plan vs actual: EXACT MATCH (fourth consecutive measurement cycle).** V1.16.0 projection: −6 aggregate (OC round-trip −2 both-sides, OC idempotence −4 single-function, others 0). Actual: −6 aggregate (OC round-trip −2, OC idempotence −4, others 0). Trajectory: v1.12 → v1.14 → v1.15 → v1.16 = **four-for-four** point-for-point exact matches.

## Per-template breakdown

All −6 suppressions are on the OC round-trip + idempotence templates. Other corpora byte-identical to cycle-12; verified via `diff` returning empty against ComplexModule + Algorithms + PropertyLawKit baselines.

### swift-collections / OrderedCollections

| Template | Cycle-12 | Cycle-13 | Δ |
|---|---:|---:|---:|
| **round-trip** | **3** | **1** | **−2** |
| **idempotence** | **6** | **2** | **−4** |
| inverse-pair | 0 | 0 | 0 |
| associativity | 10 | 10 | 0 |
| commutativity | 10 | 10 | 0 |
| monotonicity | 20 | 20 | 0 |

#### Round-trip suppressions (2)

Both fit V1.16.1's both-sides gate: both pair sides have `(Self) -> Self` shape AND both names in `SetAlgebraShape.binaryOps`.

| # | Forward | Reverse |
|---|---|---|
| 1 | `intersection(_:)` (OS Partial SetAlgebra intersection.swift) | `subtracting(_:)` (OS Partial SetAlgebra subtracting.swift) |
| 2 | `intersection(_:)` (UnorderedView) | `subtracting(_:)` (UnorderedView) |

#### Round-trip survivor (1) — preserved by design

| Forward | Reverse | Why preserved |
|---|---|---|
| `_value(forBucketContents:)` (UInt64) -> Int? | `_bucketContents(for:)` (Int?) -> UInt64 | Asymmetric domain-marker labeling per V1.15.0 plan open decision #2; non-Self typing makes V1.16.1's gate also nil. Likely true-positive round-trip (encoding/decoding bucket contents). |

#### Idempotence suppressions (4)

All 4 fit V1.16.1's single-function gate.

| # | Function |
|---|---|
| 1 | `intersection(_:)` (Self) -> Self  (OS Partial SetAlgebra intersection.swift) |
| 2 | `subtracting(_:)` (Self) -> Self  (OS Partial SetAlgebra subtracting.swift) |
| 3 | `intersection(_:)` (Self) -> Self  (OS UnorderedView.swift:416) |
| 4 | `subtracting(_:)` (Self) -> Self  (OS UnorderedView.swift:583) |

#### Idempotence survivors (2) — non-domain non-SetAlgebra labels

| # | Function | Why preserved |
|---|---|---|
| 1 | `_description(type:)` (String) -> String | `type:` not in domain-marker set; non-SetAlgebra name. |
| 2 | `firstOccupiedBucketInChain(with:)` (Bucket) -> Bucket | `with:` not in domain-marker set; non-SetAlgebra name; carrier `Bucket` not `Self`. |

### swift-algorithms / Algorithms

| Template | Cycle-12 | Cycle-13 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 13 | 13 | 0 |

Algorithms has zero SetAlgebra-shape candidates on V1.16.1's two target templates (its inverse-pair / round-trip / idempotence candidates use `(Index) -> Index` and stride-style labels, not Self-typed binary ops). Byte-identical to cycle-12.

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

The cycle-12 findings' priority-#1 candidate set (the 6 OC SetAlgebra survivors at v1.15) is now fully accounted for at v1.16:

| Candidate class | Cycle-12 count | Cycle-13 outcome | Mechanism |
|---|---:|---|---|
| OC round-trip with SetAlgebra shape | 2 | **all suppressed** | V1.16.1 round-trip gate |
| OC idempotence with SetAlgebra shape | 4 | **all suppressed** | V1.16.1 idempotence gate |

**6 of 6 V1.16.1-targeted candidates suppressed; 0 false positives.** The cycle-12 findings table erroneously listed "2" for OC idempotence with SetAlgebra shape (the narrative text correctly said "4"); V1.16.3 amends the cycle-12 findings table alongside the cycle-13 writeup.

## 80% milestone — cumulative crossing

| Snapshot | Surface | Cumulative Δ |
|---|---:|---:|
| Cycle 1 (pre-tune) | 1167 | — |
| Cycle 11 (v1.14) | 251 | −78.49% |
| Cycle 12 (v1.15) | 235 | −79.86% (near-miss on 80%, overoptimistic by 0.14pp per V1.15.0) |
| **Cycle 13 (v1.16)** | **229** | **−80.38%** (crosses 80% with 4-candidate margin) |

The 80% threshold floor is `floor(1167 × 0.20) + 1 = 234` (need surface ≤ 233); landed at 229, 4 candidates below.

## Reproducibility — capture commands

```sh
cd /Users/joecursio/xcode_projects/SwiftInferProperties
# Debug binary at .build/debug/swift-infer (rebuilt by `swift test`).
INFER=/Users/joecursio/xcode_projects/SwiftInferProperties/.build/debug/swift-infer
OUT=/Users/joecursio/xcode_projects/SwiftInferProperties/docs/calibration-cycle-13-data

# swift-numerics / ComplexModule
(cd /Users/joecursio/calibration/swift-numerics && \
  $INFER discover --target ComplexModule --include-possible) \
  > "$OUT/post-setalgebra-extension-swift-numerics-ComplexModule.discover.txt"

# swift-collections / OrderedCollections
(cd /Users/joecursio/xcode_projects/swift-collections && \
  $INFER discover --target OrderedCollections --include-possible) \
  > "$OUT/post-setalgebra-extension-swift-collections-OrderedCollections.discover.txt"

# swift-algorithms / Algorithms
(cd /Users/joecursio/calibration/swift-algorithms && \
  $INFER discover --target Algorithms --include-possible) \
  > "$OUT/post-setalgebra-extension-swift-algorithms-Algorithms.discover.txt"

# SwiftPropertyLaws / PropertyLawKit
(cd /Users/joecursio/xcode_projects/SwiftPropertyLaws && \
  $INFER discover --target PropertyLawKit --include-possible) \
  > "$OUT/post-setalgebra-extension-SwiftPropertyLaws-PropertyLawKit.discover.txt"
```

## Handoff to V1.16.3 (cycle-13 findings writeup)

V1.16.3 reads this data + the cycle-13 surface and writes `docs/calibration-cycle-13-findings.md` documenting:

1. The **−6 / −2.55% headline** + **first cycle to cross 80% cumulative reduction** framing (margin: 4 candidates).
2. The **plan-vs-actual fourth consecutive exact match** (v1.12 → v1.14 → v1.15 → v1.16).
3. The **completion of the function-name + type-shape composite three-template family** — V1.14.1 introduced (inverse-pair), V1.16.1 extended (round-trip + idempotence in one commit).
4. The **second-consumer-triggers-hoist pattern in action** — V1.16.1 hoists `isSelfTypedBinaryOp` from V1.14.1's private helper to `SwiftInferCore.SetAlgebraShape` (mirrors v1.13's `DirectionLabels` hoist precedent).
5. The cumulative **1167 → 229 (−80.38%) trajectory** across 13 cycles (12 mechanism + 1 refactor) and **8 mechanism classes** (taxonomy unchanged from cycle 12; extension within an existing class).
6. **Cycle-12 findings table correction** — change `OC idempotence with SetAlgebra shape | 2` → `4`. Document as a calibration-data-quality note.
7. **Cycle-14 priority list** rotated post-v1.16:
   - **Stride-style label extension** — PROMOTED from post-v1.15 #2 to post-v1.16 #1.
   - **Possible-tier re-sampling on the post-v1.16 surface (229 across 4 corpora)** — PROMOTED to #2; now overdue across six mechanism cycles.
   - **Reference-type carrier counter-signal** — Carried forward.
   - **FP arm + math-lib op gate + surfacedAt + multi-rater + codec-set** — Carried forward.
