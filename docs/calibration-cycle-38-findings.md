# v1.41 Calibration Cycle 38 — Findings (Dominant-Pattern Classification)

Captured: 2026-05-11. swift-infer at v1.41 development tip. The thirty-eighth calibration cycle.

## Headline

**Closes the v1.35 cycle-32 finding**: OrderedSet's 29-suggestion cluster now classifies as `dual-style-consistency cluster` (the SetAlgebra-shape story) instead of the misleading `algebraicStructure` (the Semigroup/Monoid prompt). Two-layer dominant-pattern rule introduced in `RefactorClusterAnalyzer.classify`:

1. **Algebraic-collective dominance**: 2+ distinct algebraic templates AND their sum ≥50% of total → `algebraicStructure`. Preserves Complex's classification (12/20 = 60%).
2. **Single-template most-numerous wins**: among the per-template shapes meeting their ≥3 threshold, the one with the highest count wins. Reclassifies OrderedSet to `dual-style-consistency cluster` (dual-style 12 > idempotence 5).
3. Catch-all: ≥4 total → `generalCluster`.

The pre-v1.41 priority order (idempotence > dual-style > round-trip) is retained as the **tie-breaker** when two per-template shapes have the same count.

## End-to-end verification

**OrderedCollections (74 entries, 8 clusters)**:

| Type | Pre-v1.41 | Post-v1.41 | Algebraic % | Top-template count |
|---|---|---|---:|---|
| OrderedSet (29) | algebraicStructure | **dualStyleCluster** | 14% | dual-style 12 |
| OrderedSet.UnorderedView (8) | dualStyleCluster | dualStyleCluster | 0% | dual-style 8 |
| OrderedDictionary.Elements (7) | algebraicStructure | algebraicStructure | 57% | (algebraic) |
| OrderedSet.SubSequence (6) | algebraicStructure | algebraicStructure | 67% | (algebraic) |
| OrderedDictionary.Elements.SubSequence (6) | algebraicStructure | algebraicStructure | 67% | (algebraic) |
| OrderedDictionary.Values (6) | algebraicStructure | algebraicStructure | 67% | (algebraic) |
| _HashTable (4) | generalCluster | generalCluster | varies | mixed |
| _HashTable.UnsafeHandle (4) | generalCluster | generalCluster | varies | mixed |

Only OrderedSet changes classification — every other cluster either had clear algebraic dominance (Complex 60%, OrderedDictionary.Elements 57%, etc.) or was already a non-algebraic shape.

**ComplexModule (20 entries, 1 cluster)**: unchanged at `algebraic-structure cluster` (60% algebraic).

## Migration count update

Templates migrated to Constraint Engine: still 10/10 (template-name); 13/13 (suggest entry points). v1.41 is a refinement to `RefactorClusterAnalyzer.classify` only — does not touch any template or the Constraint Engine itself.

| Metric | Cycle 37 (post-v1.40) | Cycle 38 (post-v1.41) | Δ |
|---|---:|---:|---|
| Constraint Engine refactor | 13/13 entry points | 13/13 (no change) | 0 |
| RefactorClusterAnalyzer.classify | priority-order | dominant-pattern | refactored |
| Acceptance rate | 72.4% | 72.4% (no re-measurement) | 0pp |
| Test count | 2097 | **2103** | +6 |

## Cycle-39 priority

User's call from the open paths:

- **Higher-order property composition** (PRD §20.2 lookahead).
- **Project-vocabulary constraint registration**.
- **Cross-type abstraction discovery** (v1.35 deferred).
- **Incremental indexing / natural-language query DSL / SQLite backend** (v1.33 deferred).
- **Test-execution evidence architectural shift** (v1.25 raised).
