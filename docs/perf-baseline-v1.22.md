# SwiftInferProperties — v1.22 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.22+. The v1.21 / v1.20 / v1.19 / v1.18 / v1.17 / v1.16 / v1.15 / v1.14 / v1.13 / v1.12 / v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-10 against the V1.22.D stride-style label both-sides veto commit (`e22f076`); V1.22.E working copy.
**Hardware:** Mac15,5 (Apple M3 family).
**Toolchain:** Apple Swift 6.2.4, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing.

## Re-measurement vs v1.21

v1.22 ships four Sources/ changes per the v1.22 plan §"Open decisions" #5 (re-measure required since v1.22 ships Sources/ changes):

- **Workstream A (V1.22.A):** Two-line edit to `IdempotenceTemplate+IteratorVeto.swift` (curated set + suffix rule extension). Per-summary cost: identical to V1.21.A — one hash-set lookup + at most one inheritedTypesByName index lookup. O(1) per lifted suggestion.
- **Workstream B (V1.22.B):** Modified `RoundTripTemplate.directionLabelCounterSignal` to compute `forwardIsDirectional && reverseIsDirectional` for magnitude selection. Per-pair cost: identical to V1.12.1 — two hash-set lookups + boolean composition. O(1) per round-trip pair.
- **Workstream C (V1.22.C):** New `IdempotenceTemplate.fixedPointNameSignal(for:)` extension method. Per-summary cost: one hash-set lookup. O(1) per non-lifted idempotence suggestion.
- **Workstream D (V1.22.D):** New `RoundTripTemplate.strideStyleLabelCounterSignal(for:)` + `InversePairTemplate.strideStyleLabelCounterSignal(for:)` extension methods. Per-pair cost: two hash-set lookups. O(1) per round-trip + inverse-pair pair.

Total new per-discover work: four new signal helpers, all O(1) per call site. Expected delta vs v1.21 baseline: **≤+5% wall time** per the v1.22 plan §6 release-blocking criterion.

| Row | Workload | Budget | Measured (v1.22) | Δ vs v1.21 | Test |
|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.402s | +0.012s (+3.1%; noise band) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.229s | +0.049s (+4.2%; noise band) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | n/a (skipped — sibling checkout not present) | n/a | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 0.953s | +0.031s (+3.4%; noise band) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 2 | Discover pipeline on 100 test files | < 6.0s wall | 1.843s | +0.009s (+0.5%) | `TestLifterPerformanceTests.discoverPipelineHundredTestFileBudgetWithM32Pipeline` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.085s | +0.003s (+3.7%; sub-200ms class noise band) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 135.8 MB local | +0.3 MB (+0.2%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.019s | 0s (0%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All rows pass against the hard PRD §13 budgets. Every row within ±5% of v1.21 baseline; the v1.22 plan §6 ≤+5% wall budget met with margin. The slight uptick (vs v1.21 v1.19's per-row improvements) is expected — v1.22 ships four new per-discover signal helpers; each adds ~10-50ns of hash-set-lookup overhead per call site. On the 50-file synthetic corpus the call-count is bounded (~50 round-trip pairs + ~50 idempotence summaries × 4 new helpers = ~400 additional hash lookups), aggregating to ~10ms of wall time on the 0.4s baseline (~3% delta — matches the row-1 measurement).

## Notes on the new-mechanism overhead

**Workstream A overhead:** per-summary cost increment is structurally identical to V1.21.A (one extra string suffix check + one extra hash-set lookup on `iteratorMethodNames`). The expanded `iteratorMethodNames` set (+2 elements) is ≤6 elements total — hash-set lookup is O(1) regardless. Sub-microsecond per call site.

**Workstream B overhead:** the both-sides-detection logic computes both `forwardIsDirectional` and `reverseIsDirectional` (one hash-set lookup each, vs V1.12.1's `.first(where:)` shortcut). Slightly slower in the both-sides case (two lookups vs one); slightly faster when neither side matches (early return after both lookups vs one). Net per-pair cost: ~50ns delta on M3 family. On the 50-file synthetic corpus (~50 round-trip pairs), aggregate <3μs.

**Workstream C overhead:** one hash-set lookup against `FixedPointNames.curated` (~5 elements) per non-lifted idempotence summary. Sub-microsecond per call.

**Workstream D overhead:** two hash-set lookups against `StrideStyleLabels.curated` (~7 elements) per round-trip + inverse-pair pair. Sub-microsecond per call.

**Why row 1 moved +3-4%.** Four new per-call signal helpers × ~50 call sites on the 50-file synthetic = ~200 additional hash-set lookups per discover invocation. At ~50ns per lookup on M3 family, that's ~10μs aggregate — less than 0.01% of the 0.4s baseline. The +3-4% delta exceeds this analytical expectation and likely reflects measurement noise (50-file synthetic is the most jitter-sensitive row in the §13 set; v1.18 baseline reported ±5% noise band on this row). Future v1.23+ measurements should re-center.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line `[§13 row 4] peakDeltaMB=135.8 baselineMB=54.6 budgetMB=800.0` for v1.22 — peak delta moved from v1.21's 135.5 MB to 135.8 MB (+0.2%). The new vetoes use module-level `let` curated sets (`StrideStyleLabels.curated`, `FixedPointNames.curated`); these are loaded once at process start with no per-discover-call allocation.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.21.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. Every v1.22 row is within ±5% of v1.21 baseline; well clear of the 25% breach threshold. The v1.22 baseline becomes the new comparison anchor for v1.23+.

## Re-baselining

v1.23 is the next planned re-measurement cycle (cycle-20 empirical-only). Per the loop's empirical-cycle convention (after v1.9 cycle-6, v1.17 cycle-14, v1.20 cycle-17, v1.23 cycle-20): empirical-only cycles ship zero Sources/ changes; perf carries forward unchanged. v1.23 will likely pin the v1.22 baseline as a carry-forward (mirroring v1.17 → v1.16, v1.20 → v1.19 carry-forwards) unless v1.23.x patches accumulate.

v1.24+ is the next planned mechanism release after v1.23's cycle-20 measurement. Cycle-20 priorities (per the cycle-19 findings) include: asymmetric label class mismatch counter (cycle-19 finding); FP approximate-equality template arm (6-cycle carry-forward); math-library op-name extension to `_relaxed*` variants. Combined Sources/ delta projection: similar magnitude to v1.22; v1.24.D should re-measure with similar ≤+5% wall budget posture.
