# SwiftInferProperties — v1.28 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11. v1.28 is the **sixth empirical-only cycle** — zero `Sources/` changes vs v1.27. Binary-equivalent to v1.27.0 (commit `287764a`). The v1.27 baseline therefore carries forward to v1.28 as the comparison anchor.

| Row | Workload | Budget | Measured (v1.27) | v1.28 status |
|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | ~0.400s | carry-forward |
| 4 | 500-file resident-memory | < 800 MB | ~136 MB | carry-forward |

All §13 budgets hold trivially — v1.28 makes no code-path changes.

v1.28 baseline replaces v1.27 as the comparison anchor for v1.29+.
