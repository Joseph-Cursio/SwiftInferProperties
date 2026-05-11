# SwiftInferProperties — v1.33 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.33.D commit. v1.33 ships infrastructure additions that don't touch the `discover` hot path:
- V1.33.A: `SemanticIndexEntry` data model — pure data, no discover-time code path.
- V1.33.B: `IndexStore` JSON load/save/upsert — invoked by `index` subcommand only.
- V1.33.C: `swift-infer index` subcommand — re-uses `Discover.collectVisibleSuggestions`; per-entry projection is O(1) per suggestion.
- V1.33.D: `swift-infer query` subcommand — reads + filters the index; pure in-memory work after JSON decode.

**Zero discover-time impact.** The `discover` / `drift` / `metrics` / `convert-counterexample` subcommands are unchanged.

| Row | Workload | Budget | Measured (v1.33) | Δ vs v1.32 |
|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | within budget | within noise band (zero discover-time impact) |
| 4 | 500-file resident-memory | < 800 MB | 143–155 MB peak Δ | within noise band |

Test-suite measurement at V1.33.D commit: **2027 tests** passing across **277 suites**, full `swift test` completes in ~4.4s. All §13 budgets hold.

**Index file size (informational).** A ComplexModule discover (20 suggestions) writes a ~9KB `.swiftinfer/index.json`. Per-entry overhead ≈ 450 bytes (well-suited to git-tracked configuration files; SQLite migration only motivated at much higher scale).

v1.33 baseline replaces v1.32 as the comparison anchor for v1.34+.
