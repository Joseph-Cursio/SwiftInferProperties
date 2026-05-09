# SwiftInferProperties — v1.15 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.15+. The v1.14 / v1.13 / v1.12 / v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-09 against the V1.15.3 cycle-12 findings commit (`7f8d98f`); V1.15.4 working copy.
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.14 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.493s | 75% | 0.495s (-0.4%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.479s | 26% | 1.479s (0.0%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | 1.398s | 53% | 1.416s (-1.3%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 1.217s | 70% | 1.220s (-0.2%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.102s | 80% | 0.103s (-1.0%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 134.2 MB local | 83% | 134.8 MB (-0.4%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.024s | 98% | 0.024s (0.0%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "/<funcName>\(\)"`. CI may show different absolute numbers — the §13 contract gates regression magnitude, not absolute parity.

## Notes on movement vs v1.14

**All seven rows within ±1.3% of v1.14.** Flattest cycle-to-cycle baseline movement since v1.13 (which was a no-behavior-change refactor). All deltas are sub-noise-floor:
- Row 1c at -1.3% (1.416s → 1.398s) — 18ms drop on a ~1.4s wall measurement; sub-noise-floor.
- Row 3 at -1.0% (0.103s → 0.102s) — 1ms on a 100ms-precision-class measurement.
- Rows 1a / 1b / 2 / 4 / 5 within ±0.5% of v1.14.

**Row 4 (memory delta) effectively unchanged at 134.2 MB (-0.4%).** V1.15.1's domain-marker counters are upstream of `Suggestion` construction — the 16 newly-suppressed OC HashTable claims don't allocate Suggestion structs. Same posture as V1.10.1 (idempotence direction-counter) / V1.11.1 (inverse-pair direction-counter) / V1.12.1 (round-trip direction-counter) / V1.14.1 (SetAlgebra-shape veto); same predicted (and observed) marginal memory profile. Sixteen suppressions vs cycle-9's thirty-one don't move the dial because the upstream-skip is constant-cost-per-skip.

**The cycle-12 corpus measurements (`docs/calibration-cycle-12-data/post-domain-marker-counter-*.discover.txt`) provide independent confirmation of per-corpus cost.** All four corpus discovers ran under the same debug binary in single-digit seconds; no regression-class slowdowns observed. Cycle-12 capture also produced a substantively *smaller* output (235 vs 251 suggestions) — V1.15.1 is net-faster on OC HashTable-heavy corpora because suppressed candidates skip the downstream Suggestion construction + ExplainabilityBlock formatting.

## Budget changes vs v1.14

**None at v1.15.0.** The V1.6.1 maintenance patch's flake-resistant budget bumps for Row 2 (4.0s) + the 100-file pipeline integration test (6.0s) carry forward unchanged.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` for v1.15 captured `peakDeltaMB=134.2 baselineMB=51.5 budgetMB=800.0`.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.14.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower.

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation and update the **Measured** column. v1.15 has no re-baselining log — V1.15.1's three counters add three Set membership checks per candidate per template (one each for idempotence / round-trip / inverse-pair); constant-cost-per-skip and constant-cost-per-pass.
