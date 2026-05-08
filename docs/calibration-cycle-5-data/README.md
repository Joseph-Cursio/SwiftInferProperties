# v1.8 Calibration Cycle 5 — Empirical Data

Captured: 2026-05-08. swift-infer at `416d619` (V1.8.1 — round-trip Codable shape gate).

Re-runs the cycle-1+2+3+4 corpora with V1.8.1's shape-gated Codable veto active. Cycle-4's post-bakein snapshots are the diff target; cycle-5 captures the **re-emergence** delta vs that baseline — the first cycle in the calibration trajectory to produce a *positive* delta. Intentionally so: cycle 4 surfaced an over-suppression in V1.5.2's design; cycle 5 fixes it.

## Attribution note — only V1.8.1 between cycle-4 and cycle-5

Cycle-4 capture was at the V1.7.1 commit (`231ae16`); cycle-5 capture is at the V1.8.1 commit (`416d619`). Only one structural change between the two: V1.8.1's shape-gated `RoundTripTemplate.protocolCoverageVeto(...)`. Attribution is clean.

## Corpora

Same four cycle-1+2+3+4 targets, same `--target X --include-possible` invocation:

| Corpus | Target | Cycle-4 post-bakein baseline | Cycle-5 post-tightening snapshot |
|---|---|---|---|
| swift-collections | OrderedCollections | [`../calibration-cycle-4-data/post-bakein-swift-collections-OrderedCollections.discover.txt`](../calibration-cycle-4-data/post-bakein-swift-collections-OrderedCollections.discover.txt) | [`post-tightening-swift-collections-OrderedCollections.discover.txt`](post-tightening-swift-collections-OrderedCollections.discover.txt) |
| swift-numerics | ComplexModule | [`../calibration-cycle-4-data/post-bakein-swift-numerics-ComplexModule.discover.txt`](../calibration-cycle-4-data/post-bakein-swift-numerics-ComplexModule.discover.txt) | [`post-tightening-swift-numerics-ComplexModule.discover.txt`](post-tightening-swift-numerics-ComplexModule.discover.txt) |
| swift-algorithms | Algorithms | [`../calibration-cycle-4-data/post-bakein-swift-algorithms-Algorithms.discover.txt`](../calibration-cycle-4-data/post-bakein-swift-algorithms-Algorithms.discover.txt) | [`post-tightening-swift-algorithms-Algorithms.discover.txt`](post-tightening-swift-algorithms-Algorithms.discover.txt) |
| SwiftPropertyLaws | PropertyLawKit | [`../calibration-cycle-4-data/post-bakein-SwiftPropertyLaws-PropertyLawKit.discover.txt`](../calibration-cycle-4-data/post-bakein-SwiftPropertyLaws-PropertyLawKit.discover.txt) | [`post-tightening-SwiftPropertyLaws-PropertyLawKit.discover.txt`](post-tightening-SwiftPropertyLaws-PropertyLawKit.discover.txt) |

## Aggregate re-emergence delta

| Corpus | Cycle-4 total | Cycle-5 total | Δ |
|---|---:|---:|---:|
| swift-collections / OrderedCollections | 79 | 101 | **+22** |
| swift-algorithms / Algorithms | 74 | 75 | **+1** |
| swift-numerics / ComplexModule | 166 | 166 | 0 |
| SwiftPropertyLaws / PropertyLawKit | 7 | 7 | 0 |
| **Total** | **326** | **349** | **+23 (+7.0%)** |

The **+23** matches the cycle-4 plan's projection precisely (the v1.8 plan f-bullet predicted "OrderedCollections re-emerges 22 round-trip suggestions; Algorithms re-emerges 1"). All re-emergences are on the round-trip template; identity-element / commutativity / associativity / idempotence / inverse-pair / monotonicity templates are unchanged.

Cumulative trajectory across cycles 1–5: **1167 → 349 (−70.1%)**. The +23 in cycle-5 *partially undoes* V1.7.1's −23 round-trip suppressions, leaving the cumulative cumulative reduction at 70.1% (vs 72.1% post-V1.7.1). This is the calibration-pipeline's first-ever non-monotonic surface delta — and it's the *correct* outcome: V1.7.1 found 23 over-suppressions, V1.8.1 fixes them.

## Per-template re-emergence breakdown

### swift-collections / OrderedCollections — the headline re-emergence

| Template | Cycle-4 | Cycle-5 | Δ |
|---|---:|---:|---:|
| **round-trip** | **3** | **25** | **+22** |
| idempotence | 27 | 27 | 0 |
| monotonicity | 20 | 20 | 0 |
| commutativity | 10 | 10 | 0 |
| associativity | 10 | 10 | 0 |
| inverse-pair | 9 | 9 | 0 |

The 22 re-emerged round-trip pairs match the cycle-4 V1.7.1 suppression set exactly:
- 21 `(Int) -> Int ↔ (Int) -> Int` pairs (HashTable+Constants `minimumCapacity` / `maximumCapacity` / `scale` / `wordCount` cross-product, OrderedDictionary index-after/before, OrderedSet index-after/before, etc.)
- 1 `(UInt64) -> Int? ↔ (Int?) -> UInt64` pair (`_value(forBucketContents:)` ↔ `_bucketContents(for:)`)

Each re-emerges at Score 30 (Possible tier) — type-symmetry alone, no curated name bonus. Available for `--include-possible` triage decisions.

The 3 cycle-4 surviving round-trip suggestions (1 `(Bucket) -> Bucket` + 2 `(Self) -> Self`) carry through unchanged to cycle-5.

### swift-algorithms / Algorithms

| Template | Cycle-4 | Cycle-5 | Δ |
|---|---:|---:|---:|
| **round-trip** | **19** | **20** | **+1** |
| idempotence | 44 | 44 | 0 |
| inverse-pair | 6 | 6 | 0 |
| monotonicity | 3 | 3 | 0 |
| commutativity | 1 | 1 | 0 |
| associativity | 1 | 1 | 0 |

The +1 is the `(Double) -> Double` round-trip pair V1.7.1's `Double: Codable` bake-in had suppressed.

### swift-numerics / ComplexModule

| Template | Cycle-4 | Cycle-5 | Δ |
|---|---:|---:|---:|
| round-trip | 136 | 136 | 0 |
| idempotence | 17 | 17 | 0 |
| commutativity | 6 | 6 | 0 |
| associativity | 6 | 6 | 0 |
| identity-element | 1 | 1 | 0 |

ComplexModule's 136 round-trip pairs are on user types whose textual signatures didn't trigger the V1.5.2 Codable veto in the first place (the `Complex<RealType>` carrier resolves to `Complex` which is Codable, but the round-trip pairs have `RealType` / `Complex` / generic Self / shape mismatches that didn't fit the simple `forward.parameters.first?.typeText` lookup before V1.8.1, and don't fit the new shape gate either). Confirmed byte-identical to cycle-4 via `diff`.

### SwiftPropertyLaws / PropertyLawKit

Unchanged from cycle-4 (no round-trip suggestions in either cycle). PropertyLawKit's 7-suggestion floor reflects monotonicity / idempotence on kit-internal types.

## Trajectory framing — first non-monotonic cycle

Every prior calibration cycle decreased the surface count:

| Cycle | Mechanism | Surface | Δ |
|---|---|---:|---:|
| 1 (pre-tune) | none | 1167 | — |
| 1 (post-tune V1.4.3) | FP-storage + cross-type round-trip counter-signals | 358 | −809 |
| 2 (V1.5.2) | textual-only protocol-coverage suppression | 353 | −5 |
| 3 (V1.6.1) | identity-element pair-formation skip-list | 350 | −3 |
| 4 (V1.7.1) | stdlib-conformance bake-in | 326 | −24 |
| **5 (V1.8.1)** | **shape-gated Codable veto** | **349** | **+23** |

V1.8.1 is intentionally an *un-suppression* — it doesn't add a new rule, it narrows V1.5.2's existing rule to fire only when the kit law actually applies. The surface count goes up because V1.7.1's bake-in had unintentionally widened V1.5.2's reach to suppress 23 user-defined inverse pairs that the kit doesn't verify. V1.8.1 hands those 23 back to the user as Possible-tier surface for triage.

This framing matters for the §17.3 calibration loop: monotonic surface reduction isn't the goal — *appropriate* suppression is. Cycle-5's positive delta closes a known design issue.

## Reproducibility — capture commands

```sh
cd ~/xcode_projects/SwiftInferProperties
swift build -c release  # produces .build/release/swift-infer

# swift-numerics / ComplexModule
cd ~/calibration/swift-numerics
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target ComplexModule --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-5-data/post-tightening-swift-numerics-ComplexModule.discover.txt

# swift-collections / OrderedCollections
cd ~/xcode_projects/swift-collections
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target OrderedCollections --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-5-data/post-tightening-swift-collections-OrderedCollections.discover.txt

# swift-algorithms / Algorithms
cd ~/calibration/swift-algorithms
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target Algorithms --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-5-data/post-tightening-swift-algorithms-Algorithms.discover.txt

# SwiftPropertyLaws / PropertyLawKit
cd ~/xcode_projects/SwiftPropertyLaws
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target PropertyLawKit --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-5-data/post-tightening-SwiftPropertyLaws-PropertyLawKit.discover.txt
```

## Handoff to V1.8.3 (cycle-5 findings writeup)

V1.8.3 reads this data + the cycle-5 surface and writes `docs/calibration-cycle-5-findings.md` documenting:

1. The +22 re-emergence on OrderedCollections — the headline empirical effect closing the cycle-4 design question.
2. The +1 re-emergence on Algorithms — confirms V1.8.1's gate handles `Double` correctly.
3. The 0-delta on ComplexModule + PropertyLawKit — neither corpus had a `(T) -> T` user-inverse pair on a stdlib carrier, so V1.8.1 has no suppressions to undo.
4. The first non-monotonic cycle in the calibration trajectory — framing for the v1.x calibration narrative.
5. The cycle-6 priority list (Possible-tier sampling on the new 349-surface, FP template arm, surfacedAt plumbing, math-library op extension).
6. **Open question:** whether the M1.4 SuggestionIdentity hash for these re-emerged 23 suggestions matches what was suppressed pre-V1.7.1 (cycle-3) — a yes confirms Decisions-record continuity.
