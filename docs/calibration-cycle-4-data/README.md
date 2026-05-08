# v1.7 Calibration Cycle 4 — Empirical Data

Captured: 2026-05-08. swift-infer at `231ae16` (V1.7.1 — stdlib-conformance bake-in).

Re-runs the cycle-1+2+3 corpora with the v1.7.1 stdlib bake-in active. Cycle-3's post-filter snapshots are the diff target; cycle-4 captures the suppression delta vs that baseline.

## Attribution note — what changed between cycle-3 and cycle-4

The cycle-3 capture (V1.6.2 commit `309c404`) preceded **three** orthogonal cycle-4 maintenance patches that landed in the v1.6.1 patch series, plus V1.7.1. So cycle-4's delta vs cycle-3 attributes to:

| Patch | Effect on counts | Empirical effect (cycle-4 vs cycle-3) |
|---|---|---|
| **V1.6.1.1** (math-library op-name gate extension) | `pow` / `**` added to `IdentityElementPairing.stdlibBinaryOperators` | **−1** ComplexModule identity-element (`(zero, pow)` × `Complex.zero` filtered) |
| **V1.6.1.2** (citation determinism) | Sort `inheritedTypes` before scanning | 0 (no count change; only Decisions.json field stability) |
| **V1.6.1.3** (perf budget widening) | Test budgets only | 0 (no production impact) |
| **V1.7.1** (stdlib-conformance bake-in) | `inheritedTypesIndex(...)` now seeds with 14 stdlib types' conformances | **−23** round-trip suppressions (22 OrderedCollections + 1 Algorithms via `Int: Codable` / `Double: Codable` / `UInt64: Codable`) |
| **Total** | | **−24** |

V1.7.1 is the structural deliverable for v1.7. The −23 round-trip suppressions attribute cleanly to it.

## Corpora

Same four cycle-1+2+3 targets, same `--target X --include-possible` invocation:

| Corpus | Target | Cycle-3 post-filter baseline | Cycle-4 post-bakein snapshot |
|---|---|---|---|
| swift-collections | OrderedCollections | [`../calibration-cycle-3-data/post-filter-swift-collections-OrderedCollections.discover.txt`](../calibration-cycle-3-data/post-filter-swift-collections-OrderedCollections.discover.txt) | [`post-bakein-swift-collections-OrderedCollections.discover.txt`](post-bakein-swift-collections-OrderedCollections.discover.txt) |
| swift-numerics | ComplexModule | [`../calibration-cycle-3-data/post-filter-swift-numerics-ComplexModule.discover.txt`](../calibration-cycle-3-data/post-filter-swift-numerics-ComplexModule.discover.txt) | [`post-bakein-swift-numerics-ComplexModule.discover.txt`](post-bakein-swift-numerics-ComplexModule.discover.txt) |
| swift-algorithms | Algorithms | [`../calibration-cycle-3-data/post-filter-swift-algorithms-Algorithms.discover.txt`](../calibration-cycle-3-data/post-filter-swift-algorithms-Algorithms.discover.txt) | [`post-bakein-swift-algorithms-Algorithms.discover.txt`](post-bakein-swift-algorithms-Algorithms.discover.txt) |
| SwiftPropertyLaws | PropertyLawKit | [`../calibration-cycle-3-data/post-filter-SwiftPropertyLaws-PropertyLawKit.discover.txt`](../calibration-cycle-3-data/post-filter-SwiftPropertyLaws-PropertyLawKit.discover.txt) | [`post-bakein-SwiftPropertyLaws-PropertyLawKit.discover.txt`](post-bakein-SwiftPropertyLaws-PropertyLawKit.discover.txt) |

## Aggregate suppression delta

| Corpus | Cycle-3 total | Cycle-4 total | Δ |
|---|---:|---:|---:|
| swift-collections / OrderedCollections | 101 | 79 | **−22** |
| swift-numerics / ComplexModule | 167 | 166 | **−1** |
| swift-algorithms / Algorithms | 75 | 74 | **−1** |
| SwiftPropertyLaws / PropertyLawKit | 7 | 7 | 0 |
| **Total** | **350** | **326** | **−24 (−6.9%)** |

Cumulative across cycles 1–4: total surface 1167 → 326 (−72.1% over three calibration cycles).

## Per-template breakdown

### swift-collections / OrderedCollections — the headline corpus

| Template | Cycle-3 | Cycle-4 | Δ |
|---|---:|---:|---:|
| idempotence | 27 | 27 | 0 |
| **round-trip** | **25** | **3** | **−22** |
| monotonicity | 20 | 20 | 0 |
| commutativity | 10 | 10 | 0 |
| associativity | 10 | 10 | 0 |
| inverse-pair | 9 | 9 | 0 |

The 22 suppressed round-trip pairs all had stdlib-typed primary types — 21 `(Int) -> Int` pairs + 1 `(UInt64) -> Int?` pair. All resolve through V1.7.1's `Int: Codable` / `UInt64: Codable` bake-in to the existing V1.5.2 round-trip coverage veto on `[codableRoundTrip]`. The 3 surviving round-trip suggestions are on user types not in the bake-in: 1 on `Bucket` (custom struct), 2 on `Self` (generic Self-type).

### swift-numerics / ComplexModule

| Template | Cycle-3 | Cycle-4 | Δ |
|---|---:|---:|---:|
| round-trip | 136 | 136 | 0 |
| idempotence | 17 | 17 | 0 |
| commutativity | 6 | 6 | 0 |
| associativity | 6 | 6 | 0 |
| **identity-element** | **2** | **1** | **−1** |

The −1 identity-element suppression is `(zero, pow)` × `Complex.zero` — V1.6.1.1's math-library op-name gate extension catches it (`pow` now in `stdlibBinaryOperators`). The remaining survivor is `(zero, rescaledDivide)` × `Complex.zero`, still outside the curated stdlib-operator gate. Round-trip 0 delta because `Complex` isn't in V1.7.1's stdlib bake-in (it's a user type, and the corpus already declared `Complex: Codable` in cycle-2's textual scan).

### swift-algorithms / Algorithms

| Template | Cycle-3 | Cycle-4 | Δ |
|---|---:|---:|---:|
| idempotence | 44 | 44 | 0 |
| **round-trip** | **20** | **19** | **−1** |
| inverse-pair | 6 | 6 | 0 |
| monotonicity | 3 | 3 | 0 |
| commutativity | 1 | 1 | 0 |
| associativity | 1 | 1 | 0 |

The −1 round-trip suppression is a `(Double) -> Double` pair — caught by V1.7.1's `Double: Codable` bake-in. The 19 surviving round-trip suggestions are mostly `(Index) -> Index` and `(Base.Index) -> Base.Index` — generic associated types that aren't in the stdlib bake-in.

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-3 | Cycle-4 | Δ |
|---|---:|---:|---:|
| monotonicity | 6 | 6 | 0 |
| idempotence | 1 | 1 | 0 |

PropertyLawKit had no suggestions on stdlib-typed carriers in cycle-3, so V1.7.1's bake-in has nothing to extend coverage to. The 7 surviving suggestions are on kit types (`Algorithm`, `LawCheckOutcome`, etc.).

## Reproducibility — capture commands

```sh
cd ~/xcode_projects/SwiftInferProperties
swift build -c release  # produces .build/release/swift-infer

# swift-numerics / ComplexModule
cd ~/calibration/swift-numerics
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target ComplexModule --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-4-data/post-bakein-swift-numerics-ComplexModule.discover.txt

# swift-collections / OrderedCollections
cd ~/xcode_projects/swift-collections
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target OrderedCollections --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-4-data/post-bakein-swift-collections-OrderedCollections.discover.txt

# swift-algorithms / Algorithms
cd ~/calibration/swift-algorithms
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target Algorithms --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-4-data/post-bakein-swift-algorithms-Algorithms.discover.txt

# SwiftPropertyLaws / PropertyLawKit
cd ~/xcode_projects/SwiftPropertyLaws
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target PropertyLawKit --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-4-data/post-bakein-SwiftPropertyLaws-PropertyLawKit.discover.txt
```

## Handoff to V1.7.3 (cycle-4 findings writeup)

V1.7.3 reads this data + the cycle-4 surviving surface and writes `docs/calibration-cycle-4-findings.md` documenting:

1. The −22 round-trip suppression on OrderedCollections — the headline empirical effect of V1.7.1's bake-in. Closes the cycle-2 0-delta finding on stdlib-typed carriers.
2. The −1 round-trip suppression on Algorithms — confirms V1.7.1's reach extends to `Double` as well.
3. The −1 identity-element suppression on ComplexModule — attributable to V1.6.1.1's math-library op-name gate (post-cycle-3 patch), not V1.7.1.
4. The continued 0-delta on PropertyLawKit — its surface has no stdlib-typed carriers; V1.7.1 has nothing to extend coverage to. Cycle-5 priority territory (kit-FP template arm or domain-specific suppression).
5. The cumulative trajectory across cycles 1–4: 1167 → 326 (−72.1%) over three calibration cycles.
6. The cycle-5 priority list (FP template arm, Possible-tier sampling triage, surfacedAt plumbing, SemanticIndex).
7. **Open question:** whether the round-trip template's `[codableRoundTrip]` veto candidate is the *correct* coverage signal for stdlib-typed user-defined inverse pairs (e.g., `minimumCapacity(forScale:) ↔ scale(forCapacity:)` are inverses by intent, not Codable round-trips). V1.7.1 inherits V1.5.2's design decision; cycle-5 should re-examine.
