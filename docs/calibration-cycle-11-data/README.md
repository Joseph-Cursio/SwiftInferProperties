# v1.14 Calibration Cycle 11 — Empirical Data

Captured: 2026-05-09. swift-infer at `27b615e` (V1.14.1 — SetAlgebra-shape veto on inverse-pair). Re-runs the cycle-1+...+9 corpora with V1.14.1's veto active.

Cycle 11's diff target is the **cycle-9 post-roundtrip-direction-counter baseline** (the 257-surface). Cycle-11's delta attributes 100% to V1.14.1.

## Attribution note — only V1.14.1 between cycle-9 and cycle-11

Cycle-9 capture was at the V1.12.1 commit; cycle-11 capture is at the V1.14.1 commit. v1.13's hoist refactor (cycle-10) was zero-behavior-change (verified byte-stable on Algorithms in V1.13.1); v1.14 ships exactly one structural rule: V1.14.1's `InversePairTemplate.setAlgebraShapeVeto(for:)` returning `-25` when both pair sides have `(Self) -> Self` shape AND both function names are in `SetAlgebraShape.binaryOps`. Cycle-11's delta attributes 100% to V1.14.1.

## Corpora

Same four cycle-1..9 targets:

| Corpus | Target | Cycle-9 baseline | Cycle-11 post-veto snapshot |
|---|---|---|---|
| swift-collections | OrderedCollections | [`../calibration-cycle-9-data/post-roundtrip-direction-counter-swift-collections-OrderedCollections.discover.txt`](../calibration-cycle-9-data/post-roundtrip-direction-counter-swift-collections-OrderedCollections.discover.txt) | [`post-setalgebra-veto-swift-collections-OrderedCollections.discover.txt`](post-setalgebra-veto-swift-collections-OrderedCollections.discover.txt) |
| swift-numerics | ComplexModule | [`../calibration-cycle-9-data/post-roundtrip-direction-counter-swift-numerics-ComplexModule.discover.txt`](../calibration-cycle-9-data/post-roundtrip-direction-counter-swift-numerics-ComplexModule.discover.txt) | [`post-setalgebra-veto-swift-numerics-ComplexModule.discover.txt`](post-setalgebra-veto-swift-numerics-ComplexModule.discover.txt) |
| swift-algorithms | Algorithms | [`../calibration-cycle-9-data/post-roundtrip-direction-counter-swift-algorithms-Algorithms.discover.txt`](../calibration-cycle-9-data/post-roundtrip-direction-counter-swift-algorithms-Algorithms.discover.txt) | [`post-setalgebra-veto-swift-algorithms-Algorithms.discover.txt`](post-setalgebra-veto-swift-algorithms-Algorithms.discover.txt) |
| SwiftPropertyLaws | PropertyLawKit | [`../calibration-cycle-9-data/post-roundtrip-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt`](../calibration-cycle-9-data/post-roundtrip-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt) | [`post-setalgebra-veto-SwiftPropertyLaws-PropertyLawKit.discover.txt`](post-setalgebra-veto-SwiftPropertyLaws-PropertyLawKit.discover.txt) |

## Aggregate suppression delta

| Corpus | Cycle-9 total | Cycle-11 total | Δ |
|---|---:|---:|---:|
| swift-numerics / ComplexModule | 166 | 166 | 0 |
| swift-collections / OrderedCollections | 71 | 65 | **−6** |
| swift-algorithms / Algorithms | 13 | 13 | 0 |
| SwiftPropertyLaws / PropertyLawKit | 7 | 7 | 0 |
| **Total** | **257** | **251** | **−6 (−2.3%)** |

Cumulative across cycles 1–11: total surface 1167 → 251 (**−78.5%**). Cycle-11's −6 is a precision-targeted suppression matching V1.14.0's −6 projection point-for-point.

**Plan vs actual: EXACT MATCH (second cycle in the loop's history).** V1.14.0 projection: −6 (Algo 0, OC −6, CM 0, PLK 0). Actual: −6 (Algo 0, OC −6, CM 0, PLK 0). Methodology fix from cycle-8's findings (per-suggestion `^Template:` line counts) continues to deliver projection accuracy, now confirmed across two consecutive cycles (v1.12 → v1.14).

## Per-template breakdown

All −6 suppressions are on the OC inverse-pair template. Other six templates byte-identical to cycle-9 across all four corpora.

### swift-collections / OrderedCollections

| Template | Cycle-9 | Cycle-11 | Δ |
|---|---:|---:|---:|
| **inverse-pair** | **6** | **0** | **−6** |
| associativity | 10 | 10 | 0 |
| commutativity | 10 | 10 | 0 |
| idempotence | 13 | 13 | 0 |
| monotonicity | 20 | 20 | 0 |
| round-trip | 12 | 12 | 0 |

**100% of OC inverse-pair surface eliminated** — first cycle to drop a template's per-corpus surface to zero. The 6 suppressed claims:

| # | Forward | Reverse |
|---|---|---|
| 1 | `intersection(_:)` (OS Partial SetAlgebra intersection.swift) | `subtracting(_:)` (OS Partial SetAlgebra subtracting.swift) |
| 2 | `intersection(_:)` (OS Partial SetAlgebra intersection.swift) | `intersection(_:)` (OS UnorderedView.swift) |
| 3 | `intersection(_:)` (OS Partial SetAlgebra intersection.swift) | `subtracting(_:)` (OS UnorderedView.swift) |
| 4 | `subtracting(_:)` (OS Partial SetAlgebra subtracting.swift) | `intersection(_:)` (OS UnorderedView.swift) |
| 5 | `subtracting(_:)` (OS Partial SetAlgebra subtracting.swift) | `subtracting(_:)` (OS UnorderedView.swift) |
| 6 | `intersection(_:)` (OS UnorderedView.swift) | `subtracting(_:)` (OS UnorderedView.swift) |

All 6 fit V1.14.1's two-condition gate: both pair sides have `(Self) -> Self` shape AND both names in `SetAlgebraShape.binaryOps = {union, intersection, symmetricDifference, subtracting}`.

### swift-algorithms / Algorithms

| Template | Cycle-9 | Cycle-11 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 13 | 13 | 0 |

The 1 surviving Algo inverse-pair (`endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)`) has labels `startingAt` / `endingAt` — neither in `DirectionLabels.curated` nor would they be in any SetAlgebra set. Stride-style label extension (post-v1.13 priority #3) will close this in v1.15+.

### swift-numerics / ComplexModule

| Template | Cycle-9 | Cycle-11 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 166 | 166 | 0 |

ComplexModule has zero `(Self) -> Self`-shape inverse-pair candidates (Complex's binary ops are `(Complex, Complex) -> Complex` shape; not the SetAlgebra protocol-extension Self shape). Byte-identical to cycle-9.

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-9 | Cycle-11 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 7 | 7 | 0 |

PLK has no inverse-pair candidates. Byte-identical to cycle-9.

## Cycle-6 picks coverage closes at v1.14

The cycle-6 single-runner triage's 5 inverse-pair rejections are now fully accounted for:

| # | Cycle-6 pick | Cycle-9 outcome | Cycle-11 outcome | Mechanism |
|---|---|---|---|---|
| 45 | OS `intersection ↔ subtracting` | still surfaces | **suppressed** | V1.14.1 SetAlgebra veto |
| 46 | OS (same pattern) | still surfaces | **suppressed** | V1.14.1 SetAlgebra veto |
| 47 | OS (same pattern) | still surfaces | **suppressed** | V1.14.1 SetAlgebra veto |
| 48 | Algo Index ops | suppressed (V1.11.1) | (already suppressed) | V1.11.1 direction-label |
| 49 | Algo Index ops | suppressed (V1.11.1) | (already suppressed) | V1.11.1 direction-label |

**5 of 5 cycle-6 inverse-pair rejections now suppressed**, distributed across two complementary mechanisms:
- 2/5 by V1.11.1 direction-label counter (cycle 8).
- 3/5 by V1.14.1 SetAlgebra-shape veto (cycle 11) — picks #45-#47 plus their cycle-9 cross-file expansion (3 → 6 distinct survivors via FunctionPairing across `OrderedSet+Partial SetAlgebra intersection.swift` × `OrderedSet+Partial SetAlgebra subtracting.swift` × `OrderedSet+UnorderedView.swift`).

The cycle-6 inverse-pair acceptance rate (0/5 = 0%) now has all five rejection picks suppressed. A cycle-12+ Possible-tier re-sampling on the post-v1.14 surface would measure whether the per-template rate has moved up.

## Reproducibility — capture commands

```sh
cd ~/xcode_projects/SwiftInferProperties
# Debug binary at .build/debug/swift-infer (rebuilt by `swift test`).

# swift-numerics / ComplexModule
cd ~/calibration/swift-numerics
~/xcode_projects/SwiftInferProperties/.build/debug/swift-infer discover \
    --target ComplexModule --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-11-data/post-setalgebra-veto-swift-numerics-ComplexModule.discover.txt

# swift-collections / OrderedCollections
cd ~/xcode_projects/swift-collections
~/xcode_projects/SwiftInferProperties/.build/debug/swift-infer discover \
    --target OrderedCollections --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-11-data/post-setalgebra-veto-swift-collections-OrderedCollections.discover.txt

# swift-algorithms / Algorithms
cd ~/calibration/swift-algorithms
~/xcode_projects/SwiftInferProperties/.build/debug/swift-infer discover \
    --target Algorithms --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-11-data/post-setalgebra-veto-swift-algorithms-Algorithms.discover.txt

# SwiftPropertyLaws / PropertyLawKit
cd ~/xcode_projects/SwiftPropertyLaws
~/xcode_projects/SwiftInferProperties/.build/debug/swift-infer discover \
    --target PropertyLawKit --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-11-data/post-setalgebra-veto-SwiftPropertyLaws-PropertyLawKit.discover.txt
```

## Handoff to V1.14.3 (cycle-11 findings writeup)

V1.14.3 reads this data + the cycle-11 surface and writes `docs/calibration-cycle-11-findings.md` documenting:
1. The **−6 / −2.3% headline aggregate suppression** — first cycle to fully eliminate a template's per-corpus surface (OC inverse-pair 6 → 0).
2. The **first cycle to ship a function-name + type-shape composite mechanism** framing — distinct mechanism class from cycles 7-9's parameter-label counter family.
3. The **cycle-6 picks coverage closure** — all 5 inverse-pair rejection picks now suppressed across V1.11.1 + V1.14.1.
4. The **plan-vs-actual exact match** — second consecutive cycle (after v1.12 → v1.14, with v1.13 being a no-measurement refactor cycle in between).
5. The cumulative **1167 → 251 (-78.5%) trajectory** across 11 calibration cycles (9 mechanism + 1 refactor + cycle-11 mechanism).
6. **Cycle-12 priority list** rotated post-v1.14:
   - **Domain-mismatch family on idempotence + inverse-pair + round-trip simultaneously** — PROMOTED to priority #1 post-v1.14 (was post-v1.13 priority #2). ~19 candidates aggregate (12 OC round-trip + 7 OC idempotence). Could ship as a single mechanism applied to three templates simultaneously, paralleling the direction-counter family's three-cycle deployment cadence but compressed into a single release.
   - **Stride-style label extension** — PROMOTED to priority #2. Closes the 1 Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor on both round-trip + inverse-pair templates simultaneously.
   - **Possible-tier re-sampling on the post-v1.14 surface (251 across 4 corpora)** — PROMOTED to priority #3. Measures cycle-7+8+9+11 cumulative rate-improvement (349 → 251 = −28.1% across four mechanism cycles).
   - **Reference-type carrier counter-signal** — Carried forward (post-v1.13 #5).
   - **FP arm + math-lib op gate + surfacedAt + multi-rater + codec-set** — Carried forward.
