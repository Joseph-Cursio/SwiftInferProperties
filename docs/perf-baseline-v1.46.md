# SwiftInferProperties — v1.46 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-12 against the V1.46.E commit. v1.46 ships the
second cycle of the Phase 1.5 verifiable-fraction expansion arc:
**associativity verify support** (template + 3-carrier dispatch +
pair resolver + CLI dispatch + template-aware renderer) with
**per-slot rotation edge bias** — each trial draws the edge value
into slot `(t % 3)` and the other two slots from the default
generator, surfacing breaks at any of the three nesting positions.

**Discover-pipeline impact: none.** v1.46 introduces no changes to the
discover / index / drift / metrics paths. The `verify` subcommand is
still an isolated entry point that consumes the SemanticIndex without
mutating it. The §13 discover budgets (1s / 2s / 6s for the 10 / 50 /
100 test-file synthetic corpora; 800 MB peak-delta for the 500-file
corpus) are unchanged from v1.41–v1.45.

**Test-suite measurement:** **2288 tests** passing across **310 suites**.
Full `swift test` completes in ~160s, up from v1.45's ~131s — the three
new V1.46.D.4 integration tests (`associativity × Complex<Double> ×
bothPass`, `× Double × defaultFails`, `× Int × bothPass`) each spawn a
real `swift build` of a synthesized verifier workdir. Twelve total
subprocess-based integration tests now run in parallel (3 V1.42.D
round-trip + 3 V1.44.E.3 idempotence + 3 V1.45.E.3 commutativity +
3 V1.46.D.4 associativity); wall-clock is dominated by SwiftPM
dependency resolution + the kit's cold compile under contention.
A re-run after the SwiftPM cache warms typically lands closer to ~90s.

New tests since v1.45: 19 in `AssociativityStubEmitterTests` (V1.46.A)
+ 7 in `AssociativityPairResolverTests` (V1.46.B) + 5 in
`VerifyResultRendererAssociativityTests` (V1.46.C) + 3 in
`VerifyPipelineIntegrationTests` (V1.46.D.4) = 34 net new tests.
Matches the v1.46 plan's projection of "2254 → ~2288" exactly.

**Per-verify-call cost:** **~13s cold** (unchanged from v1.43–v1.45
within measurement noise). Associativity-verify calls add <50ms over
commutativity given the same stub-emission cost + one additional
generator draw per trial (three values instead of two) + the per-slot
rotation switch (constant-time per trial). Single-pass Int
associativity is fastest (~1s warm). Measurements from a 2026 MacBook
(M-series).

**§13 budget compliance:** all v1.41–v1.45 measurements hold. v1.46's
new V1.46.D.4 integration tests sit in the same target as V1.42.D,
V1.44.E, and V1.45.E — not subject to a §13 budget. Verify itself is
opt-in and not on the discover hot path, so it doesn't enter the §13
surface either.

**Per-trial-budget cost (in stub, post-build):** at N=100 the 4-template
× 3-carrier matrix (now 12 distinct stub variants) completes in <120ms
total across all configurations. The Complex<Double> rawStorage-match
scan stays O(12) per edge-pass trial; associativity's three-value
generation adds two `generator.run(using: &rng)` calls per trial
beyond round-trip's single draw (microsecond-scale), and the per-slot
rotation switch is constant-time.

**Per-slot rotation cost.** The Pass 2 edge rotation adds one
`trial % 3` modulo + a 3-arm switch per trial. At N=100 this is
~100 modulo operations + 100 enum-discriminator branches — fully
amortized inside the existing IEEE 754 arithmetic for the function
under test. No measurable per-trial overhead vs v1.45's static
single-slot bias.

**Flake notes.** v1.44.F's `§13 discover budget` flake under
subprocess-build contention persists in cycle-43 — v1.46's 12 parallel
subprocess integration tests increase contention modestly. A second
`swift test` run typically passes cleanly. If recurrent in CI,
serialize the subprocess-based integration tests against the §13 perf
tests, or move them to a separate `swift test --filter` invocation
outside the default suite.

**No new bugs surfaced during V1.46.D.4 integration testing.** The
v1.45 lesson (Pass 2 `defaultGenerator` redeclaration) carried forward
into v1.46: the associativity Pass 2 stub reuses Pass 1's top-level
`defaultGenerator` rather than re-declaring. All three V1.46.D.4
integration tests passed on the first end-to-end run.

v1.46 baseline replaces v1.45 as the comparison anchor for v1.47+.
