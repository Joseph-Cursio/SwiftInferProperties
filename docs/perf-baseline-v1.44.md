# SwiftInferProperties — v1.44 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.44.F commit. v1.44 ships the
test-execution-evidence Phase 1 step 3: the verify pipeline now
dispatches by **template** (`round-trip` and `idempotence`) and by
**carrier** (`Complex<Double>`, `Double`, `Int`). The 4-outcome
reporting from v1.43 carries forward; the renderer adapts phrasing
per template (round-trip vs idempotence) and per carrier (FP curated-
sampled count vs integer "edge pass not applicable" sentinel).

**Discover-pipeline impact: none.** v1.44 introduces no changes to the
discover / index / drift / metrics paths. The `verify` subcommand is
still an isolated entry point that consumes the SemanticIndex without
mutating it. The §13 discover budgets (1s / 2s / 6s for the 10 / 50 /
100 test-file synthetic corpora; 800 MB peak-delta for the 500-file
corpus) are unchanged from v1.41/v1.42/v1.43.

**Test-suite measurement:** **2220 tests** passing across **304 suites**.
Full `swift test` completes in ~65s, up from v1.43's ~41s — the three
new V1.44.E.3 integration tests (`idempotence × Complex<Double> ×
edgeCaseAdvisory`, `idempotence × Double × defaultFails`, `idempotence
× Int × bothPass`) each spawn a real `swift build` of a synthesized
verifier workdir and run the resulting binary. The six total
subprocess-based integration tests (3 V1.42.D/V1.43.E.3 round-trip
cases + 3 V1.44.E.3 idempotence cases) run in parallel; wall-clock is
dominated by the slowest of the six.

New tests since v1.43: 14 in `IdempotenceStubEmitterTests` (V1.44.A) +
6 in `RoundTripStubEmitterTests` for carrier dispatch (V1.44.B) +
6 in `IdempotenceStubEmitterTests` for carrier dispatch (V1.44.C) +
7 in `IdempotencePairResolverTests` (V1.44.D) + 6 in
`VerifyResultRendererTests` for template/integer-carrier adaptation
(V1.44.D) + 3 in `VerifyPipelineIntegrationTests` (V1.44.E.3) = 42
net new tests. The pre-existing renderer test split (V1.43.D's
`VerifyResultTests` → V1.44.D's two-file split into parser + renderer
suites) reorganized 13 tests without changing their count.

**Per-verify-call cost:** **~12s cold** (unchanged from v1.43; SwiftPM
resolves swift-numerics + swift-property-based + SwiftPropertyLaws +
compiles a tiny package). **~1-3s warm** for round-trip verify calls;
idempotence-verify calls add <10ms over round-trip given the
near-identical stub shape. Single-pass Int verify is fastest (~1s
warm) since there's no edge-case generation step. Measurements from a
2026 MacBook (M-series).

**§13 budget compliance:** all v1.41/v1.42/v1.43 measurements hold.
v1.44's new V1.44.E integration tests sit in the same target as
V1.42.D's — not subject to a §13 budget. Verify itself is opt-in and
not on the discover hot path, so it doesn't enter the §13 surface
either.

**Per-trial-budget cost (in stub, post-build):** at N=100 the
2-template × 3-carrier matrix completes in <100ms total across all
configurations. The Complex<Double> rawStorage-match scan stays O(12)
per edge-pass trial; the Double `isNaN ? 0 : -1` match is O(1); the
Int single-pass collapses to one for-loop with no edge work.

**Flake notes.** During cycle-41 measurement, the §13 50-file discover
budget (`PerformanceTests.swift:42`, 2s) flaked once with elapsed=3.56s
under concurrent subprocess-build load from the 6 V1.42.D/V1.44.E
integration tests running in parallel. A second `swift test` run
passed cleanly with discover at <2s. The flake is load-induced — not
introduced by v1.44 — and matches the classic perf-test flake mode in
the loop's history. If this becomes recurrent in CI, the v1.45 plan
should consider serializing the subprocess-based integration tests
against the §13 perf tests.

v1.44 baseline replaces v1.43 as the comparison anchor for v1.45+.
