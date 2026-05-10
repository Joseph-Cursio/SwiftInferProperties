# SwiftInferProperties — v1.17 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.17+. The v1.16 / v1.15 / v1.14 / v1.13 / v1.12 / v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-09 against the V1.17.3 cycle-14 findings commit (`b45dccf`); V1.17.4 working copy.
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## Carry-forward from v1.16

**v1.17 ships zero behavior change — and zero code change.** Unlike v1.13 (which carried forward from v1.12 because V1.13.1 was a pure-refactor hoist), v1.17 carries forward from v1.16 because **v1.17 is empirical-only**: V1.17.0 opened the cycle-14 plan, V1.17.1 wrote the cycle-14 triage rubric, V1.17.2 wrote the 50-decision triage data, V1.17.3 wrote the cycle-14 findings, and V1.17.4 (this doc) records the perf carry-forward. None of those touch `Sources/` or any test target. The v1.17 binary is byte-identical to v1.16.0.

**No re-measurement required.** Per PRD §13, the contract gates regression magnitude. A documentation-only release that produces a byte-identical CLI cannot move §13 measurements. v1.17's baseline is therefore the v1.16 baseline carried forward.

| Row | Workload | Budget | Measured (v1.16 carry-forward) | Headroom | Test |
|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.493s | 75% | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.475s | 26% | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | 1.410s | 53% | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 1.231s | 69% | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.105s | 79% | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 134.8 MB local | 83% | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.024s | 98% | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers carried forward verbatim from `docs/perf-baseline-v1.16.md`. CI-side measurements at the v1.17.0 release commit will land in single-shot bands consistent with cycle-12-cycle-13's observed precision (~±5% on the half-second-class wall measurements; sub-noise-floor on Row 5's millisecond-class).

## Notes on the carry-forward posture

**Why v1.17 doesn't re-measure:**
- v1.17 changes zero `Sources/` files and zero test files. The CLI binary is byte-identical to v1.16.0 (same swift-infer commit content; only the version-string macro will change at V1.17.5).
- §13 measures wall-clock + memory deltas; both are downstream of the suggestion-stream, which is byte-identical (no scoring-pipeline change, no template change, no curated-set change).
- The cycle-13 capture (`docs/calibration-cycle-13-data/post-setalgebra-extension-*.discover.txt`) IS the v1.16 = v1.17 surface — 229 candidates across the 4 corpora, all reproducible at the V1.17.4 commit by re-running `swift-infer discover --include-possible` on the cycle-1..12 corpora.

**What would invalidate the carry-forward:**
- A V1.17.x patch that touches `Sources/` (any file). v1.17 by-design does not.
- A V1.17.x patch that adds or modifies a test target. v1.17 by-design does not (test count stays at 1618).
- A retroactive change to the v1.16.0-tag-equivalent that this carry-forward is anchored on. The v1.16.0 tag is immutable.

None apply at v1.17.0. If V1.17.x patches accumulate before v1.18 cuts, V1.18.4 should re-measure and replace this carry-forward note with fresh measurements.

## Budget changes vs v1.16

**None at v1.17.0.** The V1.6.1 maintenance patch's flake-resistant budget bumps for Row 2 (4.0s) + the 100-file pipeline integration test (6.0s) carry forward unchanged.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` for v1.16 captured `peakDeltaMB=134.8 baselineMB=51.5 budgetMB=800.0`; v1.17 carries forward.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.16.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower.

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation and update the **Measured** column. v1.17 has no re-baselining log — v1.17 is the loop's second empirical-only release (after v1.9 = cycle 6); the equivalent posture at v1.9 also carried forward perf from v1.8 with no re-measurement.
