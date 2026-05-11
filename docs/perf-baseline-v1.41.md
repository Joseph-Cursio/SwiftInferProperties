# SwiftInferProperties — v1.41 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.41.A commit. v1.41 refactors `RefactorClusterAnalyzer.classify` to a two-layer dominant-pattern rule. Cost delta: one additional `Dictionary` reduce + filter over the algebraic-template set per classify call. Sub-microsecond per cluster; negligible.

Test-suite measurement: **2103 tests** passing across **293 suites**, full `swift test` completes in ~3.9s. All §13 budgets hold.

v1.41 baseline replaces v1.40 as the comparison anchor for v1.42+.
