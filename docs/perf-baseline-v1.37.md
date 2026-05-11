# SwiftInferProperties — v1.37 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.37.A/B commit. v1.37 migrates one additional template (MonotonicityTemplate) to the Constraint Engine — same per-call cost delta as the V1.36.C Commutativity migration (~6 closure-indirect calls per Monotonicity suggestion vs the pre-migration direct calls).

Test-suite measurement: **2080 tests** passing across **283 suites**, full `swift test` completes in ~3.8s. All §13 budgets hold.

v1.37 baseline replaces v1.36 as the comparison anchor for v1.38+.
