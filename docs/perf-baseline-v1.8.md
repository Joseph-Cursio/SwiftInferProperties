# SwiftInferProperties — v1.8 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.8+ — the measured wall numbers (and one resident-memory delta) for every §13 row at the v1.8 commit. Future PRs that move any number more than 25% over the baseline below should be treated as a release blocker per §13's last paragraph. The v1.7 baseline (`docs/perf-baseline-v1.7.md`) is retained for forensic comparison across the cycle-5 calibration trajectory but is no longer the regression gate. The v1.6 (`docs/perf-baseline-v1.6.md`) / v1.5 (`docs/perf-baseline-v1.5.md`) / v1.4 (`docs/perf-baseline-v1.4.md`) / v1.3 (`docs/perf-baseline-v1.3.md`) / v1.2 (`docs/perf-baseline-v1.2.md`) / v1.1 (`docs/perf-baseline-v1.1.md`) / v0.1.0 (`docs/perf-baseline-v0.1.md`) baselines are also retained for the longer trajectory window.

**Captured:** 2026-05-08 against `main` HEAD `06a0741` (V1.8.3 cycle-5 capture commit) + the V1.8.4 working copy.
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.7 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover (all 8 templates active + contradiction pass) | < 2.0s wall | 0.520s | 74% | 0.530s (-1.9%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with `.swiftinfer/decisions.json` load | < 2.0s wall | 1.485s | 26% | 1.523s (-2.5%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` (44 .swift files) | < 3.0s wall (see note) | 1.423s | 53% | 1.431s (-0.6%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files (six detectors + chain-detector pass) | < 4.0s wall (V1.6.1 flake-resistant) | 1.240s | 69% | 1.241s (-0.1%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run after one-file change (10-file corpus) | < 0.5s wall | 0.105s | 79% | 0.104s (+1.0%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB (post-v1.1.0 calibration) | 134.5 MB local | 83% | 135.5 MB (-0.7%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency (5-file corpus) | < 1.0s wall | 0.024s | 98% | 0.024s (0.0%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "/<funcName>\(\)"`. Within-suite parallelism is unchanged from v1.7 (each row was filtered to one test in isolation to remove parallel-suite contention). CI may show different absolute numbers (different runner hardware) — the §13 contract gates regression magnitude, not absolute parity with this baseline.

## Notes on movement vs v1.7

**All seven rows are within ±5% of v1.7 — the v1.8 plan's "flat" projection confirmed.** V1.8.1's shape gate is a 4-comparison constant-time check per round-trip-pair scoring decision (~ns-scale per call); the seeded `codableCodecFormats` set has 2 entries. Net cost is well below the noise floor.

**Row 1a (-1.9%) — v1.7's +7.1% was confirmed as machine-thermal noise.** v1.7 baselined at 0.530s after three repeat measurements at 0.527/0.533/0.536s. v1.8 baselines at 0.520s — within ±2% of v1.6's 0.495s baseline. The thermal-variance hypothesis from v1.7's baseline doc bore out: the 0.530s floor was a cooler-state Apple M1 that returned to the broader 0.49-0.53s envelope. The 25% regression rule operates against the most recent baseline, so v1.9+ commits gate against 0.520s.

**Row 1b (-2.5%), Row 1c (-0.6%), Row 2 (-0.1%):** All within machine-variance. No structural reason for v1.8 to move these — the shape gate adds no work to non-round-trip templates and the 50-file synthetic / DequeModule / TestLifter corpora don't have many round-trip pairs to score.

**Row 3 (+1.0%):** Within machine-variance. The drift re-run reads cached state; v1.8 doesn't touch the drift code path.

**Row 4 (memory delta) effectively unchanged at 134.5 MB (-0.7%) vs v1.7's 135.5 MB.** Direction matches the v1.8 plan's V1.8.4 prediction note ("Row 4 memory may *increase* slightly because re-emerged Suggestions allocate"). Actual outcome is a small *decrease* — the 23 additional Suggestion structs (re-emerged round-trips) are dwarfed by the 500-file synthetic's hundreds of allocations. The -1.0 MB swing is sample-to-sample noise on a 130-MB-scale measurement.

**Row 5 (0.0%):** Identical to v1.7 (24ms == 24ms). Same posture as the prior 4 cycles' Row 5 readings — single-shot precision floor.

**The cycle-5 corpus measurements (`docs/calibration-cycle-5-data/post-tightening-*.discover.txt`) provide an independent confirmation of per-corpus cost.** All four corpus discovers ran under the same release binary in single-digit seconds; the cycle-5 capture didn't reveal any regression-class slowdowns.

## Budget changes vs v1.7

**None at v1.8.0.** The V1.6.1 maintenance patch's flake-resistant budget bumps for Row 2 (4.0s) + the 100-file pipeline integration test (6.0s) carry forward unchanged.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms, capturing the running peak. The reported number is **delta over the pre-discover baseline** sampled immediately before `TemplateRegistry.discover(in:)` runs. The diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` is unconditional on every run — for v1.8 this captured `peakDeltaMB=134.5 baselineMB=50.3 budgetMB=800.0`.

## §13 row 5 — measurement methodology (unchanged from v0.1.0 + v1.1 + v1.2 + v1.3 + v1.4 + v1.5 + v1.6 + v1.7)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. PRD §13 row 5 wording is "after process start"; the ~10ms `main` → `AsyncParsableCommand` dispatch overhead between OS process start and `Discover.run` entry is not testable from inside the package. Open decision #2 in `docs/archive/v0.1.0 Release Plan.md` documents the gap.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. The Swift Testing assertions in each suite use the hard budget as the gate; PR-time soft regression detection (the 25% rule) remains a post-v1.8 concern (would need a checked-in golden of these numbers + a comparison harness; not on the v1.8 critical path — same posture as v0.1.0 + v1.1 + v1.2 + v1.3 + v1.4 + v1.5 + v1.6 + v1.7).

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation, update the **Measured** column above, and reference the commit + the PR that caused the shift in a new "## Re-baselining log" section at the bottom of this file. Do not delete prior measurements — the regression rule operates against the most recent committed baseline.
