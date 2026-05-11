# SwiftInferProperties — v1.39 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.39 batch-migration commits. v1.39 migrates three additional suggest entry points (RoundTripTemplate + IdempotenceTemplate non-lifted + IdempotenceTemplate lifted) to the Constraint Engine — same per-call cost delta as prior migrations (~6-7 closure-indirect calls per suggestion). The Constraint API extension (`additionalWhySuggested` field) adds one closure invocation per emitted Suggestion; defaults to a constant empty array for the 5 templates migrated in v1.36–v1.38, so prior measurements are not affected.

Test-suite measurement: **2093 tests** passing across **289 suites**, full `swift test` completes in ~3.8s. All §13 budgets hold.

v1.39 baseline replaces v1.38 as the comparison anchor for v1.40.
