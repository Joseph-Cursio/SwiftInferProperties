# SwiftInferProperties — v1.43 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.43.E.3.b commit. v1.43 ships
the test-execution-evidence Phase 1 step 2: the verify pipeline now
runs **two passes** per call — a default finite-domain pass (unchanged
behavior from v1.42) followed by an edge-case-biased pass driven by
`Gen<Complex<Double>>.edgeCaseBiased()` from `PropertyLawComplex`. The
4-outcome reporting table (`bothPass` / `edgeCaseAdvisory` /
`defaultFails` / `error`) replaces v1.42's 3-outcome surface.

**Discover-pipeline impact: none.** v1.43 introduces no changes to the
discover / index / drift / metrics paths. The `verify` subcommand is
still an isolated entry point that consumes the SemanticIndex without
mutating it. The §13 discover budgets (1s / 2s / 6s for the 10 / 50 /
100 test-file synthetic corpora; 800 MB peak-delta for the 500-file
corpus) are unchanged from v1.41/v1.42.

**Test-suite measurement:** **2178 tests** passing across **302 suites**.
Full `swift test` completes in ~41s, up from v1.42's ~37s — the new
integration test (`edge-case advisory: finite-only property fires on
first non-finite curated entry`) adds a third subprocess-based
end-to-end case, each spawning a real `swift build` of a synthesized
verifier workdir. The three V1.42.D + V1.43.E.3.b integration tests
run in parallel; the wall-clock is dominated by the slowest of the
three. New tests since v1.42: parser tests for the 4-outcome shape,
renderer tests including curated-entry classification + the index `-1`
fallback, the `stubMatchesEdgeIndexViaRawStorage` unit test, and the
`edgeCaseAdvisoryOnNonFiniteEntry` integration test.

**Per-verify-call cost:** **~12s cold** (first call against a new
workdir; SwiftPM resolves swift-numerics + swift-property-based +
SwiftPropertyLaws + compiles a tiny package) — up from v1.42's ~8s due
to the kit dep being added at V1.43.A. **~1-3s warm** (subsequent
calls reuse SwiftPM's incremental cache in the same workdir); the
two-pass design at N=100 adds <100ms over v1.42's single-pass cost.
Measurements from a 2026 MacBook (M-series).

**§13 budget compliance:** all v1.41/v1.42 measurements hold. v1.43's
new integration test sits in the same target as V1.42.D's — not
subject to a §13 budget. Verify itself is opt-in and not on the
discover hot path, so it doesn't enter the §13 surface either.

**Per-trial-budget cost (in stub, post-build):** at N=100 the default
pass + edge pass + the 12-entry rawStorage match per trial complete
in <50ms total (dominated by 200 floating-point round-trip evaluations
on Complex<Double>). The matchEdgeCaseIndex scan is O(12) per edge-pass
trial — negligible.

v1.43 baseline replaces v1.42 as the comparison anchor for v1.44+.
