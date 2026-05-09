# SwiftInferProperties — v1.12 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.12+. The v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-09 against the V1.12.3 cycle-9 findings commit (`72e60c5`); V1.12.4 working copy.
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.11 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.494s | 75% | 0.523s (-5.5%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.468s | 27% | 1.484s (-1.1%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | 1.402s | 53% | 1.424s (-1.5%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 1.221s | 69% | 1.235s (-1.1%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.101s | 80% | 0.106s (-4.7%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 135.9 MB local | 83% | 136.4 MB (-0.4%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.025s | 97% | 0.025s (0.0%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "/<funcName>\(\)"`. CI may show different absolute numbers — the §13 contract gates regression magnitude, not absolute parity.

## Notes on movement vs v1.11

**All seven rows within ±5.5% of v1.11.** Largest delta is Row 1a at -5.5% (29ms drop on a 0.5s wall measurement); well below the 25% hard-gate. Row 3 at -4.7% (5ms drop on a 100ms wall measurement) is sub-noise-floor at this precision. Most rows held to within ±1.5%:
- Row 1a at -5.5% (0.523s → 0.494s) — single-shot wall measurement; 29ms is sub-noise-floor on a half-second timed test (precision ~10ms; -5.5% is at the noise-floor edge but well below the 25% regression gate).
- Row 3 at -4.7% (106ms → 101ms) — same precision class as Row 5; ±5ms is sub-noise-floor.
- Rows 1b / 1c / 2 / 4 / 5 within ±1.5% of v1.11 (effectively unchanged).

**Row 4 (memory delta) effectively unchanged at 135.9 MB.** V1.12.1's counter-signal is upstream of `Suggestion` construction — the 31 newly-suppressed round-trip claims don't allocate Suggestion structs. Same posture as V1.10.1's idempotence counter and V1.11.1's inverse-pair counter; same predicted (and observed) marginal memory profile. Round-trip's larger suppression count (31 vs 8) doesn't move the dial because the upstream-skip is constant-cost-per-skip.

**The cycle-9 corpus measurements (`docs/calibration-cycle-9-data/post-roundtrip-direction-counter-*.discover.txt`) provide independent confirmation of per-corpus cost.** All four corpus discovers ran under the same debug binary in single-digit seconds; no regression-class slowdowns observed. Cycle-9 capture also produced a substantively *smaller* output (257 vs 288 suggestions, the largest single-cycle suppression delta to date) — V1.12.1 is net-faster on round-trip-heavy corpora because suppressed candidates skip the downstream Suggestion construction + ExplainabilityBlock formatting.

## Budget changes vs v1.11

**None at v1.12.0.** The V1.6.1 maintenance patch's flake-resistant budget bumps for Row 2 (4.0s) + the 100-file pipeline integration test (6.0s) carry forward unchanged.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` for v1.12 captured `peakDeltaMB=135.9 baselineMB=51.0 budgetMB=800.0`.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.11.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower.

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation and update the **Measured** column. v1.12 has no re-baselining log — V1.12.1's counter-signal is constant-cost (two Set membership checks per round-trip candidate).
