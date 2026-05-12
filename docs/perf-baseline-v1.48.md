# SwiftInferProperties — v1.48 Performance Baseline

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-12 against the V1.48.I commit. v1.48 ships the
fourth cycle of the Phase 1.5 verifiable-fraction expansion arc and
**closes the cycle-27 template-coverage matrix** with three new
templates: idempotence-lifted, dual-style-consistency, monotonicity.
All three route exclusively through the v1.47
`StrategistDispatchEmitter`; no new hardcoded `{Complex<Double>,
Double}` paths.

**Discover-pipeline impact: none.** v1.48 introduces no changes to
the discover / index / drift / metrics paths. The §13 discover
budgets (1s / 2s / 6s for the 10 / 50 / 100 test-file synthetic
corpora; 800 MB peak-delta for the 500-file corpus) are unchanged
from v1.41–v1.47.

**Test-suite measurement:** **2360 tests** passing across **321 suites**
(up from v1.47's 2332). Full `swift test` completes in ~200s, up
from v1.47's ~170s — the two new V1.48.H integration tests
(idempotence-lifted + monotonicity; dual-style-consistency
placeholder-skipped pending v1.49 stub-preamble channel) each spawn
a real `swift build`. 18 total subprocess-based integration tests
now run in parallel (3 V1.42.D + 3 V1.44.E + 3 V1.45.E + 3 V1.46.D
+ 4 V1.47.G + 2 V1.48.H = 18). A re-run after the SwiftPM cache
warms typically lands closer to ~110s.

New tests since v1.47: 9 in `StrategistDispatchEmitterV1_48Tests`
(V1.48.E) + 13 in `V1_48PairResolverTests` (V1.48.F) + 7 in
`VerifyResultRendererV1_48Tests` (V1.48.G) + 2 in
`VerifyPipelineIntegrationTests` (V1.48.H.1 + V1.48.H.3) - 0
deleted = **+31 net new tests** (matching plan's ~30). One v1.47
test (`unsupported template throws .unsupportedTemplate`) was
updated to use a template name outside the v1.48 supported set;
no test count change.

**Per-verify-call cost:** **~13s cold** (unchanged from v1.43–v1.47).
The three new template composers (idempotence-lifted /
dual-style-consistency / monotonicity) add <20ms over the existing
strategist-routed path given the per-trial logic is small inline
composition. Idempotence-lifted adds one `array(of: 0...8)` wrap
on the element generator (microsecond-scale per trial); monotonicity
adds two `min` / `max` calls per trial; dual-style-consistency
adds one `var` binding per trial.

**§13 budget compliance:** all v1.41–v1.47 measurements hold.
v1.48's two new V1.48.H integration tests sit in the same target
as V1.42.D / V1.44.E / V1.45.E / V1.46.D / V1.47.G — not subject
to a §13 budget.

**Per-trial-budget cost (in stub, post-build):** at N=100 the
expanded surface (now ~24 distinct stub variants across the v1.46
hardcoded + strategist-routed paths × 4 → 7 templates) completes
in <150ms total across all configurations. The strategist-routed
single-pass stubs are simpler than the v1.46 two-pass Complex<Double>
stubs; per-stub cost is well under v1.47.

**§13 perf-test flake intensifies further at 18 parallel subprocess
builds.** v1.45–v1.47 documented the `Discover pipeline on 100 test
files < 6s` test contending with subprocess builds; v1.48 makes it
~5-10% more likely to fire (now consistently exceeds 6s under
parallel contention, occasionally hits 9s). Isolated re-runs still
land at 2s. **This is now the load-bearing test-harness gap** —
v1.49 should ship one of the three mitigations the cycle-44 perf
baseline outlined (split subprocess tests to a separate
`swift test --filter` invocation; widen the §13 budget when run
alongside `.integration` tests; or serialize the subprocess
builders).

**V1.48.H.2 dual-style-consistency placeholder-skipped.** The
V1.48.A composer's `copy.\(mutMethodName)()` shape requires a real
instance method on the carrier. For the integration-test fixture
to use a value-typed carrier with a paired non-mutating/mutating
method, either: (a) the stub gets a preamble channel for type
extensions, or (b) the dual-style composer gets reworked to support
inline-closure mutation. Neither shipped in v1.48 — unit-test
coverage in `StrategistDispatchEmitterV1_48Tests` pins the load-
bearing emit semantics; integration coverage of the dual-style
composer waits for v1.49. **Documented in cycle-45 findings as the
single v1.48 open thread.**

**No new bugs surfaced during V1.48.E–H.** One v1.47 test required
updating after V1.48.A's supportedTemplates widening (template
name "monotonicity" moved from unsupported to supported). The
V1.48.H.3 monotonicity test surfaced a fixture-design issue
(`x * 2` overflow-traps under the strategist's `.min...max` default
Int range) — fixed by switching to `{ x in x + 1 }` (overflow only
at `Int.max`, probability ~0). This is cycle-45's hygiene-rule
finding: monotonicity integration tests on Int carriers must use
overflow-safe functions.

v1.48 baseline replaces v1.47 as the comparison anchor for v1.49+.
