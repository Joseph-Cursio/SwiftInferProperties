# SwiftInferProperties — v1.16 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.16+. The v1.15 / v1.14 / v1.13 / v1.12 / v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-09 against the V1.16.3 cycle-13 findings commit (`41b57f5`); V1.16.4 working copy.
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.15 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.493s | 75% | 0.493s (0.0%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.475s | 26% | 1.479s (-0.3%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | 1.410s | 53% | 1.398s (+0.9%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 1.231s | 69% | 1.217s (+1.2%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.105s | 79% | 0.102s (+2.9%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 134.8 MB local | 83% | 134.2 MB (+0.4%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.024s | 98% | 0.024s (0.0%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "/<funcName>\(\)"`. CI may show different absolute numbers — the §13 contract gates regression magnitude, not absolute parity.

## Notes on movement vs v1.15

**All seven rows within ±2.9% of v1.15.** All deltas are sub-noise-floor:
- Row 3 at +2.9% (0.102s → 0.105s) — 3ms on a 100ms-precision-class measurement.
- Row 2 at +1.2% (1.217s → 1.231s) — 14ms on a ~1.2s wall measurement.
- Row 1c at +0.9% (1.398s → 1.410s) — 12ms on a ~1.4s wall measurement.
- Rows 1a / 1b / 4 / 5 within ±0.5% of v1.15.

**Row 4 (memory delta) effectively unchanged at 134.8 MB (+0.4%).** V1.16.1's two new SetAlgebra-shape veto helpers (round-trip + idempotence) are upstream of `Suggestion` construction — the 6 newly-suppressed OC HashTable claims don't allocate Suggestion structs. Same posture as V1.10.1 (idempotence direction-counter) / V1.11.1 (inverse-pair direction-counter) / V1.12.1 (round-trip direction-counter) / V1.14.1 (SetAlgebra-shape inverse-pair) / V1.15.1 (domain-marker counter on three templates); same predicted (and observed) marginal memory profile. Six suppressions vs cycle-9's thirty-one don't move the dial because the upstream-skip is constant-cost-per-skip.

**The cycle-13 corpus measurements (`docs/calibration-cycle-13-data/post-setalgebra-extension-*.discover.txt`) provide independent confirmation of per-corpus cost.** All four corpus discovers ran under the same debug binary in single-digit seconds; no regression-class slowdowns observed. Cycle-13 capture also produced a substantively *smaller* output (229 vs 235 suggestions) — V1.16.1 is net-faster on OC SetAlgebra-heavy corpora because suppressed candidates skip the downstream Suggestion construction + ExplainabilityBlock formatting.

## Budget changes vs v1.15

**None at v1.16.0.** The V1.6.1 maintenance patch's flake-resistant budget bumps for Row 2 (4.0s) + the 100-file pipeline integration test (6.0s) carry forward unchanged.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` for v1.16 captured `peakDeltaMB=134.8 baselineMB=51.5 budgetMB=800.0`.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.15.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower.

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation and update the **Measured** column. v1.16 has no re-baselining log — V1.16.1's two new vetoes add two Set membership checks + two `isSelfTypedBinaryOp` calls per candidate per template (one each for round-trip + idempotence); constant-cost-per-skip and constant-cost-per-pass. The hoist of `isSelfTypedBinaryOp(_:)` from `InversePairSetAlgebraShapeGate.swift`'s private helper to `SwiftInferCore.SetAlgebraShape` is byte-equivalent at runtime (just a different declaration site).
