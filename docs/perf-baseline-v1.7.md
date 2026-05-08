# SwiftInferProperties — v1.7 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.7+ — the measured wall numbers (and one resident-memory delta) for every §13 row at the v1.7 commit. Future PRs that move any number more than 25% over the baseline below should be treated as a release blocker per §13's last paragraph. The v1.6 baseline (`docs/perf-baseline-v1.6.md`) is retained for forensic comparison across the cycle-4 calibration trajectory but is no longer the regression gate. The v1.5 (`docs/perf-baseline-v1.5.md`) / v1.4 (`docs/perf-baseline-v1.4.md`) / v1.3 (`docs/perf-baseline-v1.3.md`) / v1.2 (`docs/perf-baseline-v1.2.md`) / v1.1 (`docs/perf-baseline-v1.1.md`) / v0.1.0 (`docs/perf-baseline-v0.1.md`) baselines are also retained for the longer trajectory window.

**Captured:** 2026-05-08 against `main` HEAD `5237254` (V1.7.3 cycle-4 capture commit) + the V1.7.4 working copy.
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.6 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover (all 8 templates active + contradiction pass) | < 2.0s wall | 0.530s | 73% | 0.495s (+7.1%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with `.swiftinfer/decisions.json` load | < 2.0s wall | 1.523s | 24% | 1.465s (+4.0%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` (44 .swift files) | < 3.0s wall (see note) | 1.431s | 52% | 1.410s (+1.5%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files (six detectors + chain-detector pass) | < 4.0s wall (V1.6.1 flake-resistant) | 1.241s | 69% | 1.222s (+1.6%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run after one-file change (10-file corpus) | < 0.5s wall | 0.104s | 79% | 0.101s (+3.0%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB (post-v1.1.0 calibration) | 135.5 MB local | 83% | 134.8 MB (+0.5%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency (5-file corpus) | < 1.0s wall | 0.024s | 98% | 0.025s (-4.0%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "/<funcName>\(\)"`. Within-suite parallelism is unchanged from v1.6 (each row was filtered to one test in isolation to remove parallel-suite contention). CI may show different absolute numbers (different runner hardware) — the §13 contract gates regression magnitude, not absolute parity with this baseline.

## Notes on movement vs v1.6

**Six of seven rows are within ±5% of v1.6 — the v1.7 plan's "flat" projection mostly confirmed.** The one outlier is Row 1a at +7.1%. Detail below.

**Row 1a (+7.1%) — slightly above the ±5% noise band but well below the 25% hard-gate.** Three repeat measurements at the V1.7.3 commit produced 0.527s / 0.533s / 0.536s — the floor moved up from v1.6's 0.495s by about 35ms. Hypotheses:
- *Bake-in cost.* V1.7.1 adds 14 dict-write seedings to `inheritedTypesIndex(...)` per `discover()` call (one-time, ~microseconds). Each `coverageVetoSignal(...)` call now finds non-empty inherited sets on stdlib type lookups, triggering a 10-element `Set<String>.sorted()` per call. For a 50-file synthetic corpus with ~50 functions × hundreds of pair-formation candidates, this could add a few thousand sort operations. At ns-scale per sort, total added work is sub-millisecond — does *not* explain +35ms.
- *Synthetic corpus type mix.* The synthetic corpus generator likely uses non-stdlib synthetic type names (`Foo123`, etc.); the bake-in's reach wouldn't fire on most lookups. The hot path is unchanged.
- *Machine-thermal noise.* The most likely explanation. The 50-file synthetic test is a 0.5-second wall measurement on an Apple M1 with active thermal management; ±50ms is within typical single-shot variance during a ~10-minute calibration session. v1.6 → v1.5's +0.6% was suspiciously low; v1.7's +7.1% may simply revert toward the broader trend.

The hard 2.0s budget gives 73% headroom either way. Re-measuring at v1.7.0 release-tag time would either confirm the floor moved (in which case the next commit's regression gate operates against 0.530s) or reveal that v1.6's 0.495s was the outlier. **Documenting at 0.530s as the v1.7 baseline.**

**Row 1b (+4.0%) and Row 3 (+3.0%)** are within machine-variance — same posture as v1.6's similar deltas vs v1.5.

**Row 1c, Row 2 (+1.5% / +1.6%):** Within machine-variance. Both well below their hard budgets (52% / 69% headroom). The v1.6.1 flake-resistant 4.0s budget on Row 2 holds with margin to spare on local Apple M1.

**Row 4 (memory delta) effectively unchanged at 135.5 MB (+0.5%) vs v1.6's 134.8 MB.** Direction matches the v1.7 plan's V1.7.4 prediction ("Numbers expected to be flat — the bake-in is a constant-cost merge per `inheritedTypesIndex(...)` call"). The +0.7 MB swing is noise on a 130-MB-scale measurement; the bake-in's seeded 14-dict-entry overhead is well below a single Suggestion struct's memory footprint.

**Row 5 (-4.0%) is machine-variance.** Identical-scale movement to v1.6's +4.2% (24ms ↔ 25ms = ±1ms = ±4% on the 1ms-precision single-shot measurement). Treating as noise, same posture as v1.6's +4.2% / v1.5's +4.2% / v1.4's -4.0% / v1.3's +4.2%.

**The cycle-4 corpus measurements (`docs/calibration-cycle-4-data/post-bakein-*.discover.txt`) provide an independent confirmation of per-corpus cost.** All four corpus discovers ran under the same release binary in single-digit seconds; the cycle-4 capture didn't reveal any regression-class slowdowns.

## Budget changes vs v1.6

**None at v1.7.0.** The V1.6.1 maintenance patch's flake-resistant budget bumps for Row 2 (4.0s) + the 100-file pipeline integration test (6.0s) carry forward unchanged. See v1.6 baseline's Re-baselining log for the per-test history.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms, capturing the running peak. The reported number is **delta over the pre-discover baseline** sampled immediately before `TemplateRegistry.discover(in:)` runs. The diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` is unconditional on every run — for v1.7 this captured `peakDeltaMB=135.5 baselineMB=50.2 budgetMB=800.0`.

## §13 row 5 — measurement methodology (unchanged from v0.1.0 + v1.1 + v1.2 + v1.3 + v1.4 + v1.5 + v1.6)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. PRD §13 row 5 wording is "after process start"; the ~10ms `main` → `AsyncParsableCommand` dispatch overhead between OS process start and `Discover.run` entry is not testable from inside the package. Open decision #2 in `docs/archive/v0.1.0 Release Plan.md` documents the gap.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. The Swift Testing assertions in each suite use the hard budget as the gate; PR-time soft regression detection (the 25% rule) remains a post-v1.7 concern (would need a checked-in golden of these numbers + a comparison harness; not on the v1.7 critical path — same posture as v0.1.0 + v1.1 + v1.2 + v1.3 + v1.4 + v1.5 + v1.6).

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation, update the **Measured** column above, and reference the commit + the PR that caused the shift in a new "## Re-baselining log" section at the bottom of this file. Do not delete prior measurements — the regression rule operates against the most recent committed baseline.
