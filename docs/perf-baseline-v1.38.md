# SwiftInferProperties — v1.38 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.38 batch-migration commits. v1.38 migrates three additional templates (Associativity, InvariantPreservation, DualStyleConsistency) to the Constraint Engine — same per-call cost delta as the V1.36.C / V1.37.A migrations (~6 closure-indirect calls per suggestion vs the pre-migration direct calls).

Test-suite measurement: **2088 tests** passing across **286 suites**, full `swift test` completes in ~3.9s. All §13 budgets hold.

v1.38 baseline replaces v1.37 as the comparison anchor for v1.39+.
