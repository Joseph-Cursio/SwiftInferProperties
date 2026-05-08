# SwiftInferProperties — v1.5 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.5+ — the measured wall numbers (and one resident-memory delta) for every §13 row at the v1.5 commit. Future PRs that move any number more than 25% over the baseline below should be treated as a release blocker per §13's last paragraph. The v1.4 baseline (`docs/perf-baseline-v1.4.md`) is retained for forensic comparison across the cycle-2 calibration trajectory but is no longer the regression gate. The v1.3 (`docs/perf-baseline-v1.3.md`) / v1.2 (`docs/perf-baseline-v1.2.md`) / v1.1 (`docs/perf-baseline-v1.1.md`) / v0.1.0 (`docs/perf-baseline-v0.1.md`) baselines are also retained for the longer trajectory window.

**Captured:** 2026-05-08 against `main` HEAD `79ad26a` + the V1.5.0–V1.5.4 working copy (V1.5.5 pre-commit).
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.4 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover (all 8 templates active + contradiction pass) | < 2.0s wall | 0.492s | 75% | 0.493s (-0.2%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with `.swiftinfer/decisions.json` load | < 2.0s wall | 1.467s | 27% | 1.455s (+0.8%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` (44 .swift files) | < 3.0s wall (see note) | 1.399s | 53% | 1.404s (-0.4%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files (six detectors + chain-detector pass) | < 3.0s wall | 1.224s | 59% | 1.225s (-0.1%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run after one-file change (10-file corpus) | < 0.5s wall | 0.100s | 80% | 0.101s (-1.0%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB (post-v1.1.0 calibration) | 134.6 MB local | 83% | 136.0 MB (-1.0%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency (5-file corpus) | < 1.0s wall | 0.024s | 98% | 0.025s (-4.0%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "/<funcName>\(\)"`. Within-suite parallelism is unchanged from v1.4 (each row was filtered to one test in isolation to remove parallel-suite contention). CI may show different absolute numbers (different runner hardware) — the §13 contract gates regression magnitude, not absolute parity with this baseline.

## Notes on movement vs v1.4

**All seven rows are within ±5% of v1.4 — the predicted "flat or slightly improved" outcome.** The v1.5 plan's V1.5.5 budget projection predicted exactly this shape: the protocol-coverage veto adds a per-suggestion table-lookup cost (O(|inheritedTypes|) ≈ 1–4 String hash lookups per candidate type), but suppressed suggestions skip downstream Suggestion-struct allocation, so the net effect should be flat or slightly negative on all rows.

**Row 1a–1c, 2, 3 — discover wall (-0.2% / +0.8% / -0.4% / -0.1% / -1.0%):** All within machine-variance of v1.4. The added per-summary work is the `protocolCoverageVeto(...)` call against the `[String: Set<String>]` index — for the 50-file synthetic corpus that's ≤ 50 lookups per template per pass (most return `nil` after a single hash miss because the synthetic types don't carry kit-relevant conformances). Net cost is well under the noise floor.

**Row 4 (memory delta) drops 136.0 → 134.6 MB (-1.0%).** Direction matches the v1.5 plan's V1.5.5 prediction ("Row 4 memory may drop further"). The veto stops Suggestion-struct allocation for any additionally-suppressed candidates in the synthetic-500 corpus, mirroring the much-larger V1.4.3b-driven drop in v1.4 (551.8 → 136.0 MB, -75.4%). v1.5's contribution is small in absolute MB because (a) the synthetic corpus's types mostly don't carry the kit-relevant inheritance clauses that drive the veto, and (b) v1.4 already cleared the bulk of the cross-type round-trip allocation pressure.

**Row 5 (-4.0%) is machine-variance.** Row 5 is sensitive to fixture-corpus + harness setup variance (25ms → 24ms is a 1ms delta on a single-shot measurement). Treating as noise, same posture as v1.4's +4.2%.

**The cycle-2 corpus measurements (`docs/calibration-cycle-2-data/post-rule-*.discover.txt`) provide an independent confirmation of the per-corpus cost.** All four corpus discovers ran under the same release binary in single-digit seconds; the cycle-2 capture didn't reveal any regression-class slowdowns.

## Budget changes vs v1.4

None. All §13 budgets are unchanged from the post-v1.1.0 calibration (row 4 ceiling = 800 MB; all other rows at their v0.1.0 budgets, with row 1c's flake-resistant 3.0s budget unchanged from v1.1).

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms, capturing the running peak. The reported number is **delta over the pre-discover baseline** sampled immediately before `TemplateRegistry.discover(in:)` runs. The diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` is unconditional on every run — for v1.5 this captured `peakDeltaMB=134.6 baselineMB=50.0 budgetMB=800.0`.

## §13 row 5 — measurement methodology (unchanged from v0.1.0 + v1.1 + v1.2 + v1.3 + v1.4)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. PRD §13 row 5 wording is "after process start"; the ~10ms `main` → `AsyncParsableCommand` dispatch overhead between OS process start and `Discover.run` entry is not testable from inside the package. Open decision #2 in `docs/archive/v0.1.0 Release Plan.md` documents the gap.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. The Swift Testing assertions in each suite use the hard budget as the gate; PR-time soft regression detection (the 25% rule) remains a post-v1.5 concern (would need a checked-in golden of these numbers + a comparison harness; not on the v1.5 critical path — same posture as v0.1.0 + v1.1 + v1.2 + v1.3 + v1.4).

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation, update the **Measured** column above, and reference the commit + the PR that caused the shift in a new "## Re-baselining log" section at the bottom of this file. Do not delete prior measurements — the regression rule operates against the most recent committed baseline.
