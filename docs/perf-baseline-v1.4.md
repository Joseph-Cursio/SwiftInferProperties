# SwiftInferProperties — v1.4 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.4+ — the measured wall numbers (and one resident-memory delta) for every §13 row at the v1.4 commit. Future PRs that move any number more than 25% over the baseline below should be treated as a release blocker per §13's last paragraph. The v1.3 baseline (`docs/perf-baseline-v1.3.md`) is retained for forensic comparison across the cycle-1 calibration trajectory but is no longer the regression gate. The v1.2 (`docs/perf-baseline-v1.2.md`) / v1.1 (`docs/perf-baseline-v1.1.md`) / v0.1.0 (`docs/perf-baseline-v0.1.md`) baselines are also retained for the longer trajectory window.

**Captured:** 2026-05-08 against commit on `main` after V1.4.4 (`3797597`).
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.3 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover (all 8 templates active + contradiction pass) | < 2.0s wall | 0.493s | 75% | 0.519s (-5.0%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with `.swiftinfer/decisions.json` load | < 2.0s wall | 1.455s | 27% | 1.523s (-4.5%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` (44 .swift files) | < 3.0s wall (see note) | 1.404s | 53% | 1.445s (-2.8%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files (six detectors + chain-detector pass) | < 3.0s wall | 1.225s | 59% | 1.224s (+0.1%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run after one-file change (10-file corpus) | < 0.5s wall | 0.101s | 80% | 0.104s (-2.9%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB (post-v1.1.0 calibration) | 136.0 MB local | 83% | 551.8 MB (**-75.4%**) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency (5-file corpus) | < 1.0s wall | 0.025s | 98% | 0.024s (+4.2%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "/<funcName>\(\)"`. Within-suite parallelism is unchanged from v1.3 (each row was filtered to one test in isolation to remove parallel-suite contention). CI may show different absolute numbers (different runner hardware) — the §13 contract gates regression magnitude, not absolute parity with this baseline.

## Notes on movement vs v1.3

**Row 4 (memory delta) is the headline at -75.4%.** The drop from 551.8 MB → 136.0 MB is real and is driven by V1.4.3b's cross-type round-trip counter-signal. The synthetic 500-file corpus generates many cross-type function-pair candidates; pre-V1.4.3b each one allocated a full `Suggestion` struct (evidence array, explainability block, identity hash, generator metadata) before the tier-filter dropped it. Post-V1.4.3b, `RoundTripTemplate.suggest` returns `nil` early when the cross-type counter-signal pushes Score < 20 — only the signals array is allocated for the score computation; no Suggestion is constructed. That dropping-before-construction is what reclaims ~415 MB of peak resident memory on the 500-file synthetic corpus.

This isn't a budget-relevant tightening per se (the post-v1.1.0 800 MB CI ceiling was already comfortable at 551.8 MB in v1.3). It's a substantial efficiency improvement and an unexpected benefit of the cross-type rule beyond the surface-quality improvement (990 → 181 round-trip Possible). The post-v1.1.0 800 MB CI ceiling stays — cycle-2 might consider tightening it if cycle-1's gain holds in CI, but that's a separate calibration question.

**Rows 1–3 are within ±5% of v1.3.** The cycle-1 tunings (FP counter-signal, cross-type round-trip rule, tightened FP advisory) add per-template work but mostly reduce per-Suggestion allocation work. Rows 1a (-5.0%), 1b (-4.5%), 1c (-2.8%), 2 (+0.1%), 3 (-2.9%) are all consistent with "slightly faster due to fewer allocations."

**Row 5 (+4.2%) is machine-variance.** Row 5 is sensitive to fixture-corpus + harness setup variance (24ms → 25ms is a 1ms delta on a single-shot measurement). Treating as noise.

## Budget changes vs v1.3

None. All §13 budgets are unchanged from the post-v1.1.0 calibration (row 4 ceiling = 800 MB; all other rows at their v0.1.0 budgets, with row 1c's flake-resistant 3.0s budget unchanged from v1.1).

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms, capturing the running peak. The reported number is **delta over the pre-discover baseline** sampled immediately before `TemplateRegistry.discover(in:)` runs. The diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` is unconditional on every run — for v1.4 this captured `peakDeltaMB=136.0 baselineMB=49.3 budgetMB=800.0`, a ~415 MB drop from the v1.3 measurement attributable to V1.4.3b's pre-allocation suppression of cross-type round-trip pairs.

## §13 row 5 — measurement methodology (unchanged from v0.1.0 + v1.1 + v1.2 + v1.3)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. PRD §13 row 5 wording is "after process start"; the ~10ms `main` → `AsyncParsableCommand` dispatch overhead between OS process start and `Discover.run` entry is not testable from inside the package. Open decision #2 in `docs/archive/v0.1.0 Release Plan.md` documents the gap.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. The Swift Testing assertions in each suite use the hard budget as the gate; PR-time soft regression detection (the 25% rule) remains a post-v1.4 concern (would need a checked-in golden of these numbers + a comparison harness; not on the v1.4 critical path — same posture as v0.1.0 + v1.1 + v1.2 + v1.3).

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation, update the **Measured** column above, and reference the commit + the PR that caused the shift in a new "## Re-baselining log" section at the bottom of this file. Do not delete prior measurements — the regression rule operates against the most recent committed baseline.
