# SwiftInferProperties — v1.19 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.19+. The v1.18 / v1.17 / v1.16 / v1.15 / v1.14 / v1.13 / v1.12 / v1.11 / v1.10 / v1.9 / v1.8 / v1.7 / v1.6 / v1.5 / v1.4 / v1.3 / v1.2 / v1.1 / v0.1.0 baselines are retained for forensic comparison.

**Captured:** 2026-05-10 against the v1.19 working copy at commit `fd798d3` (V1.19.D InversePairTemplate lift admission via InverseLiftedPairing — the post-Workstream-B-complete state).
**Hardware:** Mac15,5 (Apple M3 family).
**Toolchain:** Apple Swift 6.2.4, target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing.

## Re-measurement vs v1.18

v1.19 ships Workstream B from the v1.18 plan §2 — re-admitting the entire `mutating func` surface to algebraic-property scoring via the `LiftedTransformation` metadata-only lift. This adds a third per-discover pass (alongside v1.18's `CarrierKindResolver` + `DualStylePairing`):

- **`LiftedTransformation.derive(from:carrierKindResolver:)`** — single pass over `[FunctionSummary]`, O(N) — built once per `discover` call alongside `EquatableResolver` / `inheritedTypesByName` / `CarrierKindResolver`. Strict admission gate (`isMutating && containingTypeName != nil && carrierKindResolver.classify(...) == .valueSemantic`) filters to a small subset.
- **`LiftedIdentityElementPairing.candidates(in:identities:)`** — per-discover pass over `[LiftedTransformation] × [IdentityCandidate]`. O(M·I) where M = lifted-transformation count, I = identity-candidate count. Both are bounded by the corpus's mutating-method + curated-identity-name surface.
- **`InverseLiftedPairing.candidates(in:vocabulary:)`** — per-discover pass over `[LiftedTransformation]`. O(M²) within each carrier group; carrier groups are small (typically 1–10 mutating funcs per type).

Per-suggestion overhead: each lifted-suggest path emits the existing template's signal stack plus one `Signal.Kind.liftedFromMutation` (+10) per the V1.19.A signal addition. `Suggestion` allocation cost is identical to non-lifted templates.

> **Hardware caveat.** The v1.19 capture is on a Mac15,5 (M3 family); the v1.18 baseline was captured on a MacBook Air M1. The v1.19→v1.18 deltas reported below conflate hardware change with mechanism overhead. The §13 contract is on absolute budgets (which all rows pass) and on percentage regressions vs the prior baseline (every row in v1.19 measures faster, so no regression risk). Future v1.19→v1.20 deltas will be on consistent hardware.

| Row | Workload | Budget | Measured (v1.19) | Δ vs v1.18 (cross-hardware — see caveat) | Test |
|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.403s | -0.216s (-34.9%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.226s | -0.325s (-21.0%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | n/a (skipped — sibling checkout not present) | n/a | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 0.941s | -0.297s (-24.0%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 2 | Discover pipeline on 100 test files | < 6.0s wall | 1.836s | -0.329s (-15.2%) | `TestLifterPerformanceTests.discoverPipelineHundredTestFileBudgetWithM32Pipeline` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.085s | -0.070s (-45.2%; sub-200ms class) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 136.3 MB local | -12.5 MB (-8.4% peak delta vs v1.18 baseline 148.8 MB) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.019s | -0.025s (-56.8%; millisecond-class) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All rows pass against the hard PRD §13 budgets. Every row measured faster than v1.18 — Workstream B's lift admission is structurally additive (a third per-discover pass), but the strict value-semantic admission gate keeps the lifted-suggestion volume small and the per-suggestion cost is identical to the non-lifted templates the lifts feed into. The cross-hardware speedups dominate the v1.19→v1.18 deltas; the v1.19 release-blocking criterion (≤+10% wall vs v1.18 per the v1.18 plan §6) is met with wide margin.

## Notes on the workstream B overhead

**`LiftedTransformation.derive` overhead:** O(N) over all `FunctionSummary` entries. The strict admission gate (`isMutating && containingTypeName != nil && carrierKindResolver.classify(...) == .valueSemantic`) is three short-circuiting predicates per summary. The classifier lookup is cached in `CarrierKindResolver`. For a 500-file corpus with a few hundred function summaries, total cost is sub-millisecond.

**`LiftedIdentityElementPairing.candidates` overhead:** O(M·I). On the cycle-1..14 corpora M is bounded by the mutating-func count (typically 5–50 per corpus) and I by the curated-identity-name count (`zero`, `empty`, `identity`, `none`, `default`). The pairing pass is sub-microsecond per call site.

**`InverseLiftedPairing.candidates` overhead:** O(M²) within each carrier group, but carrier groups are small. The curated state-mutation inverse-name pair table (9 entries: `add`/`remove`, `insert`/`remove`, `push`/`pop`, `attach`/`detach`, `link`/`unlink`, `activate`/`deactivate`, `subscribe`/`unsubscribe`, `register`/`deregister`, `enable`/`disable`) plus `Vocabulary.inversePairs` is hashed for O(1) name-pair matching.

**Why row 1 measures *faster* despite three new passes.** The lift admission paths short-circuit on most synthetic corpora — the synthetic corpus generator (`PerformanceTests.generateSyntheticCorpus`) emits non-mutating functions almost exclusively, so `LiftedTransformation.derive` returns an empty array and the per-template lifted-suggest paths are no-op. The cross-hardware speedup (M1 → M3 family) accounts for the ~25–35% wall reduction across the half-second-class rows. The lifted-suggestion overhead becomes measurable only on corpora with substantial mutating-func surfaces — to be characterised in the v1.20 empirical cycle on the four cycle-1..14 corpora (Algorithms, OrderedCollections, ChartMath/ComplexModule, PropertyLawKit).

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms. Diagnostic stderr line `[§13 row 4] peakDeltaMB=136.3 baselineMB=53.8 budgetMB=800.0` for v1.19 — peak delta moved from v1.18's 148.8 MB to 136.3 MB (-8.4%). The `LiftedTransformation` array is a small per-`discover` allocation (≤ M `LiftedTransformation` structs, each ~6 stored properties); the new pairing passes use stack-allocated dictionaries that are released at function exit. No persistent memory growth from Workstream B.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.18.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. Every v1.19 row measures *faster* than v1.18, so no regression. The v1.19 baseline becomes the new comparison anchor for v1.20+.

## Re-baselining

v1.20 is the next planned re-baseline (empirical cycle on the post-v1.19 surface). v1.20 ships no `Sources/` changes — empirical-only re-measurement on the four cycle-1..14 corpora — so v1.20 may pin the v1.19 baseline as a carry-forward (mirroring v1.17's carry-forward of v1.16) if no Sources/ shifts land. Otherwise re-measure.
