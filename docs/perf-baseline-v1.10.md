# SwiftInferProperties — v1.10 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.10+. The v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-08 against the V1.10.3 cycle-7 capture commit (`4828f9b`); V1.10.4 working copy.
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.8 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.521s | 74% | 0.520s (+0.2%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.478s | 26% | 1.485s (-0.5%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | 1.423s | 53% | 1.423s (0.0%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 1.238s | 69% | 1.240s (-0.2%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.104s | 79% | 0.105s (-1.0%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 134.3 MB local | 83% | 134.5 MB (-0.1%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.026s | 97% | 0.024s (+8.3%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "/<funcName>\(\)"`. CI may show different absolute numbers — the §13 contract gates regression magnitude, not absolute parity.

## Notes on movement vs v1.8/v1.9

**Six of seven rows within ±5% of v1.8.** The one outlier is Row 5 at +8.3% (24ms → 26ms). Per the prior cycles' documentation:
- v1.4 → v1.3 was -4.0%
- v1.5 → v1.4 was +4.2%
- v1.6 → v1.5 was 0%
- v1.7 → v1.6 was +4.2%
- v1.8 → v1.7 was -4.0%
- v1.9 (carry-forward from v1.8)
- **v1.10 → v1.8: +8.3%**

Row 5 is a single-shot wall measurement with 1ms precision on a 24-26ms test; ±2-3ms noise crosses the 5% band easily. The hard 1.0s budget gives 97% headroom. **Documenting as machine-thermal noise; v1.11+ commits gate against 0.026s.**

**Row 4 (memory delta)** effectively unchanged at 134.3 MB (-0.1%) vs v1.8's 134.5. Direction matches the v1.10 plan's V1.10.4 prediction note: V1.10.1's counter-signal is upstream of Suggestion construction, so the 53 newly-suppressed idempotence claims don't allocate Suggestion structs. Net effect is a marginal memory *decrease* — exactly what the suppression mechanism predicts at small magnitude.

**Other rows (Row 1a/1b/1c/2/3) — within ±1% of v1.8.** The counter-signal helper is a Set membership check (`directionLabels.contains(label)`) per `IdempotenceTemplate.suggest(...)` call — sub-microsecond per call, well below the noise floor.

**The cycle-7 corpus measurements (`docs/calibration-cycle-7-data/post-direction-counter-*.discover.txt`) provide independent confirmation of per-corpus cost.** All four corpus discovers ran under the same release binary in single-digit seconds; the cycle-7 capture didn't reveal any regression-class slowdowns — and produced a substantively *smaller* output (296 vs 349 suggestions) because of suppression.

## Budget changes vs v1.9

**None at v1.10.0.** The V1.6.1 maintenance patch's flake-resistant budget bumps for Row 2 (4.0s) + the 100-file pipeline integration test (6.0s) carry forward.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` for v1.10 captured `peakDeltaMB=134.3 baselineMB=50.7 budgetMB=800.0`.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.9.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower.

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation and update the **Measured** column. v1.10 has no re-baselining log — V1.10.1's counter-signal is constant-cost.
