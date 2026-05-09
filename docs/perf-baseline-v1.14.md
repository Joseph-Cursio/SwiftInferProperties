# SwiftInferProperties — v1.14 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.14+. The v1.13 / v1.12 / v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-09 against the V1.14.3 cycle-11 findings commit (`f1a6a96`); V1.14.4 working copy.
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.13 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.495s | 75% | 0.494s (+0.2%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.479s | 26% | 1.468s (+0.7%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | 1.416s | 53% | 1.402s (+1.0%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 1.220s | 70% | 1.221s (-0.1%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.103s | 79% | 0.101s (+2.0%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 134.8 MB local | 83% | 135.9 MB (-0.8%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.024s | 98% | 0.025s (-4.0%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "/<funcName>\(\)"`. CI may show different absolute numbers — the §13 contract gates regression magnitude, not absolute parity.

## Notes on movement vs v1.13

**All seven rows within ±4.0% of v1.13.** Largest delta is Row 5 at -4.0% (1ms drop on a 25ms wall measurement); sub-noise-floor at this precision class. Most rows held to within ±2%:
- Row 5 at -4.0% (0.025s → 0.024s) — single-ms 1ms-precision noise; same posture as v1.10's similar Row 5 movements.
- Row 3 at +2.0% (0.101s → 0.103s) — sub-noise-floor at this precision class.
- Row 1c at +1.0% (1.402s → 1.416s) — 14ms on a ~1.4s wall measurement; well below noise floor.
- Rows 1a / 1b / 2 / 4 within ±1% of v1.13.

**Row 4 (memory delta) effectively unchanged at 134.8 MB (-0.8%).** V1.14.1's SetAlgebra-shape veto is upstream of `Suggestion` construction — the 6 newly-suppressed OC inverse-pair claims don't allocate Suggestion structs. Same posture as V1.10.1 (idempotence direction-counter) / V1.11.1 (inverse-pair direction-counter) / V1.12.1 (round-trip direction-counter); same predicted (and observed) marginal memory profile. Six suppressions vs cycle-9's thirty-one don't move the dial because the upstream-skip is constant-cost-per-skip.

**The cycle-11 corpus measurements (`docs/calibration-cycle-11-data/post-setalgebra-veto-*.discover.txt`) provide independent confirmation of per-corpus cost.** All four corpus discovers ran under the same debug binary in single-digit seconds; no regression-class slowdowns observed. Cycle-11 capture also produced a substantively *smaller* output (251 vs 257 suggestions) — V1.14.1 is net-faster on inverse-pair-heavy corpora because suppressed candidates skip the downstream Suggestion construction + ExplainabilityBlock formatting.

## Budget changes vs v1.13

**None at v1.14.0.** The V1.6.1 maintenance patch's flake-resistant budget bumps for Row 2 (4.0s) + the 100-file pipeline integration test (6.0s) carry forward unchanged.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` for v1.14 captured `peakDeltaMB=134.8 baselineMB=51.2 budgetMB=800.0`.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.13.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower.

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation and update the **Measured** column. v1.14 has no re-baselining log — V1.14.1's veto is constant-cost (two Set membership checks + two `String == "Self"` comparisons per inverse-pair candidate).
