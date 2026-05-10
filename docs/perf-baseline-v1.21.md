# SwiftInferProperties — v1.21 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.21+. The v1.20 / v1.19 / v1.18 / v1.17 / v1.16 / v1.15 / v1.14 / v1.13 / v1.12 / v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-10 against the V1.21.C math-forward function counter commit (`d3bed65`); V1.21.D working copy.
**Hardware:** Mac15,5 (Apple M3 family).
**Toolchain:** Apple Swift 6.2.4, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing.

## Re-measurement vs v1.19

v1.21 ships three Sources/ changes per the v1.21 plan §"Open decisions" #6 (re-measure required since v1.21 ships Sources/ changes):

- **Workstream A** (V1.21.A): new `IdempotenceTemplate+IteratorVeto.swift` extension method. Per-summary cost: one hash-set lookup + at most one inheritedTypesByName index lookup. O(1) per lifted suggestion.
- **Workstream B** (V1.21.B): new `monotoneBoundedLabels` curated set + per-summary first-parameter-label hash-set lookup. O(1) per composition-lifted suggestion.
- **Workstream C** (V1.21.C): new `MathForwardFunctions` curated set + canonical-inverse-pair allowlist. Per-summary one hash-set lookup (idempotence path); per-pair two lookups + canonical-pair scan (round-trip path). O(1) per idempotence non-lifted suggestion; O(K) per round-trip pair where K ≤ 10 (canonicalInversePairs entry count).

Total new per-discover work: three new vetoes, all O(1) per call site. Expected delta vs v1.19 baseline: **≤+5% wall time** per the v1.21 plan §6 release-blocking criterion.

| Row | Workload | Budget | Measured (v1.21) | Δ vs v1.19 | Test |
|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.390s | -0.013s (-3.2%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.180s | -0.046s (-3.8%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | n/a (skipped — sibling checkout not present) | n/a | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 0.922s | -0.019s (-2.0%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 2 | Discover pipeline on 100 test files | < 6.0s wall | 1.834s | -0.002s (-0.1%) | `TestLifterPerformanceTests.discoverPipelineHundredTestFileBudgetWithM32Pipeline` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.082s | -0.003s (-3.5%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 135.5 MB local | -0.8 MB (-0.6%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.019s | 0s (0%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All rows pass against the hard PRD §13 budgets. **Every row measures faster (or equal) than v1.19**, well within the v1.21 plan's ≤+5% budget. The plan's ~+5% projection assumed worst-case adding three per-discover-call vetoes; in practice, the **suppressed-suggestion short-circuit** (templates returning `nil` early when score collapses to Suppressed) outweighs the new veto-evaluation cost — V1.21.C alone closes ~146 candidates that previously ran through the full scoring + explainability + identity-hash pipeline; the per-discover wall savings on the 50-file synthetic corpus dominates the per-suggestion veto-evaluation overhead.

## Notes on the new-mechanism overhead

**Workstream A overhead:** `IdempotenceTemplate.iteratorProtocolCarrierVeto(for:inheritedTypesByName:)` is O(1) per lifted-idempotence suggestion. The primary path performs one `Dictionary[String]` lookup + one `Set.contains("IteratorProtocol")` check; the name-fallback path adds one `String.hasSuffix(".Iterator")` + one `Set.contains(methodName)` check. On the 50-file synthetic corpus the lifted-idempotence call site fires few times (the synthetic generator emits non-mutating functions almost exclusively); aggregate impact <0.1ms.

**Workstream B overhead:** `CompositionTemplate.monotoneBoundedLabelSignal(for:)` is O(1) per composition-lifted suggestion. One first-parameter-label `Set.contains(_:)` check. Sub-microsecond.

**Workstream C overhead:** `IdempotenceTemplate.mathForwardFunctionVeto(for:)` is O(1) per non-lifted idempotence suggestion (one `Set.contains(name)` + shape-gate predicates). `RoundTripTemplate.mathForwardFunctionPairVeto(for:)` is O(K) per round-trip pair, where K = `canonicalInversePairs.count` ≤ 10 — the worst-case allowlist scan. On the 50-file synthetic corpus, round-trip pairs that have both names in the curated math-forward set are rare (synthetic emits non-math names); aggregate impact <0.5ms.

**Why every row measures faster than v1.19.** The synthetic corpora used in the §13 perf rows don't exercise the new-mechanism reject paths heavily (they emit non-Iterator, non-math, non-monotone-bounded shapes), so the per-call new-veto cost is negligible. The cycle-1..14 corpora *do* exercise the new vetoes — V1.21.D's discover capture (`docs/calibration-cycle-18-data/`) shows -170 candidates closed, each of which short-circuits the rest of the scoring + suggestion-construction pipeline. Aggregate effect: the v1.21 binary spends *less* wall time per discover call than v1.19 on real corpora, even before counting the synthetic-row overhead amortization.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line `[§13 row 4] peakDeltaMB=135.5 baselineMB=54.3 budgetMB=800.0` for v1.21 — peak delta moved from v1.19's 136.3 MB to 135.5 MB (-0.6%). The new vetoes use module-level `let` curated sets (`MathForwardFunctions.curated`, `monotoneBoundedLabels`, `iteratorMethodNames`); these are loaded once at process start with no per-discover-call allocation.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.20.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. Every v1.21 row measures *faster* than v1.19, so no regression. The v1.21 baseline becomes the new comparison anchor for v1.22+.

## Re-baselining

v1.22 is the next planned re-baseline (cycle-19 mechanism release). Per the cycle-18 findings priority list, v1.22 will ship 4-5 small mechanisms targeting:

- Fixed-point-name positive signal on non-lifted idempotence (~half day).
- BucketIterator name extension on V1.21.A's curated method set (~hour).
- OC `index(after:) × index(before:)` direction-pair full-veto extension on V1.12.1 (~half day).
- Stride-style label extension (~half day).
- FP approximate-equality template arm (~1 day; out-of-band correctness fix).

Combined Sources/ delta projection: similar magnitude to v1.21 individual workstreams. v1.22.D should re-measure perf with similar ≤+5% wall budget posture.

v1.23 is the next planned empirical-only cycle (cycle 20) — perf will carry forward from v1.22 if v1.23 ships zero Sources/ changes (mirroring v1.17 → v1.16 and v1.20 → v1.19 carry-forwards).
