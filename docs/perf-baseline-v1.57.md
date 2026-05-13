# SwiftInferProperties — v1.57 Performance Baseline (Phase 2; seventh gap-closing cycle)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-13 against the V1.57.A commit + cycle-27 fixture
rebuild. v1.57 ships one workstream (A: `private`/`fileprivate`
FunctionScanner filter + fixture rebuild) + cycle-54 measurement +
standard closeout.

**Discover-pipeline impact: small but real.** V1.57.A's filter
skips `private`/`fileprivate` declarations at scan time; future
`swift-infer index` runs on user codebases will produce slightly
smaller indexes than pre-v1.57. For the cycle-27 corpus the impact
is 6 picks dropped (109 → 103). The §13 discover budgets stay
unchanged from v1.41-v1.56.

**Test-suite measurement (non-subprocess fast path):** **2403 tests**
passing across **334 suites** in **~4 seconds** when running
`swift test --skip VerifyPipelineIntegrationTests`. Full default
suite runs ~210s (21 subprocess integration tests unchanged from v1.49).

**Test count +1 vs v1.56** (2402 → 2403). V1.57.A added 1 unit test
for the scanner filter (synthetic source with 5 functions → 3
captured, 2 skipped per modifier).

**Per-survey-run cost (V1.57 cycle-54 measurement):** **~4-5 minutes**
wall-clock for the full 103-pick survey via `swift-infer verify
--all-from-index --max-parallel 4`. Slight drop from cycle-50/52/53's
~5 min — 6 fewer picks to iterate. The dropped picks were fast-failing
at carrier resolution; the elimination saves only seconds.

Projected v1.58+ cost: similar baseline ~4-5 min until TypeShape work
adds property-check execution for the 60+ OC + Algo picks.

**Per-verify-call cost (single suggestion):** **~13-15s cold**
(unchanged from v1.56). V1.57.A is scan-time only; no verify-time
impact.

**§13 budget compliance:** all v1.41-v1.56 measurements hold. v1.57
added zero subprocess integration tests; V1.57.A's unit test is
pure-Swift SwiftSyntax parsing. §13 perf measurements stayed within
v1.51-v1.56 bounds.

**Survey wall-clock model (v1.57):**
- `--max-parallel 4` (default): ~4-5 min for the **103-pick** cycle-27
  fixture (20 picks reach property check; 0 build-failed; 83 fail
  at resolution → fast).
- Cycle-55 trajectory (v1.58 starts TypeShape work): expect +10-20
  picks reaching property check → ~6-8 min wall-clock as TypeShape
  picks compile + run.

**Phase 2 cycle-54 measurement summary**: **20 / 103 = 19.4%
measured-execution** (`.bothPass` + `.defaultFails` + `.edgeCaseAdvisory`,
excluding error). Total measured count unchanged from cycles 50-53;
**denominator shifts 109 → 103** due to V1.57.A's filter dropping
6 file-private declarations from SwiftPropertyLaws (3 cycle-53
`(none)`-typeName picks + 3 `private static` ViolationFormatter
members).

**Methodologically clean baseline correction.** The 6 dropped picks
were artifacts of the v1.29-era scanner over-collecting non-public
declarations; they violated cross-module visibility and couldn't
produce valid measurements regardless of verifier capabilities. v1.57+
baseline reflects what's actually verifiable in the cycle-27 corpus.

**32-pick sample-subset agreement with cycle-46**: unchanged from
cycle-53:
- Strict 4-category match: 5/13 = 38%
- Semantic "property holds" match: 13/13 = **100%**

None of the dropped picks were in the cycle-46 stratified subset.

v1.57 baseline is the Phase 2 cleaner-baseline reference point.
