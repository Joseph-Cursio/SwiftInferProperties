# SwiftInferProperties — v1.32 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.32.C commit. v1.32 ships three additions:
- V1.32.A: `TemplatePack` enum + resolver in `SwiftInferCore` — pure data, zero discover-time impact.
- V1.32.B: `templateFilter: Set<String>?` parameter on `TemplateRegistry.discover` — adds one `Set.contains` per suggestion when the filter is non-nil; **zero** check when nil (default).
- V1.32.C: CLI `--packs` flag + config TOML — adds one-shot parsing at startup; not in the per-call hot path.

Per-suggestion cost when filter is active: O(1) hash-set membership check. The aggregate cost across cycle-1..14 corpora (~109 suggestions per default discover) is <0.1ms.

| Row | Workload | Budget | Measured (v1.32) | Δ vs v1.31 |
|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | within budget | within noise band |
| 4 | 500-file resident-memory | < 800 MB | 143–155 MB peak Δ | within noise band |

Test-suite measurement at V1.32.C commit: **1994 tests** passing across **273 suites**, full `swift test` completes in ~3.7s. All §13 budgets hold.

v1.32 baseline replaces v1.31 as the comparison anchor for v1.33+.
