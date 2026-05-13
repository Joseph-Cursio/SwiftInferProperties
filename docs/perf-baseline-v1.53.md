# SwiftInferProperties — v1.53 Performance Baseline (Phase 2; third gap-closing cycle)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-13 against the V1.53.A commit. v1.53 ships a
single workstream (V1.53.A `DYLD_LIBRARY_PATH` injection on verifier
subprocess) + the cycle-50 measurement + standard closeout. ~80 LoC
in `VerifierSubprocess.swift`; no test additions beyond what cycle-50
verifies end-to-end.

**Discover-pipeline impact: none.** v1.53 introduces zero discover-
side changes. The §13 discover budgets stay unchanged from v1.41-v1.52.

**Test-suite measurement (non-subprocess fast path):** **2399 tests**
passing across **333 suites** in **~4 seconds** when running
`swift test --skip VerifyPipelineIntegrationTests`. Full default
suite runs ~210s (21 subprocess integration tests unchanged from v1.49).

**Test count unchanged from v1.52** (2399). V1.53.A is exercised
indirectly by the V1_51EndToEndFromIndexTests and the cycle-50
measurement; no dedicated V1.53.D unit tests in this cycle. V1.54
should add coverage for `environmentWithTestingLibraryPath()` returning
a path with libTesting on hosts where the toolchain is detectable.

**Per-survey-run cost (V1.53 cycle-50 measurement):** **~5 minutes**
wall-clock for the full 109-pick survey via `swift-infer verify
--all-from-index --max-parallel 4` against the cycle-27 fixture (vs
cycle-49's ~4 min). The +1 min reflects the 12 picks now running
their full trial-budget property check (N=100 default trials per pick,
plus the edge pass for FP carriers).

Projected v1.54+ cost: with V1.52.A free-function revert + V1.52.C
key fix landing, expect another +8-11 picks reaching property check,
adding ~30s wall-clock. Steady-state survey wall-clock: ~5-7 min for
the 109-pick surface.

**Per-verify-call cost (single suggestion):** **~13-15s cold** (slight
increase from v1.52's ~13s — the `swift -print-target-info` lookup
adds ~50ms on first call, then cached). v1.53's caching mechanism
amortizes the lookup to 0.05ms per pick on the survey.

**§13 budget compliance:** all v1.41-v1.52 measurements hold. v1.53
added zero subprocess integration tests; the §13 perf measurements
stayed within v1.51-v1.52 bounds across two `swift test --skip
VerifyPipelineIntegrationTests` runs (4.0-4.3s wall-clock).

**Survey wall-clock model (v1.53):**
- `--max-parallel 4` (default): ~5 min for the 109-pick cycle-27
  fixture (12 picks reach property check; 10 build-failed; 87 fail
  at resolution → fast).
- Cycle-51 trajectory (v1.54 closes V1.52.A regressions + V1.52.C
  key fix): expect 18-25 picks running the property check → ~6-8 min
  wall-clock.

**Phase 2 cycle-50 measurement summary**: **12 / 109 = 11.0%
measured-execution** (`.bothPass` + `.defaultFails`, excluding error).
**First non-zero measurement in the project's calibration history.**
6 `.bothPass` + 6 `.defaultFails`. All 12 produced mathematically
valid outcomes (commutative/associative operations pass; non-commutative/
non-associative operations fail). Per-pick agreement-rate on cycle-50
= 12/12 = 100%; cycle-46-vs-cycle-50 sample-subset overlap = 5/5 = 100%.

V1.53.A is the single highest-impact workstream since the v1.18-v1.29
mechanism cycles hit §19 ≥70%. 80 LoC closed +12 measured outcomes
at 6.7 LoC per pick. Cycle-50 evidence calls for v1.54 to revert
V1.52.A's free-function classification (8 regression candidates) and
fix V1.52.C's key format (3 chunked-Index picks); both are mechanical.

v1.53 baseline is the Phase 2 first-measurement reference point.
