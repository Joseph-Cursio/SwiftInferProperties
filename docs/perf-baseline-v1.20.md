# SwiftInferProperties — v1.20 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.20+. The v1.19 / v1.18 / v1.17 / v1.16 / v1.15 / v1.14 / v1.13 / v1.12 / v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-10 against the V1.20.D cycle-17 findings commit (`fad0ac3`); V1.20.E working copy.
**Hardware:** Mac15,5 (Apple M3 family).
**Toolchain:** Apple Swift 6.2.4, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing.

## Carry-forward from v1.19

**v1.20 ships zero behavior change — and zero code change.** Mirroring v1.17's empirical-only carry-forward posture: V1.20.0 opened the cycle-17 plan, V1.20.A captured the post-v1.19 surface counts (data-only writeout to `docs/calibration-cycle-17-data/`), V1.20.B wrote the cycle-17 triage rubric, V1.20.C wrote the 46-decision triage data, V1.20.D wrote the cycle-17 findings, and V1.20.E (this doc) records the perf carry-forward. None of those touch `Sources/` or any test target. The v1.20 binary is byte-identical to v1.19.0.

**No re-measurement required.** Per PRD §13, the contract gates regression magnitude. A documentation-only release that produces a byte-identical CLI cannot move §13 measurements. v1.20's baseline is therefore the v1.19 baseline carried forward.

| Row | Workload | Budget | Measured (v1.19 carry-forward) | Headroom | Test |
|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.403s | 80% | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.226s | 39% | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | n/a (skipped at v1.19) | n/a | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 0.941s | 76% | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 2 | Discover pipeline on 100 test files | < 6.0s wall | 1.836s | 69% | `TestLifterPerformanceTests.discoverPipelineHundredTestFileBudgetWithM32Pipeline` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.085s | 83% | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 136.3 MB local | 83% | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.019s | 98% | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers carried forward verbatim from `docs/perf-baseline-v1.19.md`. CI-side measurements at the v1.20.0 release commit will land in single-shot bands consistent with v1.18-v1.19's observed precision (~±5% on half-second-class; sub-noise-floor on millisecond-class rows).

## Notes on the carry-forward posture

**Why v1.20 doesn't re-measure:**
- v1.20 changes zero `Sources/` files and zero test files. The CLI binary is byte-identical to v1.19.0 (same swift-infer commit content; only the version-string macro will change at V1.20.F).
- §13 measures wall-clock + memory deltas; both are downstream of the suggestion-stream, which is byte-identical (no scoring-pipeline change, no template change, no curated-set change).
- The V1.20.A capture (`docs/calibration-cycle-17-data/post-v1.19-*.discover.txt`) IS the v1.19 = v1.20 surface — 335 candidates across the 4 corpora, all reproducible at the V1.20.E commit by re-running `swift-infer discover --include-possible` on the cycle-1..14 corpora.

**What would invalidate the carry-forward:**
- A V1.20.x patch that touches `Sources/` (any file). v1.20 by-design does not.
- A V1.20.x patch that adds or modifies a test target. v1.20 by-design does not (test count stays at 1757).
- A retroactive change to the v1.19.0-tag-equivalent that this carry-forward is anchored on. The v1.19.0 tag is immutable.

None apply at v1.20.0. If V1.20.x patches accumulate before v1.21 cuts, V1.21.x should re-measure and replace this carry-forward note with fresh measurements.

## Budget changes vs v1.19

**None at v1.20.0.** The V1.6.1 maintenance patch's flake-resistant budget bumps for Row 2 (4.0s) + the 100-file pipeline integration test (6.0s) carry forward unchanged. v1.18's noise-band flag on Row 1 (50-file synthetic) was resolved at v1.19's hardware migration (M1 → M3 family); v1.20 carries the v1.19 numbers without amendment.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` for v1.19 captured `peakDeltaMB=136.3 baselineMB=53.8 budgetMB=800.0`; v1.20 carries forward.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.19.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower.

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation and update the **Measured** column. v1.20 has no re-baselining log — v1.20 is the loop's third empirical-only release (after v1.9 = cycle 6 and v1.17 = cycle 14); the equivalent posture at v1.17 also carried forward perf from v1.16 with no re-measurement.

v1.21+ is the next planned re-measurement cycle (cycle-18 mechanism work — Iterator-shape suppression on idempotence-lifted + composition-lifted monotone-bounded suppression both ship `Sources/` changes per the cycle-17 findings priority list).
