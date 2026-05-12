# SwiftInferProperties — v1.45 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-12 against the V1.45.F commit. v1.45 ships the
first cycle of the Phase 1.5 verifiable-fraction expansion arc:
**commutativity verify support** (template + 3-carrier dispatch +
pair resolver + CLI dispatch + template-aware renderer) and the
**curated round-trip pair list expansion** (6 hyperbolic entries:
`sinh/asinh`, `cosh/acosh`, `tanh/atanh` bidirectional).

**Discover-pipeline impact: none.** v1.45 introduces no changes to the
discover / index / drift / metrics paths. The `verify` subcommand is
still an isolated entry point that consumes the SemanticIndex without
mutating it. The §13 discover budgets (1s / 2s / 6s for the 10 / 50 /
100 test-file synthetic corpora; 800 MB peak-delta for the 500-file
corpus) are unchanged from v1.41–v1.44.

**Test-suite measurement:** **2254 tests** passing across **307 suites**.
Full `swift test` completes in ~131s, up from v1.44's ~65s — the three
new V1.45.E.3 integration tests (`commutativity × Complex<Double> ×
bothPass`, `× Double × defaultFails`, `× Int × bothPass`) each spawn a
real `swift build` of a synthesized verifier workdir. With nine total
subprocess-based integration tests now running in parallel (3 V1.42.D
round-trip + 3 V1.44.E.3 idempotence + 3 V1.45.E.3 commutativity),
wall-clock is dominated by SwiftPM dependency resolution + the kit's
cold compile under contention. A re-run after the SwiftPM cache warms
typically lands closer to ~75s.

New tests since v1.44: 19 in `CommutativityStubEmitterTests` (V1.45.A)
+ 7 in `CommutativityPairResolverTests` (V1.45.B) + 3 in
`VerifyResultRendererCommutativityTests` (V1.45.C) + 3 in
`RoundTripPairResolverTests` for V1.45.D's hyperbolic pairs + 3 in
`VerifyPipelineIntegrationTests` (V1.45.E.3) = 35 net new tests.
*(Plus a -1 from a renamed VerifyResultRendererTests case, netting
the surface +34 vs the source-of-truth `2220 → 2254 = +34`.)*

**Per-verify-call cost:** **~12s cold** (unchanged from v1.43/v1.44).
Commutativity-verify calls add <50ms over idempotence given the same
stub-emission cost + a single extra generator draw per trial (two
values instead of one). Single-pass Int commutativity is fastest
(~1s warm). Measurements from a 2026 MacBook (M-series).

**§13 budget compliance:** all v1.41–v1.44 measurements hold. v1.45's
new V1.45.E integration tests sit in the same target as V1.42.D's
and V1.44.E's — not subject to a §13 budget. Verify itself is opt-in
and not on the discover hot path, so it doesn't enter the §13 surface
either.

**Per-trial-budget cost (in stub, post-build):** at N=100 the 3-template
× 3-carrier matrix (now 9 distinct stub variants) completes in <100ms
total across all configurations. The Complex<Double> rawStorage-match
scan stays O(12) per edge-pass trial; commutativity's two-value
generation adds one `generator.run(using: &rng)` call per trial
(microsecond-scale).

**Flake notes.** v1.44.F flagged a `§13 discover budget` flake when
subprocess-build load contended with the perf tests; cycle-42's longer
runtime (more parallel subprocess builds) made this slightly more
frequent during cycle-42 measurement. A second `swift test` run
typically passes cleanly. If recurrent in CI, serialize the
subprocess-based integration tests against the §13 perf tests, or
move them to a separate `swift test --filter` invocation outside
the default suite.

**V1.45.E surfaced one real bug** during integration testing: the
commutativity Pass 2 stub re-declared `defaultGenerator` at top-level
(clashing with Pass 1's declaration). Unit-test-only coverage would
not have surfaced this — the integration tests pinning the actual
subprocess compile caught it. Bug fixed in the same V1.45.E commit;
no impact on this baseline.

v1.45 baseline replaces v1.44 as the comparison anchor for v1.46+.
