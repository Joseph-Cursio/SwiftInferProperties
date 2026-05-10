# SwiftInferProperties — v1.23 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.23+. The v1.22 / v1.21 / v1.20 / v1.19 / v1.18 / v1.17 / v1.16 / v1.15 / v1.14 / v1.13 / v1.12 / v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-10 against the V1.23.D cycle-20 findings commit; V1.23.E working copy.
**Hardware:** Mac15,5 (Apple M3 family).
**Toolchain:** Apple Swift 6.2.4, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing.

## Carry-forward from v1.22

**v1.23 ships zero behavior change — and zero code change.** Mirrors v1.17's empirical-only carry-forward posture (after v1.9 = cycle 6, v1.17 = cycle 14, v1.20 = cycle 17, v1.23 = cycle 20). V1.23.0 opened the cycle-20 plan, V1.23.A documented the surface re-capture metadata, V1.23.B wrote the cycle-20 triage rubric, V1.23.C wrote the 46-decision triage data, V1.23.D wrote the cycle-20 findings, and V1.23.E (this doc) records the perf carry-forward. None of those touch `Sources/` or any test target. The v1.23 binary is byte-identical to v1.22.0.

**No re-measurement required.** Per PRD §13, the contract gates regression magnitude. A documentation-only release that produces a byte-identical CLI cannot move §13 measurements. v1.23's baseline is the v1.22 baseline carried forward.

| Row | Workload | Budget | Measured (v1.22 carry-forward) | Headroom | Test |
|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.402s | 80% | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.229s | 39% | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | n/a (skipped) | n/a | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 0.953s | 76% | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 2 | Discover pipeline on 100 test files | < 6.0s wall | 1.843s | 69% | `TestLifterPerformanceTests.discoverPipelineHundredTestFileBudgetWithM32Pipeline` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.085s | 83% | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 135.8 MB local | 83% | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.019s | 98% | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers carried forward verbatim from `docs/perf-baseline-v1.22.md`. CI-side measurements at the v1.23.0 release commit will land in single-shot bands consistent with v1.22's observed precision.

## Notes on the carry-forward posture

**Why v1.23 doesn't re-measure:**
- v1.23 changes zero `Sources/` files and zero test files. CLI binary is byte-identical to v1.22.0.
- §13 measures wall-clock + memory deltas; both are downstream of the suggestion-stream, which is byte-identical (no scoring-pipeline change, no template change, no curated-set change).

**What would invalidate the carry-forward:**
- A V1.23.x patch that touches `Sources/` (any file). v1.23 by-design does not.
- A V1.23.x patch that adds or modifies a test target. v1.23 by-design does not (test count stays at 1845).

None apply at v1.23.0.

## Budget changes vs v1.22

**None at v1.23.0.** All §13 budgets carry forward unchanged.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line for v1.22: `peakDeltaMB=135.8 baselineMB=54.6 budgetMB=800.0`. v1.23 carries forward.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.22.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower.

## Re-baselining

v1.24 is the next planned re-baseline (cycle-21 mechanism release). Per the cycle-20 findings priority list, v1.24 will ship 4 small mechanisms targeting:

- Asymmetric label class mismatch counter on round-trip (cycle-19 + cycle-20 finding).
- `reverse`/`removeFirst`/`removeLast` veto on idempotence-lifted (cycle-20 NEW finding).
- Non-deterministic shuffle veto extension (cycle-20 NEW finding).
- Capacity-from-scale + formatter shape-disambiguation veto on idempotence non-lifted (cycle-20 NEW finding).

Combined Sources/ delta projection: similar magnitude to v1.22; v1.24's findings doc should re-measure perf with similar ≤+5% wall budget posture.

v1.25+ continues the cycle-15/16/17/18/19/20 carry-forward priorities (FP approximate-equality template arm — 7-cycle carry-forward; math-library `_relaxed*` extension — 5-cycle carry-forward).

The empirical-cycle cadence is now established: every 2-3 mechanism cycles → 1 empirical re-measurement. Next empirical cycle would naturally land at v1.26 (cycle 23) after v1.24 + v1.25 mechanism releases.
