# SwiftInferProperties — v1.54 Performance Baseline (Phase 2; fourth gap-closing cycle)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-13 against the V1.54.A-C commit. v1.54 ships
three workstreams (A: free-function revert; B: V1.52.C dead-binding
cleanup; C: RealModule import for FP strategist recipes) + cycle-51
measurement + standard closeout.

**Discover-pipeline impact: none.** v1.54 introduces zero discover-
side changes. The §13 discover budgets stay unchanged from v1.41-v1.53.

**Test-suite measurement (non-subprocess fast path):** **2396 tests**
passing across **333 suites** in **~4 seconds** when running
`swift test --skip VerifyPipelineIntegrationTests`. Full default
suite runs ~210s (21 subprocess integration tests unchanged from v1.49).

**Test count -3 vs v1.53 (2399 → 2396)** — V1.54.B replaced the
6-test V1_52GenericBindingExpansionTests suite with a 3-test
V1_54GenericBindingExpansionTests suite. The lost coverage was tests
of the V1.52.C `<Type>.Index` bindings which were dead code; the
remaining 3 tests cover dead-keys-removed assertion + V1.47.D/V1.51.A
regression guard + bare-type pass-through. Net coverage is unchanged.

**Per-survey-run cost (V1.54 cycle-51 measurement):** **~5 minutes**
wall-clock for the full 109-pick survey via `swift-infer verify
--all-from-index --max-parallel 4` against the cycle-27 fixture
(matched cycle-50 ~5 min). The 8 newly-reaching-runtime picks added
~30s of property-check work, offset by build-cache reuse.

Projected v1.55 cost: ~5-6 min once generator-range refinement (per
cycle-51 finding) lands; the existing 20-pick reaching-runtime sample
should grow only modestly until TypeShape-driven OC instantiation
unblocks the 60+ pending picks (v1.55-v1.56 scope).

**Per-verify-call cost (single suggestion):** **~13-15s cold**
(unchanged from v1.53). V1.54.C's RealModule import adds ~50ms to
the FP-carrier build step (one additional module to resolve); negligible.

**§13 budget compliance:** all v1.41-v1.53 measurements hold. v1.54
added zero subprocess integration tests; the V1.54.A test updates
are pure-Swift parse-and-encode coverage. §13 perf measurements
stayed within v1.51-v1.53 bounds across the cycle's two
`swift test --skip VerifyPipelineIntegrationTests` runs (3.99-4.07s).

**Survey wall-clock model (v1.54):**
- `--max-parallel 4` (default): ~5 min for the 109-pick cycle-27
  fixture (20 picks reach property check; 2 build-failed; 87 fail
  at resolution → fast).
- Cycle-52 trajectory (v1.55 closes generator-range + chunked-Index
  + relaxedMul builds): expect 25-30 picks running property check →
  ~6-7 min wall-clock.

**Phase 2 cycle-51 measurement summary**: **20 / 109 = 18.3%
measured-execution** (`.bothPass` + `.defaultFails`, excluding error).
+8 vs cycle-50 (V1.54.A free-function revert restored 8 round-trip
Complex EF picks to runtime). All 8 newly-measured picks landed in
`.defaultFails` due to the v1.42 generator's `Double.random(in:
-1e6 ... 1e6)` range exceeding `exp`/`sinh`/`cosh`/`tanh`'s stable
domain — a generator-tuning finding, not a verifier-correctness
issue. Per-pick **mathematical-correctness rate**: 12/13 = 92% on
the 32-pick sample subset; **semantic-domain match rate**: 5/13 =
38% (the 8 mismatches are all generator-range overflows).

V1.54.A's revert pays off as designed. V1.54.B's dead-binding cleanup
is silent but correct. V1.54.C's RealModule import is load-bearing
(prevented a 2-pick regression caught at smoke-test stage).

v1.54 baseline is the Phase 2 generator-tuning-gap-surfaced
reference point.
