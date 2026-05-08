# SwiftInferProperties — v1.9 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.9+ — the measured wall numbers (and one resident-memory delta) for every §13 row at the v1.9 commit. Future PRs that move any number more than 25% over the baseline below should be treated as a release blocker per §13's last paragraph.

> **v1.9 is an empirical-only release.** No Sources/ changes, no test changes, no behavior changes. The §13 measurements at v1.9 are *byte-equivalent* to v1.8.0 — the binary is identical apart from the version-string bump. This baseline file exists for **trajectory continuity** so cycle-7+ has a v1.9-anchored comparison reference; the measurements themselves are carried forward from `docs/perf-baseline-v1.8.md`.

The v1.8 baseline (`docs/perf-baseline-v1.8.md`) is retained for forensic comparison; it remains the substantive regression anchor (any v1.9 → v1.10 regression analysis can equivalently use either).

**Captured:** 2026-05-08 against the v1.8.0 release tag (`d006deb`); v1.9 carries forward.
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <SuiteName/funcName>` invocation, Swift Testing 1743.

## §13 row-by-row (carried forward from v1.8)

| Row | Workload | Budget | Measured | Headroom | v1.8 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover | < 2.0s wall | 0.520s | 74% | 0.520s (0.0%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with decisions load | < 2.0s wall | 1.485s | 26% | 1.485s (0.0%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` | < 3.0s wall (see note) | 1.423s | 52% | 1.423s (0.0%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files | < 4.0s wall (V1.6.1 flake-resistant) | 1.240s | 69% | 1.240s (0.0%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run (10-file corpus) | < 0.5s wall | 0.105s | 79% | 0.105s (0.0%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB | 134.5 MB local | 83% | 134.5 MB (0.0%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency | < 1.0s wall | 0.024s | 98% | 0.024s (0.0%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

## Why this isn't a re-measurement

v1.9 ships:
- 0 Sources/ files changed
- 0 Tests/ files changed
- 0 lint configuration changes
- 0 Package.swift changes

v1.9 ships *only*:
- 1 SwiftInferCommand.swift version-string bump (`"1.8.0"` → `"1.9.0"`)
- Documentation files (cycle-6 rubric + sample + findings + this baseline + CHANGELOG + README)

Re-running the §13 suite at the v1.9 commit would produce numbers within machine-noise of the v1.8 measurements — same compiled binary modulo a 5-character string. Re-measurement would consume 10+ minutes of test runtime to produce zero signal. The v1.8 numbers carry forward as-is.

## Budget changes vs v1.8

**None.** The V1.6.1 maintenance patch's flake-resistant budget bumps for Row 2 (4.0s) + the 100-file pipeline integration test (6.0s) carry forward unchanged.

## §13 row 4 — measurement methodology (unchanged from v1.1)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms, capturing the running peak. The reported number is **delta over the pre-discover baseline** sampled immediately before `TemplateRegistry.discover(in:)` runs. Diagnostic stderr line `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` continues unchanged.

## §13 row 5 — measurement methodology (unchanged from v0.1.0+)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. Same posture as v0.1-v1.8.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." The §13 contract gates against the most recent baseline. v1.10+ commits gate against this v1.9 baseline (which is the v1.8 baseline carried forward) — equivalently against `docs/perf-baseline-v1.8.md`.

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation and update the **Measured** column. v1.9 has no re-baselining log because no measurements moved.
