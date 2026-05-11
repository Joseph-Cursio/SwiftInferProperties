# v1.35 Calibration Cycle 32 — Findings (Carrier-Aware Refactor Suggestions)

Captured: 2026-05-11. swift-infer at v1.35 development tip. The thirty-second calibration cycle and the **first user-facing surface built on the v1.34-enriched SemanticIndex**.

## Headline

**Carrier-aware refactor suggestions shipped.** PRD §20.1 motivated the SemanticIndex with API-design feedback (`"you have three monoids; consider unifying them under a custom Monoid protocol"`) and refactoring-suggestion use cases; v1.33 + v1.34 built the data layer; v1.35 ships the user-facing render via a new `swift-infer suggest-refactors` subcommand. **No acceptance-rate re-measurement** — v1.35 is a query/render layer on top of the existing SemanticIndex; per-template inference precision unchanged.

| Metric | Cycle 31 (post-v1.34) | Cycle 32 (post-v1.35) | Δ |
|---|---:|---:|---|
| Surface (default mode) | 109 | 109 | 0 (no inference changes) |
| Acceptance rate | 72.4% (cycle-27 carries) | 72.4% (no re-measurement) | 0pp |
| Mechanism classes | 16 | 16 (no new) | 0 |
| CLI subcommands | 6 | **7** | +1 (`suggest-refactors`) |
| Test count | 2027 | **2059** | +32 |

## What v1.35 ships

Two workstreams:

- **V1.35.A**: `RefactorCluster` + `ClusterShape` + `RefactorClusterAnalyzer` in `SwiftInferCLI`. 5-shape priority-ordered taxonomy (`algebraicStructure` → `idempotenceCluster` → `dualStyleCluster` → `roundTripCluster` → `generalCluster` catch-all). Pure-function analyzer groups index entries by `typeName`, classifies, sorts by size descending. 15 unit tests.

- **V1.35.B**: `swift-infer suggest-refactors` subcommand. Reads `.swiftinfer/index.json`, runs the analyzer, renders human-readable per-cluster output with stable curated suggestion text. CLI flags: `--min-suggestions`, `--shape`, `--limit`, `--directory`, `--index-path`. 17 unit tests including stable curated-text assertions.

## End-to-end verification

### swift-numerics ComplexModule (20 entries)

**1 cluster surfaced**: `[Complex] 20 inferred properties — algebraic-structure cluster`. Template mix: round-trip ×8, associativity ×6, commutativity ×6. The curated `algebraicStructure` suggestion text correctly points at Semigroup / Monoid / CommutativeMonoid / Semilattice conformance.

### swift-collections OrderedCollections (74 entries)

**8 clusters surfaced**:

| Type | Count | Shape | Top templates |
|---|---:|---|---|
| OrderedSet | 29 | algebraic-structure | dual-style ×12, idempotence ×5, monotonicity ×5 |
| OrderedSet.UnorderedView | 8 | dual-style-consistency | dual-style ×8 |
| OrderedDictionary.Elements | 7 | algebraic-structure | assoc ×2, comm ×2, mono ×2 |
| OrderedSet.SubSequence | 6 | algebraic-structure | assoc ×2, comm ×2, mono ×2 |
| OrderedDictionary.Elements.SubSequence | 6 | algebraic-structure | assoc ×2, comm ×2, mono ×2 |
| OrderedDictionary.Values | 6 | algebraic-structure | assoc ×2, comm ×2, mono ×2 |
| _HashTable | 4 | general | mixed |
| _HashTable.UnsafeHandle | 4 | general | mixed |

Five-cycle 100% rate-stability on dual-style-consistency (cycles 17 + 20 + 23 + 25 + 27) is reflected in OrderedSet.UnorderedView's clean `dualStyleCluster` classification.

### swift-algorithms + PropertyLawKit

Both corpora have <8 suggestions and don't surface any clusters at the default `--min-suggestions 3` threshold. Expected — these are small libraries where per-type cluster density is low.

## Classification observations

- **`algebraicStructure` priority is high-recall, low-precision for collection-heavy corpora.** OrderedSet (29 entries) classifies as `algebraicStructure` despite its dominant pattern being dual-style-consistency (12 entries). The priority rules fire on the 2-of-3 algebraic-template match (commutativity ×2 + associativity ×2), but the curated suggestion text is a less-good fit than `dualStyleCluster`'s SetAlgebra-shape prompt would be.
- **Future-cycle refinement candidate**: introduce a "dominant pattern" rule — when one template category accounts for ≥50% of the cluster's count, that category wins over the simple priority order. This would reclassify OrderedSet correctly as `dualStyleCluster`.
- **Nested type names work transparently.** `OrderedDictionary.Elements.SubSequence` and `_HashTable.UnsafeHandle` cluster correctly as distinct carriers, no normalization needed.

## Scope boundaries observed

- **In scope**: index → cluster analysis → render. Per-shape curated suggestion text.
- **Out of scope (deferred)**: cross-type abstraction discovery ("Foo and Bar both have the same shape — extract a protocol"). v1.35 surfaces single-type clusters; cross-type pattern matching is a future cycle.
- **Out of scope (deferred)**: dominant-pattern classification refinement (see "Classification observations" above).
- **Out of scope (per PRD §16 #1)**: writing markers / annotations / code changes. `suggest-refactors` is a read-only render.

## Cycle-33 priority

Per the 4-cycle design-completion plan we discussed: v1.32 → v1.33 → v1.34 → v1.35 → **v1.36 Constraint Engine upgrade (PRD §20.2)** (originally planned as v1.35; pushed to v1.36 by the v1.35 carrier-aware-refactors insertion).

The Constraint Engine replaces "templates as patterns over signatures" with "constraints over a function graph + types + usage." Multi-cycle refactor. The v1 architecture is constraint-engine-ready (PRD §20.2's "the scoring engine can be replaced without touching downstream contracts" guarantee).

v1.36+ candidates from the v1.33 + v1.34 backlog also remain viable:
- Dominant-pattern classification refinement (v1.35 finding)
- Cross-type abstraction discovery (v1.35 deferred)
- Incremental indexing (v1.33 deferred)
- Natural-language query DSL (v1.33 deferred)
- SQLite backend (v1.33 deferred)

## Conclusion

v1.35 closes the v1.33-motivated PRD §20.1 use case ("you have three monoids; consider unifying them under a custom Monoid protocol") with a focused 2-workstream cycle. The carrier-aware refactor surface leverages v1.34's `typeName` enrichment directly — without v1.34, every cluster would have collapsed onto a single `nil`-typeName bucket. The cycle's headline observation: **OrderedCollections surfaces 8 distinct refactor clusters across 6 different carrier types**, validating the SemanticIndex+typeName+RefactorClusterAnalyzer pipeline.

v1.36 Constraint Engine upgrade (PRD §20.2) begins next.
