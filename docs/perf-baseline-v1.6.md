# SwiftInferProperties — v1.6 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.6+ — the measured wall numbers (and one resident-memory delta) for every §13 row at the v1.6 commit. Future PRs that move any number more than 25% over the baseline below should be treated as a release blocker per §13's last paragraph. The v1.5 baseline (`docs/perf-baseline-v1.5.md`) is retained for forensic comparison across the cycle-3 calibration trajectory but is no longer the regression gate. The v1.4 (`docs/perf-baseline-v1.4.md`) / v1.3 (`docs/perf-baseline-v1.3.md`) / v1.2 (`docs/perf-baseline-v1.2.md`) / v1.1 (`docs/perf-baseline-v1.1.md`) / v0.1.0 (`docs/perf-baseline-v0.1.md`) baselines are also retained for the longer trajectory window.

**Captured:** 2026-05-08 against `main` HEAD `1bc7039` (v1.5.0 tag) + the V1.6.0–V1.6.3 working copy (V1.6.4 pre-commit).
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.5 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover (all 8 templates active + contradiction pass) | < 2.0s wall | 0.495s | 75% | 0.492s (+0.6%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with `.swiftinfer/decisions.json` load | < 2.0s wall | 1.465s | 27% | 1.467s (-0.1%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` (44 .swift files) | < 3.0s wall (see note) | 1.410s | 53% | 1.399s (+0.8%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files (six detectors + chain-detector pass) | < 3.0s wall | 1.222s | 59% | 1.224s (-0.2%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run after one-file change (10-file corpus) | < 0.5s wall | 0.101s | 80% | 0.100s (+1.0%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB (post-v1.1.0 calibration) | 134.8 MB local | 83% | 134.6 MB (+0.1%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency (5-file corpus) | < 1.0s wall | 0.025s | 98% | 0.024s (+4.2%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "/<funcName>\(\)"`. Within-suite parallelism is unchanged from v1.5 (each row was filtered to one test in isolation to remove parallel-suite contention). CI may show different absolute numbers (different runner hardware) — the §13 contract gates regression magnitude, not absolute parity with this baseline.

## Notes on movement vs v1.5

**All seven rows are within ±5% of v1.5 — the v1.6 plan's "flat" projection confirmed.** The v1.6 plan's V1.6.4 budget projection predicted exactly this shape: V1.6.1's pair-formation skip helper is a constant-time check (set membership × 2 + dictionary lookup) that runs once per pair-emission decision; pair counts only go *down* (filtered pairs skip downstream Suggestion construction). Net effect should be flat or imperceptibly negative on all rows.

**Row 1a–1c, 2, 3 — discover wall (+0.6% / -0.1% / +0.8% / -0.2% / +1.0%):** All within machine-variance of v1.5. The added per-pair work is the `skipsKnownMismatched(...)` call against two small `Set<String>` and one Dictionary lookup — ~3 hash operations per pair-emission decision in `IdentityElementPairing.candidates(...)`. For the 50-file synthetic corpus that's ≤ a few hundred extra hash operations per discover pass. Net cost is well under the noise floor.

**Row 4 (memory delta) effectively unchanged at 134.8 MB (+0.1%) vs v1.5's 134.6 MB.** Direction matches the v1.6 plan's V1.6.4 prediction ("Row 4 memory unaffected — pair-formation is upstream of Suggestion construction; the v1.5 veto already prevented allocation for kit-covered pairs"). v1.6 filters at pair-emission *before* `IdentityElementPair` allocation, but `IdentityElementPair` is a 2-field value type whose memory cost is dominated by the contained `FunctionSummary` + `IdentityCandidate` references (already allocated upstream during scanning). The +0.2 MB swing is sample-to-sample noise on a 130-MB-scale measurement.

**Row 5 (+4.2%) is machine-variance.** Identical v1.5 → v1.6 movement (25ms → 25ms... actually 24ms → 25ms = +1ms = +4.2% on the 1ms-precision single-shot measurement). Treating as noise, same posture as v1.5's +4.2% / v1.4's -4.0% / v1.3's +4.2%.

**The cycle-3 corpus measurements (`docs/calibration-cycle-3-data/post-filter-*.discover.txt`) provide an independent confirmation of per-corpus cost.** All four corpus discovers ran under the same release binary in single-digit seconds; the cycle-3 capture didn't reveal any regression-class slowdowns.

## Budget changes vs v1.5

None. All §13 budgets are unchanged from the post-v1.1.0 calibration (row 4 ceiling = 800 MB; all other rows at their v0.1.0 budgets, with row 1c's flake-resistant 3.0s budget unchanged from v1.1).

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms, capturing the running peak. The reported number is **delta over the pre-discover baseline** sampled immediately before `TemplateRegistry.discover(in:)` runs. The diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` is unconditional on every run — for v1.6 this captured `peakDeltaMB=134.8 baselineMB=50.3 budgetMB=800.0`.

## §13 row 5 — measurement methodology (unchanged from v0.1.0 + v1.1 + v1.2 + v1.3 + v1.4 + v1.5)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. PRD §13 row 5 wording is "after process start"; the ~10ms `main` → `AsyncParsableCommand` dispatch overhead between OS process start and `Discover.run` entry is not testable from inside the package. Open decision #2 in `docs/archive/v0.1.0 Release Plan.md` documents the gap.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. The Swift Testing assertions in each suite use the hard budget as the gate; PR-time soft regression detection (the 25% rule) remains a post-v1.6 concern (would need a checked-in golden of these numbers + a comparison harness; not on the v1.6 critical path — same posture as v0.1.0 + v1.1 + v1.2 + v1.3 + v1.4 + v1.5).

**v1.5-era observation worth restating for v1.6:** Row 2 + Row 1d hard budgets (3.0s / 5.0s) are demonstrably borderline-flaky on GitHub Actions hardware (the v1.5 push CI flaked on first attempt; reran green). Local Apple M1 has 60% / 28% headroom at v1.6, but CI variance can push these tests over the ceiling. Cycle-4 priority #7 sizes a budget-widening fix.

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation, update the **Measured** column above, and reference the commit + the PR that caused the shift in a new "## Re-baselining log" section at the bottom of this file. Do not delete prior measurements — the regression rule operates against the most recent committed baseline.
