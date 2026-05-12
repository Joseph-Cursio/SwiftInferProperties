# SwiftInferProperties — v1.47 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-12 against the V1.47.H commit. v1.47 ships the
third cycle of the Phase 1.5 verifiable-fraction expansion arc and
the first **carrier-arm expansion** after v1.45 + v1.46 closed the
four-template arc: **DerivationStrategist verify-time integration**
with `GenericBindingResolver` for generic associated-type carriers
(Base.Index → Int via Array<Int>) and `StrategistDispatchEmitter`
covering 5 strategy outcomes × 4 template arms.

**Discover-pipeline impact: minimal.** v1.47 adds one new lookup in
`IndexCommand.buildEntry` — `typeShapesByName[bareTypeName]` — which
is an O(1) dictionary lookup against an in-memory map already built
during the pipeline's `TypeShapeBuilder.shapes(from:)` call. The §13
discover budgets (1s / 2s / 6s for 10 / 50 / 100 test-file synthetic
corpora; 800 MB peak-delta for the 500-file corpus) are unchanged
from v1.41–v1.46.

**Test-suite measurement:** **2332 tests** passing across **314 suites**.
Full `swift test` completes in ~170s, up from v1.46's ~160s — the four
new V1.47.G.6 integration tests (`strategist × Int / String / bound
carrier / .todo`) each spawn a real `swift build` of a synthesized
verifier workdir. 16 total subprocess-based integration tests now run
in parallel (3 V1.42.D round-trip + 3 V1.44.E.3 idempotence + 3
V1.45.E.3 commutativity + 3 V1.46.D.4 associativity + 4 V1.47.G.6
strategist-routed). Wall-clock dominated by SwiftPM dependency
resolution + the kit's cold compile under contention. A re-run after
the SwiftPM cache warms typically lands closer to ~95s.

New tests since v1.46: 6 in `IndexedTypeShapeTests` (V1.47.A) + 4 in
`SemanticIndexEntryTests` V1.47.B JSON migration + 6 in
`IndexCommandBuildEntryTests` V1.47.C typeShape population + 6 in
`GenericBindingResolverTests` (V1.47.D) + 15 in
`StrategistDispatchEmitterTests` (V1.47.E) + 3 in
`VerifyPipelineIntegrationTests` V1.47.G.6 = 44 net new tests +
0 deleted = 2288 → 2332 (+44). The plan projected ~50; the variance
is 6 fewer tests in the StrategistDispatchEmitter suite (the 5-strategy
× 4-template matrix collapsed across recipe-shared cases).

**Per-verify-call cost:** **~13s cold** (unchanged from v1.43–v1.46).
Strategist-routed verify calls add <30ms over the v1.46 hardcoded
emitters given the strategist call itself is microsecond-scale
(`DerivationStrategist.strategy(for: shape)`) and the per-strategy
recipe is small inline composition. Direct-RawType fast path
(carrier == "Int" / "String" / etc.) doesn't even invoke the
strategist — same cost as v1.46.

**§13 budget compliance:** all v1.41–v1.46 measurements hold. v1.47's
new V1.47.G.6 integration tests sit in the same target as V1.42.D /
V1.44.E / V1.45.E / V1.46.D.4 — not subject to a §13 budget.

**Per-trial-budget cost (in stub, post-build):** at N=100 the 4-template
× expanded-carrier matrix (now ~16 distinct stub variants across the
v1.46 hardcoded + strategist-routed paths) completes in <130ms total.
Strategist-routed stubs have simpler bodies than v1.46's Complex<Double>
two-pass (no `rawStorage` scan, no per-slot rotation) so per-stub cost
is lower; the extra ~10ms vs v1.46 comes from the additional carriers
running, not per-stub overhead.

**§13 perf-test flake (carry-forward, now more frequent).** The
v1.45-documented `Discover pipeline on 100 test files < 6s` test
contended with 12 parallel subprocess builds at v1.46 and 16 at
v1.47 — the perf test occasionally surfaces an 8-9s elapsed reading
(vs 6s budget) under that contention. Isolated re-runs land at 2s.
**Mitigation options for v1.48** (none applied yet):
(1) split subprocess-integration tests into a separate `swift test
--filter` invocation outside the default suite, (2) widen the §13
budget on perf tests when run alongside `.integration` tests, or
(3) serialize the subprocess builders via a test-time semaphore.
Cycle-44 measurement was unaffected — the flake is a CI/test-harness
contention concern, not a v1.47 correctness regression.

**No regressions across the v1.46 paths.** All 30 V1.46.D.4-and-earlier
integration tests (round-trip + idempotence + commutativity +
associativity × {Complex<Double>, Double, Int}) pass unchanged on the
v1.47 surface. The V1.47.F two-arm router routes those carriers to
the v1.46 hardcoded path identically to v1.46.

**No new bugs surfaced during V1.47.G.6 integration testing.** The
strategist-routed Int + String + bound-carrier paths all built and
ran clean on the first end-to-end attempt. The `.todo` strategy
correctly throws `.unsupportedCarrier` from the emitter (asserted
at the emitter level — no deliberately-failed subprocess build).

v1.47 baseline replaces v1.46 as the comparison anchor for v1.48+.
