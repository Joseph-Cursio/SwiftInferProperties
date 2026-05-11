# SwiftInferProperties — v1.29 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.29.C commit. v1.29 ships three small Sources/ changes:
- V1.29.A: one additional conditional branch in `InversePairDirectionLabelCounter.directionLabelCounterSignal` (~5 string-prefix checks).
- V1.29.B: one new curated-set lookup in `IdentityElementTemplate.algebraicFamilyMismatchVeto` (~2 hash-set checks).
- V1.29.C: signal-magnitude change only (`-25` → `Signal.vetoWeight`); zero per-call cost change.

Per-call cost: ≤7 additional hash-set / string-prefix checks. O(1) per suggestion. Expected delta vs v1.27 baseline: ≤+5% wall time.

| Row | Workload | Budget | Measured (v1.29) | Δ vs v1.27 |
|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | within budget | within noise band |
| 4 | 500-file resident-memory | < 800 MB | ~155 MB peak Δ | within noise band |

Test-suite measurement at V1.29.C commit: 1923 tests passing across 267 suites, full `swift test` completes in ~3.7s. All §13 budgets hold; the three small mechanism additions add negligible per-call overhead.

v1.29 baseline replaces v1.27 as the comparison anchor for v1.30+.
