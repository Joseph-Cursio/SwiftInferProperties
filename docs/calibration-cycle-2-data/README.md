# v1.5 Calibration Cycle 2 — Empirical Data

Captured: 2026-05-08. swift-infer v1.5.2-pre at HEAD `79ad26a` + the V1.5.0–V1.5.2 working copy (V1.5.3 pre-commit). Re-runs the cycle-1 corpora with the v1.5.2 protocol-coverage veto active.

## Corpora

Same four cycle-1 targets, same `--target X --include-possible` invocation:

| Corpus | Target | Cycle-1 post-tune baseline | Cycle-2 post-rule snapshot |
|---|---|---|---|
| swift-collections | OrderedCollections | [`../calibration-cycle-1-data/post-tune-swift-collections-OrderedCollections.discover.txt`](../calibration-cycle-1-data/post-tune-swift-collections-OrderedCollections.discover.txt) | [`post-rule-swift-collections-OrderedCollections.discover.txt`](post-rule-swift-collections-OrderedCollections.discover.txt) |
| swift-numerics | ComplexModule | [`../calibration-cycle-1-data/post-tune-swift-numerics-ComplexModule.discover.txt`](../calibration-cycle-1-data/post-tune-swift-numerics-ComplexModule.discover.txt) | [`post-rule-swift-numerics-ComplexModule.discover.txt`](post-rule-swift-numerics-ComplexModule.discover.txt) |
| swift-algorithms | Algorithms | [`../calibration-cycle-1-data/post-tune-swift-algorithms-Algorithms.discover.txt`](../calibration-cycle-1-data/post-tune-swift-algorithms-Algorithms.discover.txt) | [`post-rule-swift-algorithms-Algorithms.discover.txt`](post-rule-swift-algorithms-Algorithms.discover.txt) |
| SwiftPropertyLaws | PropertyLawKit | [`../calibration-cycle-1-data/post-tune-SwiftPropertyLaws-PropertyLawKit.discover.txt`](../calibration-cycle-1-data/post-tune-SwiftPropertyLaws-PropertyLawKit.discover.txt) | [`post-rule-SwiftPropertyLaws-PropertyLawKit.discover.txt`](post-rule-SwiftPropertyLaws-PropertyLawKit.discover.txt) |

## Aggregate suppression delta

| Corpus | Cycle-1 total | Cycle-2 total | Δ |
|---|---:|---:|---:|
| swift-numerics / ComplexModule | 175 | 170 | **−5** |
| swift-collections / OrderedCollections | 101 | 101 | 0 |
| swift-algorithms / Algorithms | 75 | 75 | 0 |
| SwiftPropertyLaws / PropertyLawKit | 7 | 7 | 0 |
| **Total** | **358** | **353** | **−5 (−1.4%)** |

## Per-template breakdown (ComplexModule, the only corpus with non-zero delta)

| Template | Cycle-1 | Cycle-2 | Δ | Suppressed targets |
|---|---:|---:|---:|---|
| associativity | 8 | 6 | −2 | `+(z:w:)`, `*(z:w:)` |
| commutativity | 8 | 6 | −2 | `+(z:w:)`, `*(z:w:)` |
| identity-element | 6 | 5 | −1 | `+(z:w:)` × `Complex.zero` |
| idempotence | 17 | 17 | 0 | — |
| round-trip | 136 | 136 | 0 | — |

The suppressed surface is the exact set of suggestions whose property is published by `Complex`'s declared conformances:
- `Complex: AdditiveArithmetic` → covers `+`'s commutativity + associativity + `(zero, +)` identity (PropertyLawKit's `checkAdditiveArithmeticPropertyLaws`).
- `Complex: Numeric` → covers `*`'s commutativity + associativity (PropertyLawKit's `checkNumericPropertyLaws`).

The 5 surviving identity-element / commutativity / associativity hits per template (per-row 8 → 6 etc.) are correctly preserved because they don't bind to a kit law:
- `-(z:w:)` / `/(z:w:)` are non-commutative / non-associative ops — bear no kit law regardless of conformance.
- `pow(_:_:)`, `rescaledDivide(_:_:)`, `_relaxedAdd(_:_:)`, `_relaxedMul(_:_:)` are user-named functions not covered by stdlib `+` / `*` laws (cycle-2 op-class fall-through preserves them).

## Why the other 3 corpora show 0 delta — v1 textual-only limitation

The v1.5 veto requires the candidate type's inheritance clauses to appear in the corpus's `typeDecls`. Three corpora's surfaced suggestions land on stdlib-typed parameters (`Int`, generic `Element`, etc.) that the corpus doesn't *declare* — only references. The textual-only protocol-coverage map (V1.5.1 documented limitation) cannot reach into stdlib's own conformance graph.

Specific diagnostics:

- **OrderedCollections — 0 of 101 suppressed:** Most candidates are `index(_:offsetBy:)` / `distance(from:to:)` / etc. typed `(Int, Int) -> Int`. No corpus-declared `: AdditiveArithmetic` on Int (Int is in stdlib, not the corpus). The veto's `inheritedTypesByName["Int"]` is `nil`. Corpus's set-shaped types (`OrderedSet`, `OrderedDictionary`) don't conform to stdlib `: SetAlgebra` either — they implement set-shaped *operations* without inheriting the protocol.
- **Algorithms — 0 of 75 suppressed:** Combinatorial functions are mostly free functions on generic `Element` types. No `inheritedTypesByName` hits.
- **PropertyLawKit — 0 of 7 suppressed:** 1 idempotence + 6 monotonicity hits land on protocol-typed parameters (`Self` in protocol extensions). The veto's lookup against stripped `"Self"` finds nothing.

This is not a v1.5 implementation bug — it's the documented v1 textual-only limit (V1.5.1 type doc, v1.5 plan §"Out of scope"). The cycle-3 SemanticIndex-blocked successor would resolve `Int: Numeric` authoritatively via `lookupConformance`, lifting suppression on these corpora. v1.5's surgical −5 on ComplexModule is the maximum effect achievable within textual-only semantics.

## Reproducibility — capture commands

```sh
cd ~/xcode_projects/SwiftInferProperties
swift build -c release  # produces .build/release/swift-infer

# swift-numerics / ComplexModule
cd ~/calibration/swift-numerics
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target ComplexModule --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-2-data/post-rule-swift-numerics-ComplexModule.discover.txt

# swift-collections / OrderedCollections
cd ~/calibration/swift-collections
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target OrderedCollections --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-2-data/post-rule-swift-collections-OrderedCollections.discover.txt

# swift-algorithms / Algorithms
cd ~/calibration/swift-algorithms
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target Algorithms --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-2-data/post-rule-swift-algorithms-Algorithms.discover.txt

# SwiftPropertyLaws / PropertyLawKit
cd ~/xcode_projects/SwiftPropertyLaws
~/xcode_projects/SwiftInferProperties/.build/release/swift-infer discover \
    --target PropertyLawKit --include-possible \
  > ~/xcode_projects/SwiftInferProperties/docs/calibration-cycle-2-data/post-rule-SwiftPropertyLaws-PropertyLawKit.discover.txt
```

## Handoff to V1.5.4 (cycle-2 findings writeup)

V1.5.4 reads this data + the surviving surface and writes `docs/calibration-cycle-2-findings.md` documenting:

1. The −5 surgical suppression on ComplexModule and what it represents (kit-covered redundancy).
2. The 0-delta on the other 3 corpora and the v1 textual-only limitation that explains it.
3. Cycle-3 hypotheses — operator-aware identity-element pairing at the pair-formation step (suppress `(.zero, *)` etc. before they reach the scorer), and the SemanticIndex sequencing that would unblock stdlib-typed coverage.
