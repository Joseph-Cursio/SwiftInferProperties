# SwiftInferProperties — v1.35 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.35.B commit. v1.35 ships:
- V1.35.A: `RefactorClusterAnalyzer` — pure-function classifier over `[SemanticIndexEntry]`. O(N) grouping + O(K) classification per type (K ≤ 5 priority checks).
- V1.35.B: `suggest-refactors` subcommand — reads index from disk, runs analyzer, renders.

**Zero discover/index hot-path impact.** The analyzer runs at `suggest-refactors` invocation time, not during `discover` or `index`. The CLI subcommand surface adds one entry to the AsyncParsableCommand list; runtime cost is the load+filter+render path only when the user invokes it.

| Row | Workload | Budget | Measured (v1.35) | Δ vs v1.34 |
|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | within budget | within noise band (no change) |
| 4 | 500-file resident-memory | < 800 MB | within budget | within noise band |

**`suggest-refactors` cost (informational)**: on the OrderedCollections 74-entry index, analyze + render completes in ~5ms wall time. Negligible at the user-invocation scale.

Test-suite measurement at V1.35.B commit: **2059 tests** passing across **279 suites**, full `swift test` completes in ~3.7s. All §13 budgets hold.

v1.35 baseline replaces v1.34 as the comparison anchor for v1.36+.
