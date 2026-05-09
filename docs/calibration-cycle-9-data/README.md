# v1.12 Calibration Cycle 9 — Empirical Data

Captured: 2026-05-09. swift-infer at `f0c40f4` (V1.12.1 — round-trip direction-label counter-signal). Re-runs the cycle-1+2+3+4+5+6+7+8 corpora with V1.12.1's counter-signal active.

Cycle 9's diff target is the **cycle-8 post-inverse-direction-counter baseline** (the 288-surface). Cycle-9's delta attributes 100% to V1.12.1.

## Attribution note — only V1.12.1 between cycle-8 and cycle-9

Cycle-8 capture was at the V1.11.1 commit; cycle-9 capture is at the V1.12.1 commit. v1.12 ships exactly one structural rule: V1.12.1's `RoundTripTemplate.directionLabelCounterSignal(for:)` returning `-15` when either pair-side's first-param argument label is in `IdempotenceTemplate.directionLabels`. Cycle-9's delta attributes 100% to V1.12.1.

## Corpora

Same four cycle-1+2+3+4+5+6+7+8 targets:

| Corpus | Target | Cycle-8 baseline | Cycle-9 post-counter snapshot |
|---|---|---|---|
| swift-collections | OrderedCollections | [`../calibration-cycle-8-data/post-inverse-direction-counter-swift-collections-OrderedCollections.discover.txt`](../calibration-cycle-8-data/post-inverse-direction-counter-swift-collections-OrderedCollections.discover.txt) | [`post-roundtrip-direction-counter-swift-collections-OrderedCollections.discover.txt`](post-roundtrip-direction-counter-swift-collections-OrderedCollections.discover.txt) |
| swift-numerics | ComplexModule | [`../calibration-cycle-8-data/post-inverse-direction-counter-swift-numerics-ComplexModule.discover.txt`](../calibration-cycle-8-data/post-inverse-direction-counter-swift-numerics-ComplexModule.discover.txt) | [`post-roundtrip-direction-counter-swift-numerics-ComplexModule.discover.txt`](post-roundtrip-direction-counter-swift-numerics-ComplexModule.discover.txt) |
| swift-algorithms | Algorithms | [`../calibration-cycle-8-data/post-inverse-direction-counter-swift-algorithms-Algorithms.discover.txt`](../calibration-cycle-8-data/post-inverse-direction-counter-swift-algorithms-Algorithms.discover.txt) | [`post-roundtrip-direction-counter-swift-algorithms-Algorithms.discover.txt`](post-roundtrip-direction-counter-swift-algorithms-Algorithms.discover.txt) |
| SwiftPropertyLaws | PropertyLawKit | [`../calibration-cycle-8-data/post-inverse-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt`](../calibration-cycle-8-data/post-inverse-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt) | [`post-roundtrip-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt`](post-roundtrip-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt) |

## Aggregate suppression delta

| Corpus | Cycle-8 total | Cycle-9 total | Δ |
|---|---:|---:|---:|
| swift-numerics / ComplexModule | 166 | 166 | 0 |
| swift-collections / OrderedCollections | 84 | 71 | **−13** |
| swift-algorithms / Algorithms | 31 | 13 | **−18** |
| SwiftPropertyLaws / PropertyLawKit | 7 | 7 | 0 |
| **Total** | **288** | **257** | **−31 (−10.8%)** |

Cumulative across cycles 1–9: total surface 1167 → 257 (**−78.0%**) — crosses the 75% reduction milestone projected in the v1.12 plan. Cycle-9's −31 is the **largest single-cycle structural-rule delta to date**, reflecting round-trip being the largest-surface template (181 of 288 = 62.8% of post-v1.11 surface).

**Plan vs actual: point-for-point match.** V1.12.0's projection was −31 (Algo −18, OC −13, CM 0, PLK 0). Actual: −31 (Algo −18, OC −13, CM 0, PLK 0). Methodology fix from cycle-8's findings (use `Template: <name>` per-line count, not substring count) paid off immediately.

## Per-template breakdown

All −31 suppressions are on the round-trip template. Other six templates byte-identical to cycle-8.

### swift-algorithms / Algorithms

| Template | Cycle-8 | Cycle-9 | Δ |
|---|---:|---:|---:|
| **round-trip** | **20** | **2** | **−18** |
| idempotence | 5 | 5 | 0 |
| monotonicity | 3 | 3 | 0 |
| commutativity | 1 | 1 | 0 |
| associativity | 1 | 1 | 0 |
| inverse-pair | 1 | 1 | 0 |

The 18 suppressed round-trip claims are direction-labeled `index(after:) ↔ index(before:)` self-pairs across multiple Algorithms source files (AdjacentPairs, Chain, Chunked × 5 instances, Compacted, Cycle, EitherSequence, FlattenCollection, Indexed, Intersperse × 2, Joined × 2, Product, Stride, Windows). The 2 cycle-9 survivors are *not* direction-labeled:
- `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` (Chunked) — labels `startingAt` / `endingAt` are stride-style, **not** in the curated 10-element direction set. Cycle-10 candidate per the v1.12 plan's "stride-style label extension" out-of-scope item.
- `log(_:) ↔ log(onePlus:)` (RandomSample) — `_` and `onePlus` not in the curated direction set. Domain-mismatch territory (mathematically related but not strictly inverse).

### swift-collections / OrderedCollections

| Template | Cycle-8 | Cycle-9 | Δ |
|---|---:|---:|---:|
| **round-trip** | **25** | **12** | **−13** |
| idempotence | 13 | 13 | 0 |
| inverse-pair | 6 | 6 | 0 |
| monotonicity | 20 | 20 | 0 |
| commutativity | 10 | 10 | 0 |
| associativity | 10 | 10 | 0 |

The 13 suppressed round-trip claims are direction-labeled — `index(after:)/(before:)` self-pairs across `OrderedDictionary+Elements.SubSequence`, `OrderedDictionary+Elements`, `OrderedDictionary+Values`, `OrderedSet+RandomAccessCollection`, `OrderedSet+SubSequence`; one `word(after:) ↔ word(before:)` pair on `_HashTable+UnsafeHandle`; plus 6 cross-pairs between OS+RandomAccessCollection's `index(after:)/index(before:)` and OS+Testing's `_minimumCapacity(forScale:)/_maximumCapacity(forScale:)/_scale(forCapacity:)` (either-side detection fires on `after`/`before` even though the partner uses `forScale`/`forCapacity`).

The 12 cycle-9 survivors are all non-direction-labeled — six HashTable Constants pairs (`minimumCapacity(forScale:) ↔ maximumCapacity(forScale:)` etc.), three OS+Testing internal pairs, two `_value(forBucketContents:) ↔ _bucketContents(for:)` shape pairs, and one `(UInt64) -> Int? ↔ (Int?) -> UInt64` shape pair. All are `forScale`/`forCapacity`/`forBucketContents`/`_` — domain-mismatch territory for cycle-10's planned mechanism.

### swift-numerics / ComplexModule

| Template | Cycle-8 | Cycle-9 | Δ |
|---|---:|---:|---:|
| round-trip | 136 | 136 | 0 |
| idempotence | 17 | 17 | 0 |
| commutativity | 6 | 6 | 0 |
| associativity | 6 | 6 | 0 |
| identity-element | 1 | 1 | 0 |

ComplexModule has zero direction-labeled round-trip pairs — all `(Complex, Complex) -> Complex` shapes use `_:` parameter labels (Swift convention for arithmetic ops). Byte-identical to cycle-8.

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-8 | Cycle-9 | Δ |
|---|---:|---:|---:|
| monotonicity | 6 | 6 | 0 |
| idempotence | 1 | 1 | 0 |

No round-trip candidates. Byte-identical to cycle-8.

## Cycle-6 round-trip picks verification

Of the cycle-6 round-trip triage picks (14 total — 6 accepts, 8 rejects), V1.12.1 should suppress direction-labeled rejection picks. Cycle-6 sample manifest in `docs/calibration-cycle-6-data/sample-manifest.md` documents the round-trip picks; verification against the v1.12 binary is V1.12.3's (cycle-9 findings) responsibility, not this README's. The empirical data is captured here for V1.12.3 to cross-reference.

## Plan-vs-actual deviation

Plan projection: **−18 Algo + −13 OC + 0 CM + 0 PLK = −31 total**.
Actual: **−18 Algo + −13 OC + 0 CM + 0 PLK = −31 total**.

**Exact match.** This is a methodology win after the cycle-8 findings' lesson — the v1.12 plan's per-suggestion line-count survey of cycle-8 snapshots (using `re.compile(r"^Template:\s+(\S+)")`) projected the exact suppression count. Contrast with cycle-8's plan-vs-actual deviation (projected −12, actual −8; over-projected Algo 2× because the original grep used substring counts).

## Reproducibility — capture commands

```sh
cd ~/xcode_projects/SwiftInferProperties
# Debug binary at .build/debug/swift-infer (rebuilt by `swift test`).
# Release builds also work but are not required.

# swift-numerics / ComplexModule
cd ~/calibration/swift-numerics
~/xcode_projects/SwiftInferProperties/.build/debug/swift-infer discover \
    --target ComplexModule --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-9-data/post-roundtrip-direction-counter-swift-numerics-ComplexModule.discover.txt

# swift-collections / OrderedCollections
cd ~/xcode_projects/swift-collections
~/xcode_projects/SwiftInferProperties/.build/debug/swift-infer discover \
    --target OrderedCollections --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-9-data/post-roundtrip-direction-counter-swift-collections-OrderedCollections.discover.txt

# swift-algorithms / Algorithms
cd ~/calibration/swift-algorithms
~/xcode_projects/SwiftInferProperties/.build/debug/swift-infer discover \
    --target Algorithms --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-9-data/post-roundtrip-direction-counter-swift-algorithms-Algorithms.discover.txt

# SwiftPropertyLaws / PropertyLawKit
cd ~/xcode_projects/SwiftPropertyLaws
~/xcode_projects/SwiftInferProperties/.build/debug/swift-infer discover \
    --target PropertyLawKit --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-9-data/post-roundtrip-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt
```

## Handoff to V1.12.3 (cycle-9 findings writeup)

V1.12.3 reads this data + the cycle-9 surface and writes `docs/calibration-cycle-9-findings.md` documenting:
1. The **−31 / −10.8% headline aggregate suppression** — largest single-cycle structural-rule delta to date.
2. The **direction-counter-family completion** framing — first time a verified mechanism has been ported to a third template, validating `Signal.Kind.directionLabel` as template-agnostic and the curated direction set as portable across `+25`/`+30`/`+30` baselines.
3. The **plan-vs-actual exact match** — methodology validation (per-suggestion line counts > substring counts, lesson from cycle-8 paid off in cycle-9's projection accuracy).
4. The **75% cumulative reduction milestone** crossed (1167 → 257 = 78.0%).
5. The **cycle-10 priority list**:
   - **v1.13 hoist** — `directionLabels` + `Signal.Kind.directionLabel` to a shared `SwiftInferCore.DirectionLabels` namespace (zero behavior change; v1.12 satisfies the v1.11 open-decision-#2 commitment "hoist when round-trip becomes the third consumer").
   - **SetAlgebra-shape detection on inverse-pair** — addresses the 6 OC `intersection(_:) ↔ subtracting(_:)` survivors (cycle-6 picks #45-#47).
   - **Domain-mismatch detection on idempotence + inverse-pair + round-trip** — `forScale`/`forCapacity` semantic-intent. Could ship as a single mechanism applied to three templates; the surviving 12 OC + 0 Algo + 0 CM + 0 PLK round-trip Possible-tier suggestions are the natural test bed.
   - **Stride-style label extension** — `startingAt`, `endingAt`, `offset`. Closes the 1 Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` round-trip survivor + the 1 inverse-pair survivor with the same labels.
   - **Possible-tier re-sampling on the post-v1.12 surface** (257 across 4 corpora) — quantifies the cycle-7+8+9 cumulative rate-improvement.
   - **`surfacedAt` plumbing** — carried forward.
   - **FP arm + math-lib op extension** — carried forward.
6. **Open question:** the cycle-6 round-trip acceptance rate was 6/14 = 42.9%; cycle-9 suppresses an unknown subset of the 8 rejected picks (those that were direction-labeled). Re-sampling the post-V1.12.1 round-trip surface (181 candidates aggregate → 150 survivors) would measure whether the per-template rate has moved up.
