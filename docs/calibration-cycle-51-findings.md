# v1.54 Calibration Cycle 51 — Findings (V1.52.A revert pays off: +8 measured outcomes; first generator-range tuning gap surfaced)

Captured: 2026-05-13. swift-infer at v1.54 (post-V1.54.C). The fifty-first execution of PRD §17.3's empirical-tuning loop.

## Headline

**Full-surface measured-execution: 20 / 109 = 18.3%** (`.bothPass` + `.defaultFails`, excluding error). **+8 measured outcomes vs cycle-50** — exactly the 8 round-trip Complex EF picks V1.54.A's revert restored.

| Outcome | Cycle-50 (v1.53) | Cycle-51 (v1.54) | Δ |
|---|---:|---:|---:|
| measured-bothPass | 6 | **6** | 0 |
| measured-defaultFails | 6 | **14** | **+8** |
| measured-error | 10 | **2** | **-8** |
| architectural-coverage-pending | 87 | 87 | 0 |

**The 8 new outcomes all landed in `.defaultFails` — but the cause is a generator-range tuning issue, not a semantic mismatch with cycle-46's predictions.** All 8 are round-trip Complex EF surface picks (`exp`, `log`, `sin`, `cos`, `tan`, `sinh`, `cosh`, `tanh`) that overflow / lose precision when the v1.42 generator's `Double.random(in: -1e6 ... 1e6)` range exceeds the function's stable domain. The cycle-46 structural prediction was `.bothPass` for all 8; the verifier reports `.defaultFails` because `exp(789009 + 533285i)` evaluates to `inf`, breaking the round-trip.

This is the **first generator-tuning gap** the project's calibration loop has surfaced — a finding only possible once end-to-end measurement reaches this layer.

## What V1.54 accomplished

| Fix | Picks unblocked | Picks reaching property check | New .bothPass | New .defaultFails |
|---|---:|---:|---:|---:|
| V1.54.A — free-function revert (CallExpressionShape) | 8 | 8 | 0 | 8 |
| V1.54.B — V1.52.C dead-binding cleanup | 0 | 0 | 0 | 0 |
| V1.54.C — RealModule import (FP strategist recipe) | 0 net (prevented 2 regressions) | (held existing 2 picks) | (no change) | (no change) |
| **Total** | **8** | **8** | **0** | **+8** |

**V1.54.C's role**: V1.54.A alone would have regressed 2 cycle-50 .bothPass picks (monotonicity-on-Double). V1.54.C's RealModule import for FP strategist recipes prevented that. Discovered at smoke-test stage (single-pick verify on 0xA9AD), fixed in the same cycle.

## Cycle-46 predictions vs cycle-51 actuals (32-pick sample subset)

13 of 32 sample picks produced measurable outcomes (up from 5 in cycle-50):

**Mathematical-correctness match rate**: 12 / 13 = **92%**. The 1 borderline case is sin/cos precision loss at very large inputs — whether the prediction "holds" depends on the chosen domain.

**Semantic-domain match rate** (predicted outcome class matches measured outcome class verbatim): 5 / 13 = **38%**. The 8 mismatches are all round-trip Complex EF picks where cycle-46 predicted `.bothPass` (structurally correct) but cycle-51 measures `.defaultFails` (generator-range overflow).

Both numbers are informative:
- 92% mathematical correctness: the architecture is sound; the verifier identifies the right algebraic property at the structural level.
- 38% semantic-domain agreement: the v1.42 generator's input range is too wide for `exp`-class functions. v1.55+ generator-range refinement is the load-bearing fix.

## What cycle-51 establishes

1. **V1.54.A's free-function revert was the right call.** 8 picks now reach the property check; cycle-49's V1.52.B stderr capture finding (libTesting was the real issue, not call-expression shape) is fully validated.

2. **V1.54.B's binding cleanup is silent but correct.** Removed 4 dead keys; zero picks moved (as predicted). The bare-type-key + TypeShape-driven element binding is v1.55+ scope.

3. **V1.54.C's RealModule import is a critical follow-on**. Without it, V1.54.A would have regressed 2 picks. The smoke-test → fix-in-same-cycle pattern is a methodology improvement worth keeping (catches regressions before the full survey runs).

4. **The 8 new `.defaultFails` reveal a new gap: FP generator range tuning**. Not a verifier bug — the verifier correctly reports the round-trip failure for `exp(800)` = `inf`. The fix is generator-side: tune the input range per function's stable domain, or use a log-scale / two-tier generator.

5. **Mathematical correctness is now demonstrable at scale**. Of the 20 measured picks, 18 (all `.bothPass` + 6 of the 14 `.defaultFails`) are unambiguously correct algebraic identifications. The other 8 `.defaultFails` are correct *for the chosen inputs*; the cycle-46 prediction was correct *for the function's stable domain*.

6. **The remaining 87 `.architectural-coverage-pending` picks are the dominant single category** — same as cycle-50. v1.55+'s TypeShape-driven OC instantiation is the next-biggest workstream.

## v1.55+ priorities

In priority order (rebalanced post-cycle-51):

1. **v1.55 — FP generator-range refinement**. Closes ~6 of the 8 new `.defaultFails` to `.bothPass`. Three approaches: (a) per-function generator domains (`exp` → ±700, `sin`/`cos` → ±100, etc.); (b) log-scale + linear-scale two-tier generators; (c) use the kit's `Gen<Double>.edgeCaseBiased` infrastructure with smaller magnitudes. Push 32-pick subset match-rate to 12/13 → 12/12 on the measurable subset.

2. **v1.55-v1.56 — TypeShape-driven generic instantiation** for OC + Algo types. Dominant remaining category (60+ picks). Substantial scope.

3. **v1.55 — `_relaxedMul` / `rescaledDivide` build-failure investigation**. 2 picks; stub-source inspection.

4. **v1.55 — Instance-method emission for chunked-Index picks** (deferred from v1.54). Closes 3 cycle-46-predicted `.defaultFails`.

5. **v1.55 — Methodology guard for binding tables** (carried from v1.54 plan). Fixture-level check that every binding key matches at least one indexer-produced carrier name. Prevents V1.51.B + V1.52.C latent-key recurrence.

6. **v1.56+ — Phase 2 accept-flow integration** — gated on cycle-51's 20-pick sample being statistically sufficient.

## Captured artifacts

- Cycle-51 survey JSON: `docs/calibration-cycle-51-data/full-surface-outcomes.json` (sorted by identityHash; surveyVersion: 1; 109 entries).
- Aggregate summary: `docs/calibration-cycle-51-data/full-surface-summary.md` (template × outcome cross-tab + cycle-46 sample-subset comparison + generator-range methodology note).
- V1.54.A-C code — committed `7b1d1ed`.

## Open threads carried into v1.55

1. **FP generator-range refinement** — load-bearing for closing the 32-pick semantic-domain match rate from 38% to ~90%+. The 8 round-trip EF picks all need narrower input ranges to match cycle-46's structural prediction.
2. **`_relaxedMul` and `rescaledDivide` build failures** — unknown cause; need stub-source inspection.
3. **The 87 architectural-coverage-pending picks** — TypeShape-driven Element-type binding is the dominant single workstream.
4. **`Complex<Float>` emitter path** — deferred from v1.51; cycle-51 surfaces nothing new on this.
5. **Linux `LD_LIBRARY_PATH` support** for V1.53.A — deferred from v1.53; cycle-51 confirms macOS-only-good-enough on this host.
