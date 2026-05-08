# SwiftInferProperties — v1.11 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.11+. The v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-08 against the V1.11.3 cycle-8 findings commit (`a772c58`); V1.11.4 working copy.
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.10 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.523s | 74% | 0.521s (+0.4%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.484s | 26% | 1.478s (+0.4%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | 1.424s | 53% | 1.423s (+0.1%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 1.235s | 69% | 1.238s (-0.2%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.106s | 79% | 0.104s (+1.9%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 136.4 MB local | 83% | 134.3 MB (+1.6%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.025s | 97% | 0.026s (-3.8%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "/<funcName>\(\)"`. CI may show different absolute numbers — the §13 contract gates regression magnitude, not absolute parity.

## Notes on movement vs v1.10

**All seven rows within ±5% of v1.10.** The largest deltas:
- Row 5 at -3.8% (26ms → 25ms) — single-shot wall measurement with 1ms precision; ±1ms is sub-noise-floor.
- Row 3 at +1.9% (104ms → 106ms) — same precision class.
- Row 4 at +1.6% (134.3 MB → 136.4 MB) — single-shot mach_task_basic_info poll; baselineMB shifted 50.7 → 50.8 (process-startup variance).

All other rows (1a / 1b / 1c / 2) within ±0.4% of v1.10.

**Row 4 (memory delta) effectively unchanged at 136.4 MB.** V1.11.1's counter-signal is upstream of `Suggestion` construction — the 8 newly-suppressed inverse-pair claims don't allocate Suggestion structs. Same posture as V1.10.1's idempotence counter; same predicted (and observed) marginal memory profile.

**Other rows (1a / 1b / 1c / 2 / 3 / 5) within ±2% of v1.10.** The V1.11.1 counter-signal helper is two Set membership checks (`directionLabels.contains(forwardLabel)` + `directionLabels.contains(reverseLabel)`) per `InversePairTemplate.suggest(...)` call — sub-microsecond per call, well below the noise floor on any of these workloads (synthetic corpora have very few inverse-pair candidate pairs; the helper fires at most a handful of times across the entire 50/100/500-file workloads).

**The cycle-8 corpus measurements (`docs/calibration-cycle-8-data/post-inverse-direction-counter-*.discover.txt`) provide independent confirmation of per-corpus cost.** All four corpus discovers ran under the same debug binary in single-digit seconds (mostly under 30s for the largest, OrderedCollections); no regression-class slowdowns observed. Cycle-8 capture also produced a substantively *smaller* output (288 vs 296 suggestions) — V1.11.1 is net-faster on inverse-pair-heavy corpora because suppressed candidates skip the downstream Suggestion construction + ExplainabilityBlock formatting.

## Budget changes vs v1.10

**None at v1.11.0.** The V1.6.1 maintenance patch's flake-resistant budget bumps for Row 2 (4.0s) + the 100-file pipeline integration test (6.0s) carry forward unchanged.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` for v1.11 captured `peakDeltaMB=136.4 baselineMB=50.8 budgetMB=800.0`.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.10.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower.

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation and update the **Measured** column. v1.11 has no re-baselining log — V1.11.1's counter-signal is constant-cost (two Set membership checks per inverse-pair candidate).
