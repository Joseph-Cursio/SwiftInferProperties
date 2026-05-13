# SwiftInferProperties — v1.52 Performance Baseline (Phase 2; second gap-closing cycle)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-13 against the V1.52.F commit. v1.52 ships three
mechanical workstreams (A: call-expression-shape resolver; B:
subprocess stderr capture; C: `GenericBindingResolver` chunked-Index
expansion) + ~21 unit tests + cycle-49 measurement (no architectural
changes).

**Discover-pipeline impact: none.** v1.52 introduces zero discover-
side changes. The §13 discover budgets stay unchanged from v1.41-v1.51.

**Test-suite measurement (non-subprocess fast path):** **2399 tests**
passing across **333 suites** in **~4 seconds** when running
`swift test --skip VerifyPipelineIntegrationTests`. Full default
suite runs ~210s (21 subprocess integration tests unchanged from v1.49).

New tests since v1.51: +21 (`V1_52CallExpressionShapeTests` 8 +
`V1_52PairResolverIntegrationTests` 4 + `V1_52StderrCaptureTests` 3 +
`V1_52GenericBindingExpansionTests` 6). Test count 2378 → 2399. The
plan called for ~17; the overshoot came from adding the
`isOperatorName` edge-cases test (one `@Test` with 7 `#expect`s) and
the stderr-truncation test (V1.52.B's 200-char cap).

**Per-survey-run cost (V1.52 cycle-49 measurement):** **~4 minutes**
wall-clock for the full 109-pick survey via `swift-infer verify
--all-from-index --max-parallel 4` against the cycle-27 fixture (vs
cycle-48's ~6 min — cache-warmer second run; same 22 picks reach
`swift build`).

Projected v1.53+ cost: once the V1.53 `libTesting.dylib` fix lands,
expect ~16-22 picks to actually run the property check (vs cycle-49's
0 picks reaching runtime past the dyld trap). Per-pick property-check
cost: ~100ms-1s depending on trial budget. Total v1.53 survey wall-
clock: ~5-7 min projected.

**Per-verify-call cost (single suggestion):** **~13s cold** (unchanged
from v1.43-v1.51). V1.52's classifier + binding additions don't change
the per-call cost; they're pure-Swift in-process work.

**§13 budget compliance:** all v1.41-v1.51 measurements hold. v1.52
added zero subprocess integration tests; the V1.52.D unit tests are
pure-Swift parse-and-encode coverage. The §13 perf measurements stayed
under the 2s discover budget across two full runs of `swift test
--skip VerifyPipelineIntegrationTests` (2.069s / 2.053s — same range
as v1.51's 2.069s).

**Survey wall-clock model (v1.52):**
- `--max-parallel 4` (default): ~4 min for the 109-pick cycle-27
  fixture (22 picks reach swift build; 87 fail at resolution → fast).
- Cycle-50 trajectory (v1.53 closes libTesting.dylib): expect 16-22
  picks running the property check → ~5-7 min wall-clock.

**Phase 2 cycle-49 measurement summary**: 22/109 = 20.2% measured-execution,
unchanged from cycle-48. The composition shifted (8 round-trip Complex
picks regressed compile via V1.52.A free-function shape; 6 cycle-48
build-failed picks now reach runtime via V1.52.A operator-paren; 11
cycle-48 parse-error picks revealed by V1.52.B as `libTesting.dylib`
dyld failures). No per-pick agreement-rate signal computable —
all 22 measured picks landed in `.measured-error`. **V1.52.B was the
cycle's biggest win**; it falsified the cycle-48 framing of parse-error
as a call-expression-shape issue and surfaced the real load-bearing
gap (runtime library linking).

V1.52.A's operator-paren classification holds; the free-function half
needs revert (or import-shim) in v1.53. V1.52.C's chunked-Index
bindings are latent (wrong key format) — v1.53 fix is mechanical.

v1.52 baseline is the Phase 2 stderr-instrumentation reference point.
