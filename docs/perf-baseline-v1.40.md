# SwiftInferProperties — v1.40 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.40 batch-migration commits. v1.40 migrates the last 5 suggest entry points to the Constraint Engine, completing the 10-template refactor. Per-call cost is the same ~6 closure-indirect calls per suggestion as prior migrations. The IdentityElement wrapper-pattern variants add one additional Suggestion rebuild per suggestion (struct copy with 7 field reassignments) — sub-microsecond overhead.

Test-suite measurement: **2097 tests** passing across **293 suites**, full `swift test` completes in ~3.9s. All §13 budgets hold.

v1.40 baseline replaces v1.39 as the comparison anchor. **Constraint Engine refactor complete** — future v1.41+ baselines compare against this Constraint-driven matcher rather than the pre-v1.36 bespoke-matcher architecture.
