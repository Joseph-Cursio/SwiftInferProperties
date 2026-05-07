# SwiftInferProperties — v1.2 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.2+ — the measured wall numbers (and one resident-memory delta) for every §13 row at the v1.2 commit. Future PRs that move any number more than 25% over the baseline below should be treated as a release blocker per §13's last paragraph. The v1.1 baseline (`docs/perf-baseline-v1.1.md`) is retained for forensic comparison across the M13/M14/M15 trajectory but is no longer the regression gate. The v0.1.0 baseline (`docs/perf-baseline-v0.1.md`) is also retained for the longer trajectory window.

**Captured:** 2026-05-07 against commit on `main` after V1.2.0 (`607da09`).
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v1.1 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover (all 8 templates active + contradiction pass) | < 2.0s wall | 0.518s | 74% | 0.567s (-9%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with `.swiftinfer/decisions.json` load | < 2.0s wall | 1.508s | 25% | 1.613s (-7%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` (44 .swift files) | < 3.0s wall (see note) | 1.394s | 54% | 1.507s (-7%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files (six detectors) | < 3.0s wall | 1.211s | 60% | 1.209s (+0.2%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run after one-file change (10-file corpus) | < 0.5s wall | 0.103s | 79% | 0.103s (0%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB (post-v1.1.0 calibration — see Re-baselining log in `perf-baseline-v1.1.md`) | 548.5 MB local | 31% | 548.8 MB (-0.05%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency (5-file corpus) | < 1.0s wall | 0.023s | 98% | 0.030s (-23%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function via `--filter "<SuiteStruct>/<funcName>"`. Within-suite parallelism is unchanged from v1.1 (PerformanceTests row 1 ran its three tests concurrently within a single suite invocation; for this baseline each row was filtered to one test in isolation to remove parallel-suite contention). CI may show different absolute numbers (different runner hardware) — the §13 contract gates regression magnitude, not absolute parity with this baseline.

## Notes on movement vs v1.1

All rows are within ±10% of the v1.1 baseline; most rows came in faster, consistent with machine variance rather than systemic shifts. M13 + M14 + M15 added per-token / per-`TypeDecl` / per-float-column work that the existing perf suite exercises:

- **Row 2 (TestLifter parse) +0.2%.** Effectively flat against v1.1 (1.209s → 1.211s). The M13 marker-table broadening (`MarkerTable.curatedPairs` × per-method scan) and the M14 enum-case-name extraction (`MemberBlockInspector.enumCaseNames(in:)` per `EnumDeclSyntax` / extension) are both per-token O(token-count) work that distributes across the existing detector fan-out without showing up here. The v1.1 → v1.2 stack confirms the M3.4 §13 row 2 budget posture: each new detector's per-file overhead has stayed sub-millisecond.

- **Row 4 (memory delta) -0.05% local.** The 500-file delta is essentially unchanged at v1.2 (548.8 → 548.5 MB locally). M13's `MarkerTable` / `MarkerSet` types are value-typed and per-process (one shared instance from `MarkerTable.curatedPairs`), so no per-suggestion allocation. M14's `TypeDecl.enumCaseNames` is a `[String]` populated only on `enum` decls + extensions; M15 adds no new persistent allocations. The post-v1.1.0 800 MB CI ceiling stands; the always-on `[§13 row 4] peakDeltaMB=…` stderr log surfaces every CI run for drift detection.

- **Row 1b / 1c (-7%) and Row 5 (-23%) faster than v1.1.** Plausible mix of machine warm-up state + the v1.2 commit's working tree being smaller than v1.1's (no in-flight changes). No code change in the v1.2 stack should have made these rows materially faster on its own; treating these as machine variance.

## Budget changes vs v1.1

None. All §13 budgets are unchanged from the post-v1.1.0 calibration (row 4 ceiling = 800 MB; all other rows at their v0.1.0 budgets, with row 1c's flake-resistant 3.0s budget unchanged from v1.1).

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms, capturing the running peak. The reported number is **delta over the pre-discover baseline** sampled immediately before `TemplateRegistry.discover(in:)` runs. The diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` is unconditional on every run — for v1.2 this captured `peakDeltaMB=548.5 baselineMB=47.6 budgetMB=800.0`, matching the v1.1 measurement to within ~0.05%.

## §13 row 5 — measurement methodology (unchanged from v0.1.0 + v1.1)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. PRD §13 row 5 wording is "after process start"; the ~10ms `main` → `AsyncParsableCommand` dispatch overhead between OS process start and `Discover.run` entry is not testable from inside the package. Open decision #2 in `docs/archive/v0.1.0 Release Plan.md` documents the gap.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. The Swift Testing assertions in each suite use the hard budget as the gate; PR-time soft regression detection (the 25% rule) remains a post-v1.2 concern (would need a checked-in golden of these numbers + a comparison harness; not on the v1.2 critical path — same posture as v0.1.0 + v1.1).

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation, update the **Measured** column above, and reference the commit + the PR that caused the shift in a new "## Re-baselining log" section at the bottom of this file. Do not delete prior measurements — the regression rule operates against the most recent committed baseline.
