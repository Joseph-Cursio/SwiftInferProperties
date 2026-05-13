# SwiftInferProperties — v1.56 Performance Baseline (Phase 2; sixth gap-closing cycle)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-13 against the V1.56.A+B commit. v1.56 ships
one workstream (A+B: internal-API build-failure reclassification +
unit tests) + cycle-53 measurement + standard closeout.

**Discover-pipeline impact: none.** v1.56 introduces zero discover-
side changes. The §13 discover budgets stay unchanged from v1.41-v1.55.

**Test-suite measurement (non-subprocess fast path):** **2402 tests**
passing across **334 suites** in **~4 seconds** when running
`swift test --skip VerifyPipelineIntegrationTests`. Full default
suite runs ~210s (21 subprocess integration tests unchanged from v1.49).

**Test count +6 vs v1.55** (2396 → 2402). V1.56.B added 6 tests for
the `architecturalPendingDetail(buildStdout:buildStderr:)` helper —
internal/private/fileprivate access-modifier variations, stdout vs
stderr stream detection, nil-returns for non-matching inputs.

**Per-survey-run cost (V1.56 cycle-53 measurement):** **~5 minutes**
wall-clock for the full 109-pick survey via `swift-infer verify
--all-from-index --max-parallel 4` (matched cycles 50-52). V1.56.A's
pattern check adds <1ms per build-failure path; negligible.

Projected v1.57+ cost: similar baseline ~5 min until TypeShape work
adds property-check execution for the 60+ OC picks. Once those reach
runtime, expect +5-10 min depending on per-pick trial budget.

**Per-verify-call cost (single suggestion):** **~13-15s cold**
(unchanged from v1.55). V1.56.A's pattern-match is pure-Swift in-
process; no extra subprocess overhead.

**§13 budget compliance:** all v1.41-v1.55 measurements hold. v1.56
added zero subprocess integration tests; V1.56.B's unit tests are
pure-Swift Substring matches. §13 perf measurements stayed within
v1.51-v1.55 bounds.

**Survey wall-clock model (v1.56):**
- `--max-parallel 4` (default): ~5 min for the 109-pick cycle-27
  fixture (20 picks reach property check; **0 build-failed (down
  from cycle-52's 2)**; 89 fail at resolution → fast).
- Cycle-54 trajectory (v1.57 starts TypeShape work): expect +5-15
  picks reaching property check → ~6-8 min wall-clock.

**Phase 2 cycle-53 measurement summary**: **20 / 109 = 18.3%
measured-execution** (`.bothPass` + `.defaultFails` + `.edgeCaseAdvisory`,
excluding error). Count unchanged from cycles 51-52; **`.measured-error`
count drops to 0** for the first time since the full-surface
measurement began at cycle-47. The 2 cycle-52 `rescaledDivide` picks
reclassify from `.measured-error` to `.architectural-coverage-pending`
with detail `"internal-api-not-accessible"`.

**The `.measured-error = 0` baseline is now a CI-able alarm.** Any
future cycle producing measured-error > 0 indicates an unexpected
build/runtime failure (not a known measurement-tooling gap),
motivating immediate investigation.

**32-pick sample-subset agreement with cycle-46**: unchanged from
cycle-52:
- Strict 4-category match: 5/13 = 38%
- Semantic "property holds" match: 13/13 = **100%**

V1.56.A's reclassification doesn't move picks in the 32-pick sample
(the 2 reclassified picks weren't in cycle-46's stratified subset).

v1.56 baseline is the Phase 2 clean-error-category reference point.
