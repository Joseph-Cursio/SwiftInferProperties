# SwiftInferProperties — v1.3 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.3+ — the measured wall numbers (and one resident-memory delta) for every §13 row at the v1.3 commit. Future PRs that move any number more than 25% over the baseline below should be treated as a release blocker per §13's last paragraph. The v1.2 baseline (`docs/perf-baseline-v1.2.md`) is retained for forensic comparison across the M16 trajectory but is no longer the regression gate. The v1.1 (`docs/perf-baseline-v1.1.md`) and v0.1.0 (`docs/perf-baseline-v0.1.md`) baselines are also retained for the longer trajectory window.

**Captured:** 2026-05-07 against commit on `main` after V1.3.0 (`2fb97c3`).
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.2 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover (all 8 templates active + contradiction pass) | < 2.0s wall | 0.519s | 74% | 0.518s (+0.2%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with `.swiftinfer/decisions.json` load | < 2.0s wall | 1.523s | 24% | 1.508s (+1.0%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` (44 .swift files) | < 3.0s wall (see note) | 1.445s | 52% | 1.394s (+3.7%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files (six detectors + chain-detector pass) | < 3.0s wall | 1.224s | 59% | 1.211s (+1.1%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run after one-file change (10-file corpus) | < 0.5s wall | 0.104s | 79% | 0.103s (+1.0%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB (post-v1.1.0 calibration — see Re-baselining log in `perf-baseline-v1.1.md`) | 551.8 MB local | 31% | 548.5 MB (+0.6%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency (5-file corpus) | < 1.0s wall | 0.024s | 98% | 0.023s (+4.3%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "/<funcName>\(\)"`. Within-suite parallelism is unchanged from v1.2 (each row was filtered to one test in isolation to remove parallel-suite contention). CI may show different absolute numbers (different runner hardware) — the §13 contract gates regression magnitude, not absolute parity with this baseline.

## Notes on movement vs v1.2

All rows are within ±5% of the v1.2 baseline — well inside the §13 25% regression rule. M16's surface adds one corpus-wide pass (`ConsumerProducerChainDetector.detect(...)`) over the already-aggregated `[String: [DomainCallSite]]` map, which the existing 100-test-file row (row 2) exercises directly:

- **Row 2 (TestLifter parse) +1.1%.** Effectively flat against v1.2 (1.211s → 1.224s). The M16 chain detector is `O(consumerCount × siteCount)` over an already-built map; the M16.3 follow-up `try`/`await` peeling in `DomainCorpusScanner.classify(_:)` adds at most two cheap `.as(...)` checks per call-site classification. M16 also runs once per discover invocation — not per slice — so the per-test-file overhead doesn't scale with corpus size beyond the deterministic-by-consumer-name iteration.

- **Row 4 (memory delta) +0.6% local.** The 500-file delta at v1.3 (551.8 MB) is essentially unchanged from v1.2 (548.5 MB locally). M16's `consumerProducerChainHintsByIdentity` side-map carrier follows the M11 posture — keyed only on qualifying chains, not on every Suggestion — so per-Suggestion storage is unchanged. The post-v1.1.0 800 MB CI ceiling stands; the always-on `[§13 row 4] peakDeltaMB=…` stderr log surfaces every CI run for drift detection.

- **Row 5 (--interactive first prompt) +4.3%.** Row 5 is sensitive to fixture-corpus + harness setup variance (24ms → 23ms is a 1ms delta on a single-shot measurement). Treating as machine variance.

- **Rows 1a / 1b / 1c / 3 within ±4%.** All within machine-variance neighborhood. M16's pipeline arm is gated on a non-empty `domainCallSitesByConsumer` map; for the 50-file synthetic corpus (row 1) and the swift-collections row (row 1c), the production-side TestLifter discovery doesn't surface chain candidates at the M4.3 ≥3-site threshold so the detector returns immediately. Row 3 (drift re-run) is unchanged in shape.

## Budget changes vs v1.2

None. All §13 budgets are unchanged from the post-v1.1.0 calibration (row 4 ceiling = 800 MB; all other rows at their v0.1.0 budgets, with row 1c's flake-resistant 3.0s budget unchanged from v1.1).

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms, capturing the running peak. The reported number is **delta over the pre-discover baseline** sampled immediately before `TemplateRegistry.discover(in:)` runs. The diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` is unconditional on every run — for v1.3 this captured `peakDeltaMB=551.8 baselineMB=48.6 budgetMB=800.0`, matching the v1.2 measurement to within ~0.6%.

## §13 row 5 — measurement methodology (unchanged from v0.1.0 + v1.1 + v1.2)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. PRD §13 row 5 wording is "after process start"; the ~10ms `main` → `AsyncParsableCommand` dispatch overhead between OS process start and `Discover.run` entry is not testable from inside the package. Open decision #2 in `docs/archive/v0.1.0 Release Plan.md` documents the gap.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. The Swift Testing assertions in each suite use the hard budget as the gate; PR-time soft regression detection (the 25% rule) remains a post-v1.3 concern (would need a checked-in golden of these numbers + a comparison harness; not on the v1.3 critical path — same posture as v0.1.0 + v1.1 + v1.2).

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation, update the **Measured** column above, and reference the commit + the PR that caused the shift in a new "## Re-baselining log" section at the bottom of this file. Do not delete prior measurements — the regression rule operates against the most recent committed baseline.
