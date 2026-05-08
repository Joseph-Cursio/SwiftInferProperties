# v1.11 Calibration Cycle 8 — Empirical Data

Captured: 2026-05-08. swift-infer at `307036f` (V1.11.1 — inverse-pair direction-label counter-signal). Re-runs the cycle-1+2+3+4+5+6+7 corpora with V1.11.1's counter-signal active.

Cycle 8's diff target is the **cycle-7 post-direction-counter baseline** (the 296-surface). Cycle-8's delta attributes 100% to V1.11.1.

## Attribution note — only V1.11.1 between cycle-7 and cycle-8

Cycle-7 capture was at the V1.10.1 commit; cycle-8 capture is at the V1.11.1 commit. v1.11 ships exactly one structural rule: V1.11.1's `InversePairTemplate.directionLabelCounterSignal(for:)` returning `-10` when either pair-side's first-param argument label is in `IdempotenceTemplate.directionLabels`. Cycle-8's delta attributes 100% to V1.11.1.

## Corpora

Same four cycle-1+2+3+4+5+6+7 targets:

| Corpus | Target | Cycle-7 baseline | Cycle-8 post-counter snapshot |
|---|---|---|---|
| swift-collections | OrderedCollections | [`../calibration-cycle-7-data/post-direction-counter-swift-collections-OrderedCollections.discover.txt`](../calibration-cycle-7-data/post-direction-counter-swift-collections-OrderedCollections.discover.txt) | [`post-inverse-direction-counter-swift-collections-OrderedCollections.discover.txt`](post-inverse-direction-counter-swift-collections-OrderedCollections.discover.txt) |
| swift-numerics | ComplexModule | [`../calibration-cycle-7-data/post-direction-counter-swift-numerics-ComplexModule.discover.txt`](../calibration-cycle-7-data/post-direction-counter-swift-numerics-ComplexModule.discover.txt) | [`post-inverse-direction-counter-swift-numerics-ComplexModule.discover.txt`](post-inverse-direction-counter-swift-numerics-ComplexModule.discover.txt) |
| swift-algorithms | Algorithms | [`../calibration-cycle-7-data/post-direction-counter-swift-algorithms-Algorithms.discover.txt`](../calibration-cycle-7-data/post-direction-counter-swift-algorithms-Algorithms.discover.txt) | [`post-inverse-direction-counter-swift-algorithms-Algorithms.discover.txt`](post-inverse-direction-counter-swift-algorithms-Algorithms.discover.txt) |
| SwiftPropertyLaws | PropertyLawKit | [`../calibration-cycle-7-data/post-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt`](../calibration-cycle-7-data/post-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt) | [`post-inverse-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt`](post-inverse-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt) |

## Aggregate suppression delta

| Corpus | Cycle-7 total | Cycle-8 total | Δ |
|---|---:|---:|---:|
| swift-numerics / ComplexModule | 166 | 166 | 0 |
| swift-collections / OrderedCollections | 87 | 84 | **−3** |
| swift-algorithms / Algorithms | 36 | 31 | **−5** |
| SwiftPropertyLaws / PropertyLawKit | 7 | 7 | 0 |
| **Total** | **296** | **288** | **−8 (−2.7%)** |

Cumulative across cycles 1–8: total surface 1167 → 288 (**−75.3%**). Cycle-8's −8 is the smallest single-cycle structural-rule delta to date, reflecting the narrow targeting (inverse-pair was already the smallest-surface template per cycle-7 — 6 Algo + 9 OC = 15 candidates total to evaluate).

## Per-template breakdown

All −8 suppressions are on the inverse-pair template. Other six templates byte-identical to cycle-7.

### swift-algorithms / Algorithms

| Template | Cycle-7 | Cycle-8 | Δ |
|---|---:|---:|---:|
| **inverse-pair** | **6** | **1** | **−5** |
| idempotence | 5 | 5 | 0 |
| round-trip | 20 | 20 | 0 |
| monotonicity | 3 | 3 | 0 |
| commutativity | 1 | 1 | 0 |
| associativity | 1 | 1 | 0 |

The 5 suppressed inverse-pair claims are direction-labeled `index(after:) × index(after:)` self-pairs across multiple Algorithms source files (AdjacentPairs, Chain, Chunked, Compacted, Cycle, EitherSequence, FlattenCollection, Indexed, Intersperse, Joined, Product). The 1 cycle-8 survivor is non-direction-labeled:
- `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` (Chunked) — labels `startingAt` / `endingAt` are stride-style, *not* in the curated 10-element direction set. Cycle-10 candidate per the v1.11 plan's "stride-style label extension" out-of-scope item.

### swift-collections / OrderedCollections

| Template | Cycle-7 | Cycle-8 | Δ |
|---|---:|---:|---:|
| **inverse-pair** | **9** | **6** | **−3** |
| idempotence | 13 | 13 | 0 |
| round-trip | 25 | 25 | 0 |
| monotonicity | 20 | 20 | 0 |
| commutativity | 10 | 10 | 0 |
| associativity | 10 | 10 | 0 |

The 3 suppressed inverse-pair claims are direction-labeled — likely `index(after:)/(before:)`, `bucket(after:)/(before:)`, or `word(after:)/(before:)` self-pairs (mirror of v1.10's idempotence suppressions on the same source files but in pair shape). The 6 cycle-8 survivors are all SetAlgebra-shaped Self-typed binary ops with `_:` (nil) labels:
- `intersection(_:) ↔ subtracting(_:)` × 6 site combinations across `OrderedSet+Partial SetAlgebra intersection.swift` × `OrderedSet+Partial SetAlgebra subtracting.swift` × `OrderedSet+UnorderedView.swift`. These match cycle-6 picks #45-#47 verbatim — same 3-of-5 inverse-pair rejection sub-pattern. Cycle-9 candidate (domain-mismatch / SetAlgebra-shape detection on inverse-pair).

### swift-numerics / ComplexModule

| Template | Cycle-7 | Cycle-8 | Δ |
|---|---:|---:|---:|
| round-trip | 136 | 136 | 0 |
| idempotence | 17 | 17 | 0 |
| commutativity | 6 | 6 | 0 |
| associativity | 6 | 6 | 0 |
| identity-element | 1 | 1 | 0 |

ComplexModule has no inverse-pair candidates per cycle-7 (all elementary functions are paired into round-trip, not inverse-pair, due to Complex being Equatable). Byte-identical to cycle-7.

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-7 | Cycle-8 | Δ |
|---|---:|---:|---:|
| monotonicity | 6 | 6 | 0 |
| idempotence | 1 | 1 | 0 |

No inverse-pair candidates. Byte-identical to cycle-7.

## Cycle-6 picks verification

Of the cycle-6 inverse-pair triage picks (5 rejections, IDs 45-49), V1.11.1 suppresses exactly the direction-labeled subset:

| # | Cycle-6 pick (corpus) | Cycle-8 outcome | Notes |
|---|---|---|---|
| 45 | OrderedSet `intersection(_:) ↔ subtracting(_:)` (OC) | still surfaces | `_` (nil label) ∉ direction set; cycle-9 candidate (SetAlgebra-shape detection). |
| 46 | OrderedSet (same pattern) (OC) | still surfaces | Same. |
| 47 | OrderedSet (same pattern) (OC) | still surfaces | Same. |
| 48 | Algorithms Index ops (Algo) | **suppressed** | `after`/`before` ∈ direction set ✓ |
| 49 | Algorithms Index ops (Algo) | **suppressed** | Same. |

**2 of 5 cycle-6 inverse-pair rejections are now suppressed by V1.11.1's counter-signal.** The other 3 are correctly preserved (different cause-of-noise class — SetAlgebra-shaped Self-typed ops with no labels — for cycle-9 to address).

This matches the v1.11 plan's projection exactly: the plan predicted 2 of 5 suppression at the picks level (Algo #48-#49 direction-labeled; OC #45-#47 SetAlgebra-shaped, no direction labels) and that's what landed.

## Plan-vs-actual deviation

Plan projection: **~−10 Algo + ~−2 OC = ~−12 total**.
Actual: **−5 Algo + −3 OC = −8 total**.

The plan over-projected Algo (−10 vs −5) because the earlier `grep -c "inverse-pair"` count of 12 was string-based (counting all `inverse-pair` substring occurrences in identity hashes / detail lines) rather than `Template: inverse-pair` line count (the per-suggestion count). The actual cycle-7 Algo inverse-pair surface was 6 candidates (not 12); 5 of 6 were direction-labeled and got suppressed; 1 stride-labeled survivor stays.

The plan under-projected OC (−2 vs −3) by an off-by-one — the third suppressed OC inverse-pair was a `bucket`/`word`-shape pair I hadn't enumerated in projection.

Net plan accuracy: dominated by the Algo over-projection. Methodology lesson for cycle-9 plan: when projecting from existing data, use `grep -c "Template: <name>"` (per-suggestion line count) rather than substring counts.

## Reproducibility — capture commands

```sh
cd ~/xcode_projects/SwiftInferProperties
swift build -c release  # produces .build/arm64-apple-macosx/release/swift-infer
# (debug binary at .build/debug/swift-infer also works — captures here used debug)

# swift-numerics / ComplexModule
cd ~/calibration/swift-numerics
~/xcode_projects/SwiftInferProperties/.build/debug/swift-infer discover \
    --target ComplexModule --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-8-data/post-inverse-direction-counter-swift-numerics-ComplexModule.discover.txt

# swift-collections / OrderedCollections
cd ~/xcode_projects/swift-collections
~/xcode_projects/SwiftInferProperties/.build/debug/swift-infer discover \
    --target OrderedCollections --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-8-data/post-inverse-direction-counter-swift-collections-OrderedCollections.discover.txt

# swift-algorithms / Algorithms
cd ~/calibration/swift-algorithms
~/xcode_projects/SwiftInferProperties/.build/debug/swift-infer discover \
    --target Algorithms --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-8-data/post-inverse-direction-counter-swift-algorithms-Algorithms.discover.txt

# SwiftPropertyLaws / PropertyLawKit
cd ~/xcode_projects/SwiftPropertyLaws
~/xcode_projects/SwiftInferProperties/.build/debug/swift-infer discover \
    --target PropertyLawKit --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-8-data/post-inverse-direction-counter-SwiftPropertyLaws-PropertyLawKit.discover.txt
```

## Handoff to V1.11.3 (cycle-8 findings writeup)

V1.11.3 reads this data + the cycle-8 surface and writes `docs/calibration-cycle-8-findings.md` documenting:
1. The −8 / −2.7% headline aggregate suppression — smaller than v1.10's −53 / −15.2% because inverse-pair was a much smaller starting surface.
2. The cycle-7 → cycle-8 mechanism-replication framing — first time a verified mechanism is ported across templates with successful empirical effect.
3. Verification of the cycle-6 inverse-pair picks: 2 of 5 are now suppressed; 3 of 5 stay surfaced (correct: different cause-of-noise class).
4. The cycle-9 priority list (round-trip direction counter, SetAlgebra-shape detection on inverse-pair, domain-mismatch detection on idempotence + inverse-pair, stride-style label extension, FP arm, math-lib op extension, surfacedAt plumbing, Possible-tier re-sampling at v1.11).
5. **Open question:** the cycle-6 inverse-pair acceptance rate was 0/5 = 0%; cycle-8 suppresses 2 of 5 rejections. Re-sampling the post-V1.11.1 inverse-pair surface (15 candidates aggregate → 7 survivors) would measure whether the per-template rate has moved up.
