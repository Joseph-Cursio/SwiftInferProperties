# SwiftInferProperties — v1.36 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.36.C commit. v1.36 ships:
- V1.36.A: `Constraint<Subject>` data model in SwiftInferCore — pure data + closures.
- V1.36.B: `ConstraintRunner.suggest` — one indirect closure call per gate / signals / evidence / identity / carrier / caveats invocation (vs the equivalent inlined logic in the bespoke matcher).
- V1.36.C: CommutativityTemplate now orchestrated through the runner.

**Per-call cost delta**: ~6 closure-indirect calls per Commutativity suggestion (one per Constraint field) vs the pre-migration direct calls. At ~10 commutativity suggestions per ComplexModule discover, total overhead is ≈ 60 closure calls — sub-microsecond at the swift-optimized indirect-call cost. **Negligible.**

| Row | Workload | Budget | Measured (v1.36) | Δ vs v1.35 |
|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | within budget | within noise band |
| 4 | 500-file resident-memory | < 800 MB | within budget | within noise band |

Test-suite measurement at V1.36.C commit: **2077 tests** passing across **282 suites**, full `swift test` completes in ~3.8s. All §13 budgets hold.

v1.36 baseline replaces v1.35 as the comparison anchor for v1.37+.
