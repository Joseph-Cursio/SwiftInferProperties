# SwiftInferProperties — v0.1.0 Performance Baseline

PRD v0.4 §13 mandates that "a 25% regression in any number fails the build." This file is the comparison anchor — the measured wall numbers (and one resident-memory delta) for every §13 row at the v0.1.0 cut. Future PRs that move any number more than 25% over the baseline below should be treated as a release blocker per §13's last paragraph.

**Captured:** 2026-05-03 against commit on `main` after R1.1.h (`e686200`).
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), target `arm64-apple-macosx26.0`.
**Test target:** `swift test` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | Test |
|---|---|---|---|---|---|
| 1 | 50-file synthetic discover (all 8 templates active + contradiction pass) | < 2.0s wall | 0.689s | 66% | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with `.swiftinfer/decisions.json` load | < 2.0s wall | 1.792s | 10% | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` (44 .swift files) | < 2.0s wall | 1.704s | 15% | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 3.0s wall | 0.507s | 83% | `TestLifterPerformanceTests` |
| 3 | `swift-infer drift` re-run after one-file change (10-file corpus) | < 0.5s wall | 0.175s | 65% | `DriftIncrementalPerformanceTests` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | **< 600 MB** (calibrated — see below) | ~492 MB | 18% | `MemoryCeilingPerformanceTests` |
| 5 | `swift-infer discover --interactive` first-prompt latency (5-file corpus) | < 1.0s wall | 0.046s | 95% | `InteractiveFirstPromptPerformanceTests` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named suite. CI may show different absolute numbers (different runner hardware) — the §13 contract gates regression magnitude, not absolute parity with this baseline.

## §13 row 4 — calibration note

PRD v0.3 §13 row 4 set the target at "< 200 MB resident" without measurement, and §13 itself authorized raising calibration-busted targets ("if the targets are already missed there, raise them in v0.4 rather than ship a tool that can't keep up"). The R1.1.b measurement on the v0.1.0 commit finds delta **~492 MB** on a 500-file synthetic — the original 200 MB target was unattainable on a real corpus that exercises every shipped template. The budget was revised to 600 MB (current measurement + ~25% headroom matching the §13 25%-regression rule).

The PRD §13 row 4 line was updated to "< 600 MB resident on 500-file module" in R1.3 alongside the version bump; the in-test budget references a per-suite constant `MemoryCeilingPerformanceTests.calibratedDeltaBudgetMB` so the two stay aligned.

**Post-v0.1.0 perf-tuning candidates** identified during R1.1.b (not blocking v0.1.0):
- `FunctionScanner.scanCorpus(directory:)` accumulates `[FunctionSummary]` + `[IdentityCandidate]` + `[TypeDecl]` across all files at once. For larger corpora a streaming pass (one file → one suggestion-emission unit, dropped before next file parses) would halve memory.
- The cross-function pairing pass (`FunctionPairing.pair(...)`) materializes the pair index in memory for the M1.4 round-trip + M3.x algebraic pairings. A bucket-by-canonical-type-name pre-filter would shrink the working set.

## §13 row 4 — measurement methodology

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms, capturing the running peak. The reported number is **delta over the pre-discover baseline** sampled immediately before `TemplateRegistry.discover(in:)` runs — the absolute RSS includes the test runner's own footprint (Swift Testing, every test target's binary, the SwiftSyntax dep graph) which baselines around 40 MB on its own and would dominate the absolute measurement. Delta is the honest in-test gate; the absolute number from a real `swift-infer discover` invocation against a 500-file corpus would be 40 MB lower, putting it well inside the calibrated 600 MB budget.

## §13 row 5 — measurement methodology

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. PRD §13 row 5 wording is "after process start"; the ~10ms `main` → `AsyncParsableCommand` dispatch overhead between OS process start and `Discover.run` entry is not testable from inside the package. Open decision #2 in `docs/archive/v0.1.0 Release Plan.md` documents the gap.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. The Swift Testing assertions in each suite use the hard budget as the gate; PR-time soft regression detection (the 25% rule) is a post-v0.1.0 concern (would need a checked-in golden of these numbers + a comparison harness; not on the v0.1.0 critical path).

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation, update the **Measured** column above, and reference the commit + the PR that caused the shift in a new "## Re-baselining log" section at the bottom of this file. Do not delete prior measurements — the regression rule operates against the most recent committed baseline.
