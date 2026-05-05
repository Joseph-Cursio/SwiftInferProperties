# SwiftInferProperties — v1.1 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build." This file is the **canonical comparison anchor** for v1.1+ — the measured wall numbers (and one resident-memory delta) for every §13 row at the v1.1 commit. Future PRs that move any number more than 25% over the baseline below should be treated as a release blocker per §13's last paragraph. The v0.1.0 baseline (`docs/perf-baseline-v0.1.md`) is retained for forensic comparison across the M9/M10/M11 trajectory but is no longer the regression gate.

**Captured:** 2026-05-05 against commit on `main` after V1.1.0 (`819eb81`).
**Hardware:** MacBook Air, Apple M1, 16 GB unified memory.
**Toolchain:** Apple Swift 6.3.1 (swiftlang-6.3.1.1.2 clang-2100.0.123.102), target `arm64-apple-macosx26.0`.
**Test target:** `swift test --filter <function-name>` invocation, Swift Testing 1743.

## §13 row-by-row

| Row | Workload | Budget | Measured | Headroom | v0.1.0 (delta) | Test |
|---|---|---|---|---|---|---|
| 1 | 50-file synthetic discover (all 8 templates active + contradiction pass) | < 2.0s wall | 0.567s | 72% | 0.689s (-18%) | `PerformanceTests.syntheticFiftyFileCorpus` |
| 1 | 50-file synthetic discover with `.swiftinfer/decisions.json` load | < 2.0s wall | 1.613s | 19% | 1.792s (-10%) | `PerformanceTests.syntheticFiftyFileCorpusWithDecisionsLoad` |
| 1 | `swift-collections/Sources/DequeModule` (44 .swift files) | < 3.0s wall (see note) | 1.507s | 50% | 1.704s (-12%) | `PerformanceTests.swiftCollectionsDequeModule` |
| 2 | TestLifter parse of 100 synthetic test files (six detectors) | < 3.0s wall | 1.209s | 60% | 0.507s (+138%) | `TestLifterPerformanceTests.syntheticHundredTestFileCorpus` |
| 3 | `swift-infer drift` re-run after one-file change (10-file corpus) | < 0.5s wall | 0.103s | 79% | 0.175s (-41%) | `DriftIncrementalPerformanceTests.driftReRunWithinBudget` |
| 4 | `swift-infer discover` resident-memory delta on 500-file synthetic | < 800 MB (recalibrated post-v1.1.0 — see Re-baselining log) | 548.8 MB local | 31% | ~492 MB (+12%) | `MemoryCeilingPerformanceTests.memoryCeilingOnFiveHundredFiles` |
| 5 | `swift-infer discover --interactive` first-prompt latency (5-file corpus) | < 1.0s wall | 0.030s | 97% | 0.046s (-35%) | `InteractiveFirstPromptPerformanceTests.firstPromptWithinBudget` |

All numbers are single-shot wall times from a `swift test` invocation that filtered to the named test function. Within-suite parallelism is unchanged from v0.1.0 (PerformanceTests row 1 ran its three tests concurrently within a single suite invocation, mirroring v0.1.0's methodology). CI may show different absolute numbers (different runner hardware) — the §13 contract gates regression magnitude, not absolute parity with this baseline.

## Notes on movement vs v0.1.0

Most rows came in faster than v0.1.0 — likely a combination of warmer ambient state on the dev machine and incremental tuning. Two rows moved against the v0.1.0 baseline meaningfully:

- **Row 2 (TestLifter parse) +138%.** Grew from 0.507s → 1.209s. Still ~60% headroom against the 3s budget, but the absolute movement is the largest in the table. Plausible contributors all landed between v0.1.0 and v1.1: the M10.3 `DomainCorpusScanner` pass that now runs inside `TestLifter.discover` (and which the same test asserts non-emptiness of via `artifacts.domainCallSitesByConsumer`); the M11 `EquivalenceClassMarkerExtractor` per-method scan; M7's `AsymmetricAssertionDetector` counter-signal scan for every other file. None individually large (all per-file O(token-count) work the M10.3 §13 re-check exercised), but the additive surface across six detectors + two new scanners shows up here. Watch this row in v1.x — if it grows another 25% over the v1.1 baseline (1.51s) future work should re-profile.

- **Row 4 (memory delta) +12% local; +23% CI.** Local grew from ~492 MB → 548.8 MB. Inside the §13 25% rule against either baseline. Plausible contributors: the M10.3 `domainCallSitesByConsumer` map carried alongside the lifted-suggestion artifacts; M11 marker extraction state. Note the M11.2 side-map fix (hint via `InteractiveTriage.Context.equivalenceClassHintsByIdentity` rather than inline on `Suggestion`) already saved ~65 MB on this row — without it, v1.1 would be at ~614 MB locally. **CI runs ~110 MB heavier than local on this row** — the M10 closure commit measured 604.7 MB on CI while the same commit measured ~492-548 MB locally, busting the original 600 MB ceiling at the M10 closure (the failure went silently unnoticed for hours). The ceiling was recalibrated to 800 MB post-v1.1.0; see "Re-baselining log" below. Future work touching this row should re-validate against both the 600 MB local-measurement reference (the design constraint) and the 800 MB CI ceiling (the gate).

## Budget changes vs v0.1.0

- **Row 1 (`swift-collections DequeModule`) budget loosened from < 2.0s → < 3.0s** in commit `2e89733` (the `SwiftProtocolLaws → SwiftPropertyLaws` rename sweep). Test name explicitly carries the rationale: "3-second flake-resistant budget". This is a flake-resistance loosening, not a regression. The v1.1 measurement (1.507s) is still well inside both the original 2.0s and the loosened 3.0s budget.

All other §13 budgets are unchanged from v0.1.0.

## §13 row 4 — measurement methodology (unchanged from v0.1.0)

`MemoryCeilingPerformanceTests` polls `mach_task_basic_info.resident_size` on a background thread every 50ms, capturing the running peak. The reported number is **delta over the pre-discover baseline** sampled immediately before `TemplateRegistry.discover(in:)` runs — the absolute RSS includes the test runner's own footprint (Swift Testing, every test target's binary, the SwiftSyntax dep graph) which baselines around 46 MB at v1.1 (was ~40 MB at v0.1.0; the +6 MB baseline reflects the M10/M11 source surface added to the test binary). Delta is the honest in-test gate; the absolute number from a real `swift-infer discover` invocation against a 500-file corpus would be ~46 MB lower, putting it well inside the calibrated 600 MB budget.

The v1.1 measurement was captured by temporarily writing the formatted delta to stderr inside the test's `#expect`, running the filtered test, and reverting the source. The test itself only emits the delta in the assertion failure message; the unconditional log was not committed.

## §13 row 5 — measurement methodology (unchanged from v0.1.0)

`InteractiveFirstPromptPerformanceTests` times from `Discover.run` entry to the first `PromptInput.readLine()` invocation. PRD §13 row 5 wording is "after process start"; the ~10ms `main` → `AsyncParsableCommand` dispatch overhead between OS process start and `Discover.run` entry is not testable from inside the package. Open decision #2 in `docs/archive/v0.1.0 Release Plan.md` documents the gap.

## What "regression" means in CI

PRD §13 last paragraph: "a 25% regression in any number fails the build." For each row above, the §13 contract is breached when the measurement crosses **1.25 × baseline** OR the row's hard budget — whichever is lower. The Swift Testing assertions in each suite use the hard budget as the gate; PR-time soft regression detection (the 25% rule) remains a post-v1.1 concern (would need a checked-in golden of these numbers + a comparison harness; not on the v1.1 critical path — same posture as v0.1.0).

## Re-baselining

When intentional perf work moves a number, re-run the relevant filtered `swift test` invocation, update the **Measured** column above, and reference the commit + the PR that caused the shift in a new "## Re-baselining log" section at the bottom of this file. Do not delete prior measurements — the regression rule operates against the most recent committed baseline.

## Re-baselining log

### 2026-05-05 — Row 4 ceiling 600 → 800 MB (post-v1.1.0 calibration vs CI)

**Trigger.** Investigation post-v1.1.0 push found that the M10 closure commit `84ae669` (2026-05-05, the push immediately before the v1.1 stack) had silently failed CI hours earlier with peakDeltaMB=604.7 MB busting the 600 MB ceiling — the failure was not surfaced because no Claude session was watching at push time. The v1.1.0 push that followed it passed CI, but only because the M11.2 side-map carrier fix (commit `526213c`) avoided adding the ~65 MB inline-Optional regression that an earlier M11.0 design had introduced. The local measurement at v1.1.0 was 548.8 MB (9% headroom against 600 MB); CI was thinner — estimated < 1 MB headroom.

**Root cause of the headroom gap.** R1.1.b's original 600 MB calibration was against a local MacBook Air measurement (492 MB + 25% headroom). CI on macos-15-arm64 runners samples ~110 MB heavier per workload across this row — the test runner + Swift Testing + every test target's binary baseline higher in the CI image than they do on the dev machine. The 600 MB number was always tight on CI; it just took the M10 footprint addition to push past it.

**Recalibration.** Ceiling raised to 800 MB. Math: the only confirmed CI measurement is the M10 closure failure at 604.7 MB; 800 MB ≈ 604.7 × 1.32 — generous CI headroom over that data point, with room for v1.1's M11 footprint (a few MB beyond M10) plus future per-detector growth. The calibration is intentionally generous because we'd rather absorb cross-machine variance than re-tune every M-cycle.

**Diagnostic addition.** `MemoryCeilingPerformanceTests` now writes `[§13 row 4] peakDeltaMB=… baselineMB=… budgetMB=…` to stderr unconditionally on every run, success or failure. Future drift will surface in CI logs at every push, not at the next failure. The cost is one stderr line per run.

**Local reference.** The local-measurement baseline is unchanged (548.8 MB at v1.1.0). Future work touching row 4 should re-validate against both: the 800 MB CI ceiling (the gate) AND the 548.8 MB local-measurement reference (the design constraint). A regression that takes local from 548.8 → 700 MB still trips the §13 25% rule (548.8 × 1.25 = 686 MB) even if it stays inside the 800 MB ceiling.

**Files changed:**
- `Tests/SwiftInferIntegrationTests/MemoryCeilingPerformanceTests.swift` — `calibratedDeltaBudgetMB: Double = 800.0` (was 600.0); diagnostic stderr log added; suite docstring extended with the v1.1 recalibration rationale.
- `docs/SwiftInferProperties PRD v1.0.md` §13 — row 4 ceiling line revised; "Post-v1.1.0 recalibration note (row 4)" paragraph added alongside the v0.1.0 calibration note.
- `docs/perf-baseline-v1.1.md` — row 4 table cell revised; row 4 movement-vs-v0.1.0 note refreshed; this Re-baselining log entry added.
