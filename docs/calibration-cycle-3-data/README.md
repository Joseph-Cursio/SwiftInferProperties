# v1.6 Calibration Cycle 3 — Empirical Data

Captured: 2026-05-08. swift-infer at `1bc7039` (v1.5.0 tag) + the V1.6.0–V1.6.1 working copy (V1.6.2 pre-commit). Re-runs the cycle-1 corpora with the v1.6.1 pair-formation skip-list filter active.

## Corpora

Same four cycle-1 + cycle-2 targets, same `--target X --include-possible` invocation:

| Corpus | Target | Cycle-2 post-rule baseline | Cycle-3 post-filter snapshot |
|---|---|---|---|
| swift-collections | OrderedCollections | [`../calibration-cycle-2-data/post-rule-swift-collections-OrderedCollections.discover.txt`](../calibration-cycle-2-data/post-rule-swift-collections-OrderedCollections.discover.txt) | [`post-filter-swift-collections-OrderedCollections.discover.txt`](post-filter-swift-collections-OrderedCollections.discover.txt) |
| swift-numerics | ComplexModule | [`../calibration-cycle-2-data/post-rule-swift-numerics-ComplexModule.discover.txt`](../calibration-cycle-2-data/post-rule-swift-numerics-ComplexModule.discover.txt) | [`post-filter-swift-numerics-ComplexModule.discover.txt`](post-filter-swift-numerics-ComplexModule.discover.txt) |
| swift-algorithms | Algorithms | [`../calibration-cycle-2-data/post-rule-swift-algorithms-Algorithms.discover.txt`](../calibration-cycle-2-data/post-rule-swift-algorithms-Algorithms.discover.txt) | [`post-filter-swift-algorithms-Algorithms.discover.txt`](post-filter-swift-algorithms-Algorithms.discover.txt) |
| SwiftPropertyLaws | PropertyLawKit | [`../calibration-cycle-2-data/post-rule-SwiftPropertyLaws-PropertyLawKit.discover.txt`](../calibration-cycle-2-data/post-rule-SwiftPropertyLaws-PropertyLawKit.discover.txt) | [`post-filter-SwiftPropertyLaws-PropertyLawKit.discover.txt`](post-filter-SwiftPropertyLaws-PropertyLawKit.discover.txt) |

## Aggregate suppression delta

| Corpus | Cycle-2 total | Cycle-3 total | Δ |
|---|---:|---:|---:|
| swift-numerics / ComplexModule | 170 | 167 | **−3** |
| swift-collections / OrderedCollections | 101 | 101 | 0 |
| swift-algorithms / Algorithms | 75 | 75 | 0 |
| SwiftPropertyLaws / PropertyLawKit | 7 | 7 | 0 |
| **Total** | **353** | **350** | **−3 (−0.85%)** |

Cumulative across cycles 1–3: total surface 358 → 350 (−2.2% over two calibration cycles).

## Per-template breakdown (ComplexModule)

| Template | Cycle-2 | Cycle-3 | Δ | Filtered targets |
|---|---:|---:|---:|---|
| identity-element | 5 | 2 | **−3** | `(zero, -)`, `(zero, /)`, `(zero, *)` |
| associativity | 6 | 6 | 0 | — |
| commutativity | 6 | 6 | 0 | — |
| idempotence | 17 | 17 | 0 | — |
| round-trip | 136 | 136 | 0 | — |

The 3 filtered identity-element pairs are exactly the `(kit-blessed-constant, stdlib-operator)` cross-product mismatches V1.6.1's filter targets. They were cycle-2 survivors that v1.5's coverage veto couldn't reach (no kit law applied → no "covered" path).

## Surviving identity-element on ComplexModule (the 2 that didn't get filtered)

```
[Suggestion]
Template: identity-element
Score:    70 (Likely)
  ✓ rescaledDivide(_:_:) (Complex, Complex) -> Complex — Complex+AlgebraicField.swift:48
  ✓ Complex.zero: Complex — Complex+AdditiveArithmetic.swift:19

[Suggestion]
Template: identity-element
Score:    70 (Likely)
  ✓ pow(_:_:) (Complex, Complex) -> Complex — Complex+ElementaryFunctions.swift:423
  ✓ Complex.zero: Complex — Complex+AdditiveArithmetic.swift:19
```

Both survivors have user-named ops (`rescaledDivide`, `pow`) that fall outside V1.6.1's `{+, -, *, /, %}` stdlib-operator gate. The filter was deliberately scoped to *known* stdlib operators per the v1.6 plan's open-decision #1 (skip-list, not allow-list) — extending the gate to math-library names like `pow` is a curated-list decision deferred to cycle-4.

## Trajectory across all 3 cycles — ComplexModule identity-element

| Cycle | Surfaced | Filter applied | Δ from prior |
|---|---:|---|---:|
| 1 (pre-tune) | 6 | none | — |
| 2 (post-coverage-veto, V1.5.2) | 5 | v1.5 coverage veto suppresses `(zero, +)` (covered by `: AdditiveArithmetic`) | −1 |
| 3 (post-pair-formation-filter, V1.6.1) | 2 | v1.6 pair-formation filter skips `(zero, -)`, `(zero, /)`, `(zero, *)` | −3 |

**Cumulative: 6 → 2 (−66.7%) over two calibration cycles.** Cycle-4 priority #1 candidate would be extending the curated stdlib-operator gate to include math-library op names (`pow`, `rescaledDivide`), which would close the remaining 2 → 0.

## Why the other 3 corpora show 0 delta — same v1 textual-only limit as cycle 2

OrderedCollections / Algorithms / PropertyLawKit had 0 identity-element hits in cycle-2 (per the per-template breakdown), so v1.6's filter has nothing to filter on these corpora. The 0 delta reflects:

- Their identity-element pre-filter surface was already empty (no `(T, T) -> T` ops paired with same-typed kit-blessed `let X: T` constants).
- v1.6's filter doesn't extend to commutativity / associativity / idempotence / monotonicity / round-trip / inverse-pair templates — those are scoped to v1.5's coverage veto + cycle-2's textual-only limitation (corpora's candidate types aren't *declared* in the corpus's source, so `inheritedTypesByName` lookup misses).

This is the same headline limitation finding from cycle 2: textual-only protocol-coverage + textual-only pair-formation filter can't reach into stdlib's own conformance/operator graph. SemanticIndex (PRD §20) would unblock both.

## Reproducibility — capture commands

```sh
cd ~/xcode_projects/SwiftInferProperties
swift build -c release  # produces .build/release/swift-infer

# swift-numerics / ComplexModule
cd ~/calibration/swift-numerics
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target ComplexModule --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-3-data/post-filter-swift-numerics-ComplexModule.discover.txt

# swift-collections / OrderedCollections
cd ~/calibration/swift-collections
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target OrderedCollections --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-3-data/post-filter-swift-collections-OrderedCollections.discover.txt

# swift-algorithms / Algorithms
cd ~/calibration/swift-algorithms
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target Algorithms --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-3-data/post-filter-swift-algorithms-Algorithms.discover.txt

# SwiftPropertyLaws / PropertyLawKit
cd ~/xcode_projects/SwiftPropertyLaws
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target PropertyLawKit --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-3-data/post-filter-SwiftPropertyLaws-PropertyLawKit.discover.txt
```

## Handoff to V1.6.3 (cycle-3 findings writeup)

V1.6.3 reads this data + the cycle-3 surviving surface and writes `docs/calibration-cycle-3-findings.md` documenting:

1. The −3 surgical reduction on ComplexModule identity-element and what it represents (cross-product mismatch elimination).
2. The 6 → 2 cumulative trajectory across cycles 1–3 on ComplexModule identity-element, demonstrating how v1.5's coverage veto + v1.6's pair-formation filter compose.
3. The two surviving user-named-op pairs (`pow`, `rescaledDivide`) that the v1.6 filter doesn't reach — the natural cycle-4 extension target.
4. The continued 0-delta on the other three corpora and why v1.6 doesn't address that limitation (different mechanism — cycle-3 priority #2 stdlib-conformance bake-in is the matching fix).
