# v1.53 Calibration Cycle 50 — Findings (first non-zero measured-execution + first computable per-pick agreement-rate)

Captured: 2026-05-13. swift-infer at v1.53 (post-V1.53.A). The fiftieth execution of PRD §17.3's empirical-tuning loop. **First non-zero `.bothPass` / `.defaultFails` measurement in the project's calibration history.**

## Headline

**Full-surface measured-execution: 12 / 109 = 11.0%** (`.bothPass` + `.defaultFails`, excluding `.measured-error` and `.architectural-coverage-pending`).

| Outcome | Cycle-49 (v1.52) | Cycle-50 (v1.53) | Δ |
|---|---:|---:|---:|
| **measured-bothPass** | 0 | **6** | **+6** |
| **measured-defaultFails** | 0 | **6** | **+6** |
| measured-edgeCaseAdvisory | 0 | 0 | 0 |
| measured-error | 22 | 10 | -12 |
| architectural-coverage-pending | 87 | 87 | 0 |

**The cycle's load-bearing fact**: V1.53.A's `DYLD_LIBRARY_PATH` injection closed the `libTesting.dylib` runtime-link gap that cycle-49's V1.52.B stderr capture surfaced. 12 picks that had been stuck at `dyld: Library not loaded` now run their full property-check loops. All 12 produced mathematically valid outcomes — every `.bothPass` matches a commutative/associative/monotonic operation; every `.defaultFails` matches a non-commutative/non-associative one.

**Per-pick agreement-rate on cycle-50: 12/12 = 100%.** First computable real-indexer-end-to-end signal in the project's history, directly comparable to cycles 42-46's synthetic-shape-class predictions (which also reported 100% on a 30-pick sample). The two numbers align — at small N — confirming the architecture's load-bearing claim end-to-end.

## What V1.53.A accomplished

| Fix | Picks unblocked | Picks reaching property check | Picks reaching .bothPass/.defaultFails |
|---|---:|---:|---:|
| V1.53.A — DYLD_LIBRARY_PATH injection for verifier subprocess | 18 | 12 | **12** |

The 18 picks reaching the property-check layer split:
- **12 produced clean .bothPass / .defaultFails outcomes** (listed below).
- **6 entered the property check then hit a different failure**: the 8 V1.52.A free-function regressions on round-trip Complex EF surface (`exp`, `log`, etc.) compile-fail rather than dyld-fail; they stay `.measured-error` in cycle-50. Wait — that's a contradiction. Re-reading: the 8 regressions are *compile* failures (build-failed), not runtime — so they never reach the property check. The 18 figure was over-counted; **the actual reach-property-check count is 12**, exactly matching the `.bothPass` + `.defaultFails` sum.

## The 12 measured picks

**6 `.bothPass` (mathematically valid true-positives):**

| # | Hash prefix | Template | Function | Carrier |
|---:|---|---|---|---|
| 1 | 0x1C94 | commutativity | `_relaxedAdd(_:_:)` | Complex |
| 2 | 0x26D2 | associativity | `_relaxedAdd(_:_:)` | Complex |
| 3 | 0x60A0 | associativity | `_relaxedMul(_:_:)` | Complex |
| 4 | 0x7748 | commutativity | `_relaxedMul(_:_:)` | Complex |
| 5 | 0xA9AD | monotonicity | `log(onePlus:)` | Double |
| 6 | 0xE062 | monotonicity | `log(_:)` | Double |

**6 `.defaultFails` (mathematically valid true-negatives):**

| # | Hash prefix | Template | Function | Carrier |
|---:|---|---|---|---|
| 7 | 0x0EE1 | associativity | `pow(_:_:)` | Complex |
| 8 | 0x89A9 | commutativity | `/(z:w:)` | Complex |
| 9 | 0xB8DE | associativity | `-(z:w:)` | Complex |
| 10 | 0xB8FE | commutativity | `pow(_:_:)` | Complex |
| 11 | 0xD8D3 | associativity | `/(z:w:)` | Complex |
| 12 | 0xF19A | commutativity | `-(z:w:)` | Complex |

Every outcome is correct: `+` (additive) commutes and associates on Complex; `*` (multiplicative) commutes and associates; `log` is monotonic on its domain; `pow` and `/` and `-` don't satisfy commutativity/associativity. The verifier's trial-budget loop found counterexamples to all 6 invalid properties — e.g., `Complex.pow` failed at trial 0 with `pow(pow(a, b), c) = (0.0, 0.0)` vs `pow(a, pow(b, c)) = inf`.

## Cycle-46 predictions vs cycle-50 actuals

Of the 32-pick stratified sample from cycles 41-46, **5 members produced measurable outcomes in cycle-50**:

| Sample # | Hash prefix | Cycle-46 predicted | Cycle-50 actual | Match? |
|---:|---|---|---|---|
| #18 | 0xA9AD | .bothPass | .bothPass | ✓ |
| #19 | 0xE062 | .bothPass | .bothPass | ✓ |
| #24 | 0x7748 | .bothPass | .bothPass | ✓ |
| #26 | 0x60A0 | .bothPass | .bothPass | ✓ |
| #27 | 0xB8DE | .defaultFails | .defaultFails | ✓ |

**5/5 = 100% per-pick agreement on the cycle-46-vs-cycle-50 sample-subset overlap.** Cycle-46's "100% per-pick agreement" was synthetic-shape-class agreement; cycle-50's is real-indexer-end-to-end agreement. The two now align — **at small N** — for the picks that reach the property check.

The remaining 27 sample-subset members are still `.measured-error` (8 round-trip Complex EF picks pending v1.54 V1.52.A revert) or `.architectural-coverage-pending` (19 OC + Algo generic carrier picks pending v1.54+ TypeShape work). Per-pick agreement on the full 32-pick sample is not yet computable.

## What cycle-50 establishes

1. **The verify architecture is sound, end-to-end.** Cycles 42-46 demonstrated capability on synthetic inputs. Cycles 47-49 surfaced bridge gaps (carrier resolution → call-expression shape → runtime linking). Cycle-50 closes the last load-bearing bridge gap (`libTesting.dylib`); the first 12 picks where the bridge is fully closed all produce mathematically valid outcomes.

2. **V1.53.A is the single highest-impact cycle since v1.30**. 80 LoC closed +12 measured outcomes. LoC/outcome efficiency: 6.7 LoC per measured pick. (V1.30 hit the §19 ≥70% target at -38 reject closures via the v1.18-v1.29 mechanism cycles — comparable in headline impact but spread across multiple cycles; V1.53.A is a single-workstream win.)

3. **The 8 V1.52.A free-function regressions are worth reverting**. Without the regression, cycle-50 would have hit ~20 measured outcomes (12 + 8 round-trip Complex EF picks). v1.54's revert plus V1.52.C carrier-name key fix should grow the sample to 18-22+.

4. **The remaining 87 `.architectural-coverage-pending` picks need different fixes**. Mostly OC + Algo generic carrier types needing TypeShape-driven instantiation. v1.54+ scope.

5. **The cycle-49 "libTesting.dylib is the load-bearing fix" framing was correct**. Without V1.52.B's stderr capture, v1.53 would have chased the wrong gap (call-expression shape).

6. **The 100% per-pick agreement on cycle-50's measured picks is statistically thin** (N=12, sample-subset N=5). Cycle-51+ should grow the sample. The agreement is informative — at the *capability* level — but not yet load-bearing for v1.0 ship readiness.

## v1.54+ roadmap

Per cycle-50 evidence, in priority order:

1. **v1.54 — V1.52.A free-function revert**. Drop EF-surface entries from `CallExpressionShape.freeFunctionMap`. The 8 cycle-50 build-failed round-trip Complex picks return to `.staticMethod` shape, then reach the property check via V1.53.A's DYLD fix. Closes 8 picks; small +.bothPass / +.defaultFails delta. Mechanical fix; ~5 LoC + test updates.

2. **v1.54 — V1.52.C carrier-name key fix**. Replace `ChunkedByCollection.Index` / `OrderedSet.Index` keys with bare `ChunkedByCollection` / `OrderedSet`. 3 chunked-Index picks reach swift build (cycle-46 predicted `.defaultFails`).

3. **v1.54 — `_relaxedMul`/`rescaledDivide` build-failure investigation**. 2 picks build-fail on cycle-50 with no operator/EF-surface cause; need to inspect the synthesized stub source.

4. **v1.54-v1.55 — TypeShape-driven generic instantiation** for OC + Algo types. Dominant remaining category (60+ picks).

5. **v1.54 — Methodology guard**. Fixture-level check that every `GenericBindingResolver.curatedBindings` key matches at least one indexer-produced carrier name. Prevents the V1.51.B + V1.52.C latent-key-format recurrence.

6. **v1.55+ — Phase 2 accept-flow integration** — gated on cycle-51+ growing the agreement-rate sample to 20+ picks for statistical reliability.

## Captured artifacts

- Cycle-50 survey JSON: `docs/calibration-cycle-50-data/full-surface-outcomes.json` (sorted by identityHash; surveyVersion: 1; 109 entries).
- Aggregate summary: `docs/calibration-cycle-50-data/full-surface-summary.md` (template × outcome cross-tab + measured-pick mathematical-correctness check + cycle-46 sample-subset comparison + methodology).
- V1.53.A subprocess env injection — committed `a07489f`.

## Open threads carried into v1.54

1. **The V1.52.A free-function revert decision.** Cycle-50 evidence strongly favors revert. v1.54's first commit should be the revert + restored test assertions.
2. **`_relaxedMul` and `rescaledDivide` build failures.** Unknown cause; need stub-source inspection.
3. **The 87 architectural-coverage-pending picks.** Mostly OC / Algo generic types. TypeShape-driven Element-type binding is the dominant single workstream.
4. **DYLD propagation under SIP / signed-binary scenarios.** Cycle-50 host had no SIP scrub; cycle-51+ should validate on CI / signed-toolchain machines.
