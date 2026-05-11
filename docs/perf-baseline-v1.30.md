# SwiftInferProperties — v1.30 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11. v1.30 is the **seventh empirical-only cycle** — zero `Sources/` changes vs v1.29. Binary-equivalent to v1.29.0 (commit `4eebd43`). The v1.29 baseline therefore carries forward to v1.30 as the comparison anchor.

| Row | Workload | Budget | Measured (v1.29) | v1.30 status |
|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | within budget | carry-forward |
| 4 | 500-file resident-memory | < 800 MB | ~155 MB peak Δ | carry-forward |

All §13 budgets hold trivially — v1.30 makes no code-path changes.

v1.30 baseline replaces v1.29 as the comparison anchor for v1.31+.
