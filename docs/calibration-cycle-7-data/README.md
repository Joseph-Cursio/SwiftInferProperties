# v1.10 Calibration Cycle 7 — Empirical Data

Captured: 2026-05-08. swift-infer at `9bff3a3` (V1.10.1 — direction-label counter-signal). Re-runs the cycle-1+2+3+4+5+6 corpora with V1.10.1's direction-label counter-signal active.

Cycle 7's diff target is the **cycle-5 post-tightening baseline** (the 349-surface). Cycle 6 didn't move the surface — it was empirical-only — so cycle-5 + cycle-6's snapshots are byte-equivalent. Cycle-7's delta is therefore attributable cleanly to V1.10.1.

## Attribution note — only V1.10.1 between cycle-5/6 and cycle-7

Cycle-5 capture was at the V1.8.1 commit; cycle-7 capture is at the V1.10.1 commit. v1.9 between them was empirical-only (zero Sources/ changes). Cycle-7's delta vs cycle-5 attributes 100% to V1.10.1.

## Corpora

Same four cycle-1+2+3+4+5+6 targets:

| Corpus | Target | Cycle-5 baseline | Cycle-7 post-counter snapshot |
|---|---|---|---|
| swift-collections | OrderedCollections | [`../calibration-cycle-5-data/post-tightening-swift-collections-OrderedCollections.discover.txt`](../calibration-cycle-5-data/post-tightening-swift-collections-OrderedCollections.discover.txt) | [`post-direction-counter-swift-collections-OrderedCollections.discover.txt`](post-direction-counter-swift-collections-OrderedCollections.discover.txt) |
| swift-numerics | ComplexModule | [`../calibration-cycle-5-data/post-tightening-swift-numerics-ComplexModule.discover.txt`](../calibration-cycle-5-data/post-tightening-swift-numerics-ComplexModule.discover.txt) | [`post-direction-counter-swift-numerics-ComplexModule.discover.txt`](post-direction-counter-swift-numerics-ComplexModule.discover.txt) |
| swift-algorithms | Algorithms | [`../calibration-cycle-5-data/post-tightening-swift-algorithms-Algorithms.discover.txt`](../calibration-cycle-5-data/post-tightening-swift-algorithms-Algorithms.discover.txt) | [`post-direction-counter-swift-algorithms-Algorithms.discover.txt`](post-direction-counter-swift-algorithms-Algorithms.discover.txt) |
| SwiftPropertyLaws | PropertyLawKit | [`../calibration-cycle-5-data/post-tightening-SwiftPropertyLaws-PropertyLawKit.discover.txt`](../calibration-cycle-5-data/post-tightening-SwiftPropertyLaws-PropertyLawKit.discover.txt) | [`post-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt`](post-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt) |

## Aggregate suppression delta

| Corpus | Cycle-5/6 total | Cycle-7 total | Δ |
|---|---:|---:|---:|
| swift-numerics / ComplexModule | 166 | 166 | 0 |
| swift-collections / OrderedCollections | 101 | 87 | **−14** |
| swift-algorithms / Algorithms | 75 | 36 | **−39** |
| SwiftPropertyLaws / PropertyLawKit | 7 | 7 | 0 |
| **Total** | **349** | **296** | **−53 (−15.2%)** |

Cumulative across cycles 1–7: total surface 1167 → 296 (−74.6%). Cycle-7's −53 is the second-largest single-cycle suppression after cycle-1's structural counter-signals.

## Per-template breakdown

All −53 suppressions are on the idempotence template. Other six templates byte-identical to cycle-5.

### swift-algorithms / Algorithms — the headline corpus

| Template | Cycle-5 | Cycle-7 | Δ |
|---|---:|---:|---:|
| **idempotence** | **44** | **5** | **−39** |
| round-trip | 20 | 20 | 0 |
| inverse-pair | 6 | 6 | 0 |
| monotonicity | 3 | 3 | 0 |
| commutativity | 1 | 1 | 0 |
| associativity | 1 | 1 | 0 |

The 39 suppressed idempotence claims are all `(Index) -> Index` / `(Base.Index) -> Base.Index` increment / decrement ops with `after:` or `before:` argument labels, distributed across 11 source files (AdjacentPairs, Chain, Chunked, Compacted, Cycle, EitherSequence, FlattenCollection, Indexed, Intersperse, Joined, Product). The 5 cycle-7 survivors are non-direction-labeled idempotence claims:
- `endOfChunk(startingAt:)` (Chunked) — `startingAt` not in direction set
- `startOfChunk(endingAt:)` (Chunked) — `endingAt` not in direction set
- `sizeOfChunk(offset:)` (Chunked) — `offset` not in direction set
- `log(_:)` and `log(onePlus:)` (RandomSample) — `_` / `onePlus` not in direction set

### swift-collections / OrderedCollections

| Template | Cycle-5 | Cycle-7 | Δ |
|---|---:|---:|---:|
| **idempotence** | **27** | **13** | **−14** |
| round-trip | 25 | 25 | 0 |
| monotonicity | 20 | 20 | 0 |
| commutativity | 10 | 10 | 0 |
| associativity | 10 | 10 | 0 |
| inverse-pair | 9 | 9 | 0 |

The 14 suppressed claims include `index(after:)` / `index(before:)` from OrderedDictionary+Elements / OrderedDictionary+Values / OrderedSet+RandomAccessCollection sites, plus `bucket(after:)` / `bucket(before:)` from _HashTable+UnsafeHandle, plus `word(after:)` / `word(before:)`. The 13 cycle-7 survivors are:
- HashTable scale-vs-capacity functions: `minimumCapacity(forScale:)`, `maximumCapacity(forScale:)`, `scale(forCapacity:)`, `wordCount(forScale:)`, plus their `_minimumCapacity` / `_maximumCapacity` / `_scale` test-shim variants — these are the cycle-6 documented domain-mismatch sub-pattern, deferred to cycle-8.
- Self-typed SetAlgebra ops: `intersection(_:)` (×2 sites), `subtracting(_:)` (×2 sites) — `_` label not in direction set.
- Other: `_description(type:)`, `firstOccupiedBucketInChain(with:)` — non-direction-labeled.

### swift-numerics / ComplexModule

| Template | Cycle-5 | Cycle-7 | Δ |
|---|---:|---:|---:|
| idempotence | 17 | 17 | 0 |
| round-trip | 136 | 136 | 0 |
| commutativity | 6 | 6 | 0 |
| associativity | 6 | 6 | 0 |
| identity-element | 1 | 1 | 0 |

ComplexModule's 17 idempotence claims are on Complex elementary functions (`exp(_:)`, `log(_:)`, `cosh(_:)`, etc.) — none have direction labels. Byte-identical to cycle-5.

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-5 | Cycle-7 | Δ |
|---|---:|---:|---:|
| monotonicity | 6 | 6 | 0 |
| idempotence | 1 | 1 | 0 |

The 1 idempotence claim is `nearMissLines(_:)` — `_` label not in direction set. Byte-identical to cycle-5.

## Cycle-6 picks verification

Of the cycle-6 idempotence-template triage picks (10 rejections), the cycle-7 binary now suppresses the direction-labeled subset:

| # | Cycle-6 pick | Cycle-7 outcome | Notes |
|---|---|---|---|
| 17 | `minimumCapacity(forScale:)` | still surfaces | `forScale` ∉ direction set; cycle-8 candidate (domain-mismatch). |
| 18 | `index(after:)` (OrderedDictionary+Elements) | **suppressed** | `after` ∈ direction set ✓ |
| 19 | `bucket(after:)` (_HashTable+UnsafeHandle) | **suppressed** | `after` ∈ direction set ✓ |
| 20 | `_minimumCapacity(forScale:)` (OrderedSet+Testing) | still surfaces | `forScale` ∉ direction set; cycle-8 candidate. |
| 21 | `exp(_:)` (Complex) | still surfaces | `_` (nil label) ∉ direction set. |
| 22 | `log(_:)` (Complex) | still surfaces | `_` ∉ direction set. |
| 23 | `Complex` self-pair (unknown which) | still surfaces (probably) | flagged unknown in cycle-6. |
| 24 | `index(after:)` (AdjacentPairs) | **suppressed** | `after` ∈ direction set ✓ |
| 25 | `endOfChunk(startingAt:)` (Chunked) | still surfaces | `startingAt` ∉ direction set. |
| 26 | `index(after:)` (FlattenCollection) | **suppressed** | `after` ∈ direction set ✓ |
| 27 | `index(before:)` (Joined) | **suppressed** | `before` ∈ direction set ✓ |
| 28 | `nearMissLines(_:)` (PLK) | still surfaces | `_` ∉ direction set; cycle-6 flagged unknown. |

5 of 10 cycle-6 idempotence rejections are now suppressed by V1.10.1's counter-signal. The other 5 are correctly preserved (different cause-of-noise classes that v1.10 doesn't address):
- 3× `forScale` domain-mismatch — cycle-8 candidate.
- 2× exp/log on Complex — paramless / `_`-labeled, no direction signal; would need a different mechanism (FP-template arm could re-frame these).

## Reproducibility — capture commands

```sh
cd ~/xcode_projects/SwiftInferProperties
swift build -c release  # produces .build/release/swift-infer

# swift-numerics / ComplexModule
cd ~/calibration/swift-numerics
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target ComplexModule --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-7-data/post-direction-counter-swift-numerics-ComplexModule.discover.txt

# swift-collections / OrderedCollections
cd ~/xcode_projects/swift-collections
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target OrderedCollections --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-7-data/post-direction-counter-swift-collections-OrderedCollections.discover.txt

# swift-algorithms / Algorithms
cd ~/calibration/swift-algorithms
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target Algorithms --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-7-data/post-direction-counter-swift-algorithms-Algorithms.discover.txt

# SwiftPropertyLaws / PropertyLawKit
cd ~/xcode_projects/SwiftPropertyLaws
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target PropertyLawKit --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-7-data/post-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt
```

## Handoff to V1.10.3 (cycle-7 findings writeup)

V1.10.3 reads this data + the cycle-7 surface and writes `docs/calibration-cycle-7-findings.md` documenting:
1. The −53 / −15.2% headline aggregate suppression.
2. The Algorithms-corpus 39-suppression dominance — Index-protocol after/before pattern is the most concentrated cause-of-noise V1.10.1 addresses.
3. Verification of the cycle-6 picks: 5 of 10 idempotence rejections are now correctly suppressed.
4. The cycle-8 priority list (domain-mismatch detection, inverse-pair direction counter, FP arm, math-lib op extension, round-trip directional counter, surfacedAt plumbing, multi-rater methodology).
5. **Open question:** the cycle-6 acceptance rate was 0/10 = 0%; cycle-7 suppresses 5 of 10 rejections. If cycle-8 re-samples the post-V1.10.1 idempotence surface, the *new* per-template rate should be measurably higher because the noise-floor was lifted.
