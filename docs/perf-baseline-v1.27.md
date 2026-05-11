# SwiftInferProperties — v1.27 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.27.B commit. v1.27 ships 2 small Sources/ changes (V1.27.A Sequence-conformance path extension; V1.27.B name-prefix gate on inverse-pair direction-counter). Per-call cost: 2-4 additional hash-set / string-prefix checks. O(1) per suggestion. Expected delta vs v1.25 baseline: ≤+5% wall time.

| Row | Workload | Budget | Measured (v1.27) | Δ vs v1.25 |
|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | ~0.400s | within noise band |
| 4 | 500-file resident-memory | < 800 MB | ~136 MB | within noise band |

All §13 budgets hold. The two small mechanism extensions add negligible per-call overhead; aggregate <0.5ms on a 50-file corpus.

v1.27 baseline replaces v1.25 as the comparison anchor for v1.28+.
