# SwiftInferProperties — v1.42 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-11 against the V1.42.C.6 commit. v1.42 ships the
test-execution-evidence Phase 1 minimum-viable pipeline: an opt-in
`swift-infer verify --suggestion <id>` subcommand that compiles + runs
a synthesized round-trip property test in a throwaway SwiftPM workdir.

**Discover-pipeline impact: none.** v1.42 introduces no changes to the
discover / index / drift / metrics paths. The `verify` subcommand is an
isolated new entry point that consumes the SemanticIndex but does not
mutate it. The §13 discover budgets (1s / 2s / 6s for the 10 / 50 / 100
test-file synthetic corpora; 800 MB peak-delta for the 500-file
corpus) are unchanged from v1.41.

**Test-suite measurement:** **2171 tests** passing across **301 suites**.
Full `swift test` completes in ~37s, dominated by the new V1.42.D
integration tests (`identity round-trip passes 100 trials`, `asymmetric
pair fails at trial 0`) which each spawn a real `swift build` of a
synthesized verifier workdir (~37s wall-clock total because both tests
run in parallel). Prior v1.41 baseline was ~4s for 2103 tests; the
addition of subprocess-based integration tests is the v1.42 deliberate
cost.

**Per-verify-call cost:** **~37s cold** (first call against a new
workdir; SwiftPM resolves swift-numerics + swift-property-based + compiles
a tiny package). **~1-3s warm** (subsequent calls reuse SwiftPM's
incremental cache in the same workdir). v1.43+ may layer additional
caching; the v1.42 measurement is from a 2026 MacBook (M-series).

**§13 budget compliance:** all v1.41 measurements hold. The new
integration-test cost is in a separate test target and not subject to a
§13 budget. Verify itself is opt-in and not on the discover hot path,
so it doesn't enter the §13 surface either.

v1.42 baseline replaces v1.41 as the comparison anchor for v1.43+.
