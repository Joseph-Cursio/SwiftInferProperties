# SwiftInferProperties — v1.31 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.31.C commit. v1.31 ships three small additions:
- V1.31.A: `FloatingPointEquatableTypes` curated set (12 entries) + detector helper (~3 string operations per call).
- V1.31.B: `EqualityKind` enum + helper `equalityExpression` (one switch).
- V1.31.C: `InteractiveTriage.equalityKind` + `CheckPropertyMacro` lookups — one curated-set query per accept gesture.

Per-call cost: **emission only** (no discover-time impact). The `FloatingPointEquatableTypes` lookup runs once per accepted suggestion (typically <50 picks per discover); aggregate <1ms across the cycle-1..14 corpora.

| Row | Workload | Budget | Measured (v1.31) | Δ vs v1.29 |
|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | within budget | within noise band (zero discover-time impact) |
| 4 | 500-file resident-memory | < 800 MB | 143-152 MB peak Δ | within noise band |

Test-suite measurement at V1.31.C commit: **1959 tests** passing across **270 suites**, full `swift test` completes in ~3.9s. All §13 budgets hold; v1.31 additions touch only the emission paths (no inference-time changes).

v1.31 baseline replaces v1.29 as the comparison anchor for v1.32+.
