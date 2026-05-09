# SwiftInferProperties — v1.13 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.13+. The v1.12 / v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-09 against the V1.13.1 hoist commit (`29a0f4e`); V1.13.2 working copy.
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## Carry-forward from v1.12

**v1.13 ships zero behavior change.** V1.13.1 hoists `IdempotenceTemplate.directionLabels` to `SwiftInferCore.DirectionLabels.curated` — a pure site-of-truth refactor. The set's contents, the three template consumers' counter-signal helpers, and the scoring pipeline are all byte-identical to v1.12. The hoist was verified byte-identical against the cycle-9 Algorithms snapshot (`docs/calibration-cycle-9-data/post-roundtrip-direction-counter-swift-algorithms-Algorithms.discover.txt`) at V1.13.1 commit time.

**No re-measurement required.** Per PRD §13, the contract gates regression magnitude. A pure refactor that touches only the *site* of a static let — not its content, not any code path that consults it (the three `.contains($0)` checks are syntactically identical), and not allocation patterns — cannot move §13 measurements. v1.13's baseline is therefore the v1.12 baseline carried forward.

| Row | Workload | Budget | Measured (v1.12 carry-forward) | Headroom | Test |
|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.494s | 75% | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.468s | 27% | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | 1.402s | 53% | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 1.221s | 69% | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.101s | 80% | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 135.9 MB local | 83% | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.025s | 97% | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers carried forward verbatim from `docs/perf-baseline-v1.12.md`. CI-side measurements at the v1.13.0 release commit will land in single-shot bands consistent with cycle-7-cycle-9's observed precision (~±5% on the half-second-class wall measurements; sub-noise-floor on Row 5's millisecond-class).

## Notes on the carry-forward posture

**Why v1.13 doesn't re-measure:**
- V1.13.1 changes only the file location of one `public static let`. Swift compiles the consumer-side `Set.contains($0)` check to an identical SIL representation regardless of which module the set lives in (the access is at static dispatch).
- V1.13.1's byte-stable discover() verification on the Algorithms corpus already proves the change has zero observable effect at the suggestion-stream layer.
- §13 measures wall-clock + memory deltas; both are downstream of the suggestion-stream, which is byte-stable.

**What would invalidate the carry-forward:**
- A future change that adds runtime work to `DirectionLabels.curated` access (e.g., wrapping in `lazy var` with computation).
- A future change that introduces dynamic dispatch where static dispatch was used.
- Any V1.13.x patch that touches scoring-pipeline code paths.

None of these apply at v1.13.0. If V1.13.x patches accumulate before v1.14 cuts, V1.14.4 should re-measure and replace this carry-forward note with fresh measurements.

## Budget changes vs v1.12

**None at v1.13.0.** The V1.6.1 maintenance patch's flake-resistant budget bumps for Row 2 (4.0s) + the 100-file pipeline integration test (6.0s) carry forward unchanged.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` for v1.12 captured `peakDeltaMB=135.9 baselineMB=51.0 budgetMB=800.0`; v1.13 carries forward.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.12.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower.

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation and update the **Measured** column. v1.13 has no re-baselining log — V1.13.1 is a pure structural refactor; no perf-relevant code changed.
