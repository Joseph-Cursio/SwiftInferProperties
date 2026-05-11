# SwiftInferProperties — v1.26 Performance Baseline

PRD v1.0 §13: 25% regression fails the build.

**v1.26 ships zero behavior change** — v1.25 carry-forward (mirrors v1.20.E + v1.23.E pattern). All §13 rows carry forward verbatim from `docs/perf-baseline-v1.25.md`:

| Row | Budget | v1.25 carry-forward |
|---|---|---|
| 1 (50-file synthetic) | < 2.0s | 0.400s |
| 2 (TestLifter 100 files) | < 4.0s | 0.945s |
| 4 (500-file memory) | < 800 MB | 136.2 MB |

v1.26 binary-equivalent to v1.25.0 — CLI byte-identical; no re-measurement required.

v1.27 = cycle 24 mechanism release; re-measure perf there.
