# SwiftInferProperties — v1.51 Performance Baseline (Phase 2; gap-closing cycle)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-12 against the V1.51.G commit. v1.51 ships the
three mechanical fixes (A: bare→qualified `Complex` carrier
normalization; B: dual-style curated pair expansion; C: monotonicity-
on-Double routing flip) plus the Layer-2(a) blind-spot guard (D:
always-on E2E indexer→verify test) plus the Layer-2(b) doc-level
reframing (G: cycle-47 caveat appended to cycles 41-46 findings).

**Discover-pipeline impact: none.** v1.51 introduces zero discover-
side changes. The §13 discover budgets stay unchanged from v1.41-v1.50.

**Test-suite measurement (non-subprocess fast path):** **2378 tests**
passing across **327 suites** in **~4 seconds** when running
`swift test --skip VerifyPipelineIntegrationTests`. Full default
suite runs ~210s (21 subprocess integration tests unchanged from v1.49).

New tests since v1.50: +15 (`V1_51CanonicalizationTests` 3 +
`V1_51DualStyleExpansionTests` 6 + `V1_51RoutingFlipTests` 3 +
`V1_51EndToEndFromIndexTests` 2 + dual-style E2E test dropped after
V1.51.B latency finding = +13 net + 2 fixture-load helpers). Test
count 2400 → 2415.

**Per-survey-run cost (V1.51 cycle-48 measurement):** **~6 minutes**
wall-clock for the full 109-pick survey via `swift-infer verify
--all-from-index --max-parallel 4` against the cycle-27 fixture (vs
cycle-47's ~3 minutes — the doubled cost reflects the 22 picks now
actually running `swift build` rather than erroring at resolution).

Projected v1.52+ cost: as more picks reach swift build, expect linear
scaling. 109 picks × ~12s cold / 4-parallel = ~5-6 min wall-clock at
the steady state. Macos file-descriptor limits still cap practical
parallelism at ~8.

**Per-verify-call cost (single suggestion):** **~13s cold** (unchanged
from v1.43-v1.50). v1.51's mechanical fixes don't change the per-call
cost; they just unblock more picks at the resolution layer.

**§13 budget compliance:** all v1.41-v1.50 measurements hold. v1.51
added zero subprocess integration tests; the V1.51.E unit tests are
pure-Swift parse-and-encode coverage. V1.51.D's E2E test is a
unit-test-style fixture load (no subprocess), so it doesn't count
toward the subprocess parallelism budget.

**Survey wall-clock model (v1.51):**
- `--max-parallel 4` (default): ~6 min for the 109-pick cycle-27
  fixture (22 picks reach swift build; 87 fail at resolution → fast).
- Cycle-49 trajectory (if v1.52 closes the call-expression-shape
  gap): expect 60+ picks reaching swift build → ~10-15 min wall-clock.

**Phase 2 opening summary**: 0/109 (cycle-47) → 22/109 = 20.2% (cycle-48)
measured-execution. V1.51 mechanical fixes shift 22 picks past
carrier-resolution; the new gap (call-expression shape) is v1.52+
scope. No per-pick agreement-rate signal computable from cycle-48 —
all 22 measured picks landed in `.measured-error`, none in the
outcome categories cycle-46's predictions used. v1.52's call-
expression resolver should produce the first measurable
`.bothPass`/`.defaultFails` subset.

V1.51.D's always-on E2E guard (`V1_51EndToEndFromIndexTests`) catches
the synthetic↔real-indexer bridge regression at unit-test speed —
the cycle-47 blind spot can't recur silently.

v1.51 baseline is the Phase 2 gap-closing reference point.
