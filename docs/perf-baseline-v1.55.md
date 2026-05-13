# SwiftInferProperties — v1.55 Performance Baseline (Phase 2; fifth gap-closing cycle)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-13 against the V1.55.A commit. v1.55 ships one
workstream (A: per-function default-pass domain for Complex round-trip)
+ cycle-52 measurement + standard closeout.

**Discover-pipeline impact: none.** v1.55 introduces zero discover-
side changes. The §13 discover budgets stay unchanged from v1.41-v1.54.

**Test-suite measurement (non-subprocess fast path):** **2396 tests**
passing across **333 suites** in **~4 seconds** when running
`swift test --skip VerifyPipelineIntegrationTests`. Full default
suite runs ~210s (21 subprocess integration tests unchanged from v1.49).

**Test count unchanged from v1.54** (2396). V1.55.A's per-function
domain table is exercised end-to-end by the cycle-52 measurement; no
dedicated V1.55.D unit tests in this cycle. v1.56 may add coverage
for `complexDefaultPassDomain(forwardCall:)` returning the right
range per function name.

**Per-survey-run cost (V1.55 cycle-52 measurement):** **~5 minutes**
wall-clock for the full 109-pick survey via `swift-infer verify
--all-from-index --max-parallel 4` (matched cycles 50-51). The 8
picks now reaching the edge-pass do additional property-check work
(default pass 100/100 + edge pass first-fail), but on average this
is offset by build-cache reuse.

Projected v1.56+ cost: ~5-6 min once the next workstream lands. The
20-pick measurable sample is stable and the survey wall-clock is
dominated by build-step caching, not property-check execution.

**Per-verify-call cost (single suggestion):** **~13-15s cold**
(unchanged from v1.54). V1.55.A's domain-lookup adds <1ms in-process;
the change is purely string-interpolation into the emitted stub.

**§13 budget compliance:** all v1.41-v1.54 measurements hold. v1.55
added zero subprocess integration tests; the §13 perf measurements
stayed within v1.51-v1.54 bounds across the cycle's `swift test
--skip VerifyPipelineIntegrationTests` runs.

**Survey wall-clock model (v1.55):**
- `--max-parallel 4` (default): ~5 min for the 109-pick cycle-27
  fixture (20 picks reach property check; 2 build-failed; 87 fail
  at resolution → fast).
- Cycle-53 trajectory (v1.56 closes TypeShape work + relaxedMul/
  rescaledDivide builds + chunked-Index instance methods): expect
  30-40 picks running property check → ~7-10 min wall-clock.

**Phase 2 cycle-52 measurement summary**: **20 / 109 = 18.3%
measured-execution** (`.bothPass` + `.defaultFails` + `.edgeCaseAdvisory`,
excluding error). Count unchanged from cycle-51; category quality
substantially improved — 8 picks shifted from misleading
`.defaultFails` to correct `.edgeCaseAdvisory`. **First non-zero
`.edgeCaseAdvisory` measurement** in the project's calibration
history (v1.43's advisory design now produces its intended outcomes
at scale).

**32-pick sample-subset agreement with cycle-46**:
- Strict 4-category match: 5/13 = 38%
- Semantic "property holds" match: 13/13 = **100%**

Both numbers are informative. The strict-match number reveals that
`.edgeCaseAdvisory` is a real outcome class cycle-46's 4-category
prediction didn't enumerate. The semantic-match confirms the
architecture identifies the right algebraic outcome at the
structural level.

v1.55 baseline is the Phase 2 generator-tuned-and-advisory-emergent
reference point.
