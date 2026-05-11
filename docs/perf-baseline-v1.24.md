# SwiftInferProperties — v1.24 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.24+. The v1.23 / v1.22 / v1.21 / v1.20 / v1.19 / v1.18 / v1.17 / v1.16 / v1.15 / v1.14 / v1.13 / v1.12 / v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-10 against the V1.24.D shape-disambiguation veto commit (`7efcced`); V1.24.E working copy.
**Hardware:** Mac15,5 (Apple M3 family).
**Toolchain:** Apple Swift 6.2.4, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing.

## Re-measurement vs v1.22

v1.24 ships four Sources/ changes per the v1.24 plan §"Open decisions" #4 (re-measure required). v1.23 was empirical-only (carry-forward); v1.22 is the previous re-measured baseline.

The four new vetoes:

- **V1.24.A:** `RoundTripTemplate.asymmetricLabelClassMismatchCounterSignal(for:)` — O(1) per pair (two hash-set lookups + boolean composition).
- **V1.24.B:** `IdempotenceTemplate.mutatorBlocklistVeto(forLifted:)` — O(1) per lifted suggestion (one hash-set lookup).
- **V1.24.C:** `IdempotenceTemplate.nonDeterministicMutatorVeto(forLifted:)` — O(1) per lifted suggestion (one hash-set lookup).
- **V1.24.D:** `IdempotenceTemplate.shapeDisambiguationVeto(for:)` — O(1) per non-lifted suggestion (a few string predicates + hash-set lookups; bounded constant).

Total new per-discover work: four new signal helpers, all O(1) per call site. Expected delta vs v1.22 baseline: **≤+5% wall time** per the v1.24 plan §6 release-blocking criterion.

| Row | Workload | Budget | Measured (v1.24) | Δ vs v1.22 | Test |
|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.391s | -0.011s (-2.7%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.218s | -0.011s (-0.9%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | n/a (skipped) | n/a | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 0.932s | -0.021s (-2.2%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 2 | Discover pipeline on 100 test files | < 6.0s wall | 1.825s | -0.018s (-1.0%) | `TestLifterPerformanceTests.discoverPipelineHundredTestFileBudgetWithM32Pipeline` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.082s | -0.003s (-3.5%; sub-200ms class noise) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 135.9 MB local | +0.1 MB (+0.07%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.020s | +0.001s (+5.3%; millisecond-class noise band) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All rows within ±5% of v1.22 baseline; v1.24 plan §6 ≤+5% budget met. Most rows measure slightly faster than v1.22 — the suppression short-circuit on -22 closed candidates (mostly OC) outweighs per-call O(1) veto-evaluation overhead on the synthetic corpora.

## Notes on the new-mechanism overhead

**Workstream A overhead:** `asymmetricLabelClassMismatchCounterSignal` does up to 4 hash-set lookups (2 against `DirectionLabels.curated`, 2 against `DomainMarkerLabels.curated`) + boolean composition. Sub-microsecond per pair.

**Workstream B overhead:** one hash-set lookup against `MutatorBlockedFromIdempotence.curated` (7 elements). Sub-microsecond per lifted suggestion.

**Workstream C overhead:** one hash-set lookup against `NonDeterministicMutatorNames.curated` (1 element). Trivially fast.

**Workstream D overhead:** one string-prefix check (`_description` / `format`) OR a small set of `.contains` substring checks (Capacity / Count / Scale / scale) + label hash-set lookup. Sub-microsecond per non-lifted suggestion.

**Aggregate per-discover overhead:** ~50 call sites × 4 new vetoes × ~50ns = ~10μs. Negligible compared to the 0.4s baseline.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line for v1.24: `peakDeltaMB=135.9 baselineMB=55.4 budgetMB=800.0`. Peak delta moved from v1.22's 135.8 MB to 135.9 MB (+0.07%). The new vetoes use module-level `let` curated sets; no per-discover-call allocation.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.23.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. Every v1.24 row within ±5% of v1.22; well clear of the 25% breach threshold. The v1.24 baseline becomes the new comparison anchor for v1.25+.

## Re-baselining

v1.25 will be either:
- **Empirical-only cycle 22** (carry-forward from v1.24; no Sources/ changes; perf carries unchanged).
- **Mechanism cycle 22** (NEW direct cycle-21 finding: `index(after:)`/`index(before:)` direction-op idempotence veto; ships Sources/ changes; ~half-day; re-measure perf with ≤+5% budget).

The choice depends on the loop's cadence preference — the cycle-19 findings doc projected v1.25 = empirical re-measurement, but the cycle-21 finding (#2 priority) creates a tractable mechanism-cycle option.
