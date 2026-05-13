# Cycle-50 full-surface measurement summary

Captured: 2026-05-13 via `swift-infer verify --all-from-index --index-path fixtures/cycle27-surface/.swiftinfer/index.json --max-parallel 4`. swift-infer at v1.53 (post-V1.53.A). **First non-zero `.bothPass`/`.defaultFails` measurement in the project's calibration history.**

## Aggregate

| Classification | Cycle-48 (v1.51) | Cycle-49 (v1.52) | Cycle-50 (v1.53) | Δ vs c49 |
|---|---:|---:|---:|---:|
| **measured-bothPass** | 0 | 0 | **6** | **+6** |
| **measured-edgeCaseAdvisory** | 0 | 0 | 0 | 0 |
| **measured-defaultFails** | 0 | 0 | **6** | **+6** |
| measured-error | 22 | 22 | 10 | -12 |
| architectural-coverage-pending | 87 | 87 | 87 | 0 |
| **Total** | **109** | **109** | **109** | — |
| **Measured-execution (excluding error)** | **0** | **0** | **12** | **+12** |

**Headline shifts from "diagnostic-only" to "measurable".** V1.53.A's `DYLD_LIBRARY_PATH` injection unblocked all 12 cycle-49 parse-dyld picks; they now run the property check end-to-end. Combined with the 6 picks V1.52.A's operator-paren classifier had pushed to runtime (cycle-49 parse-dyld), that's 18 picks at the property-check layer. Of those, 12 produced mathematically valid `.bothPass`/`.defaultFails` outcomes; the remaining 10 stay `.measured-error` (8 V1.52.A free-function regressions + 2 unknown-cause build failures).

## Per-template breakdown

| Template | Surface | pending | build-failed | .bothPass | .defaultFails |
|---|---:|---:|---:|---:|---:|
| round-trip | 12 | 4 | 8 | 0 | 0 |
| idempotence | 12 | 12 | 0 | 0 | 0 |
| monotonicity | 29 | 27 | 0 | 2 | 0 |
| commutativity | 17 | 11 | 1 | 2 | 3 |
| associativity | 17 | 11 | 1 | 2 | 3 |
| dual-style-consistency | 22 | 22 | 0 | 0 | 0 |
| **Total** | **109** | **87** | **10** | **6** | **6** |

## The 12 measured picks — mathematical correctness check

**6 `.bothPass` (property holds — all are mathematically valid true-positives):**

| Hash prefix | Template | Function | Carrier | Why .bothPass is correct |
|---|---|---|---|---|
| 0x1C94 | commutativity | `_relaxedAdd(_:_:)` | Complex | Complex addition commutes |
| 0x26D2 | associativity | `_relaxedAdd(_:_:)` | Complex | Complex addition associates |
| 0x60A0 | associativity | `_relaxedMul(_:_:)` | Complex | Complex multiplication associates |
| 0x7748 | commutativity | `_relaxedMul(_:_:)` | Complex | Complex multiplication commutes |
| 0xA9AD | monotonicity | `log(onePlus:)` | Double | `log(1+x)` is monotonic on `x ≥ 0` |
| 0xE062 | monotonicity | `log(_:)` | Double | `log` is monotonic on positive reals |

**6 `.defaultFails` (property doesn't hold — all are mathematically valid true-negatives):**

| Hash prefix | Template | Function | Carrier | Why .defaultFails is correct |
|---|---|---|---|---|
| 0x0EE1 | associativity | `pow(_:_:)` | Complex | `(a^b)^c ≠ a^(b^c)` for Complex generally |
| 0x89A9 | commutativity | `/(z:w:)` | Complex | Division doesn't commute |
| 0xB8DE | associativity | `-(z:w:)` | Complex | Subtraction doesn't associate |
| 0xB8FE | commutativity | `pow(_:_:)` | Complex | `a^b ≠ b^a` for Complex generally |
| 0xD8D3 | associativity | `/(z:w:)` | Complex | Division doesn't associate |
| 0xF19A | commutativity | `-(z:w:)` | Complex | Subtraction doesn't commute |

**Per-pick agreement-rate on the 12 measured picks: 12/12 = 100%.** Every `.bothPass` matches a mathematically commutative/associative/monotonic operation; every `.defaultFails` matches a non-commutative/non-associative one. The verifier's trial-budget loop found counterexamples to all 6 invalid properties (e.g., `Complex.pow` failed at trial 0 with an inf-vs-zero divergence on a 6-tuple input).

**This is the first end-to-end-from-indexer per-pick agreement-rate signal in the project's history**, directly comparable to cycle-46's synthetic-shape-class predictions (which reported 100% on a 30-pick sample). The synthetic and real numbers now align — at small N — confirming the architecture's load-bearing claim at the *capability* level.

## The 10 .measured-error picks — what stays broken

| Hash prefix | Template | Function | Cause |
|---|---|---|---|
| 0x4949, 0x51D5, 0x56A3, 0x68D5, 0x6D31, 0xB72E, 0xC6E1, 0x22C4 | round-trip | `exp`, `log`, `sinh`, `cosh`, `sin`, `cos`, `tanh`, `tan` (Complex) | V1.52.A free-function regression — `exp(value)` not in scope from workdir's imports. **v1.54 revert candidate.** |
| 0xD6C6, 0xE724 | commutativity / associativity | `rescaledDivide(_:_:)` (Complex) | Unknown — build failed; non-operator + non-EF surface name; classified as `.staticMethod`. Possibly an internal-API mismatch in the synthesized stub. **v1.54+ investigation.** |

## Cycle-46 predictions vs cycle-50 actuals (32-pick sample subset)

Cycles 42-46 predicted per-pick outcomes on a 32-pick stratified sample. Cycle-50 produces real measurements for **some** members of that sample. Comparing:

| Sample # | Hash prefix | Template | Cycle-27 verdict | Cycle-46 predicted | Cycle-50 actual | Match? |
|---:|---|---|---|---|---|---|
| #18 | 0xA9AD | monotonicity | accept | .bothPass | .bothPass | ✓ |
| #19 | 0xE062 | monotonicity | accept | .bothPass | .bothPass | ✓ |
| #24 | 0x7748 | commutativity | accept | .bothPass | .bothPass | ✓ |
| #26 | 0x60A0 | associativity | accept | .bothPass | .bothPass | ✓ |
| #27 | 0xB8DE | associativity | reject | .defaultFails | .defaultFails | ✓ |

5 of the 32-pick sample members produced measurable outcomes in cycle-50; all 5 match the cycle-46 prediction. **5/5 = 100% per-pick agreement on the sample subset that reached the property check.** The remaining 27 sample picks are still `.measured-error` (8 round-trip Complex EF regressions awaiting V1.52.A revert) or `.architectural-coverage-pending` (OC + Algo generic types awaiting v1.54+ TypeShape work).

## What cycle-50 establishes

1. **The architecture is sound, end-to-end.** Cycles 42-46 built the verify capability on synthetic SemanticIndexEntry inputs. Cycles 47-49 surfaced gaps in the synthetic↔real-indexer bridge. Cycle-50 produces the first 12 picks where the bridge is fully closed — and they all produce mathematically valid outcomes. The 100% per-pick agreement on the 5-pick sample-subset overlap matches the cycles 42-46 synthetic predictions.

2. **V1.53.A's DYLD injection is the single biggest cycle gain in the project's history.** 80 LoC closed +12 measured outcomes — the highest LoC/outcome efficiency since cycle-30's V1.30.0 hit the §19 ≥70% target.

3. **The remaining 87 architectural-coverage-pending picks need different fixes**. Most are OrderedCollections / swift-algorithms generic carrier types. v1.54+'s TypeShape-driven instantiation is the next-largest single workstream.

4. **The 8 V1.52.A free-function regressions are real and worth reverting.** Without the regression, cycle-50 would have hit ~20 measured outcomes (12 + 8 round-trip Complex EF picks). v1.54's V1.52.A revert plus V1.52.C carrier-name key fix should grow the sample to 18-22+ measured outcomes.

5. **The cycle-49 "libTesting.dylib is the load-bearing fix" framing was correct.** Without V1.52.B's stderr capture, the v1.53 cycle would have continued chasing the wrong gap.

## v1.54+ priorities (per cycle-50 evidence)

In order of expected impact:

1. **v1.54 — V1.52.A free-function revert** (drop EF-surface entries from `freeFunctionMap`). 8 cycle-50 build-failed round-trip Complex picks return to `.staticMethod` shape, then reach the property check via V1.53.A's DYLD fix. **Closes 8 picks; small +.bothPass / +.defaultFails delta**.

2. **v1.54 — V1.52.C carrier-name key fix** (bare `ChunkedByCollection` / `OrderedSet` instead of `<Type>.Index`). 3 chunked-Index picks reach swift build. **Closes 3+ picks; expected `.defaultFails` per cycle-46 predictions**.

3. **v1.54 — `_relaxedMul`/`rescaledDivide` build-failure investigation**. The 2 build-failed picks on cycle-50 don't have operator-named or EF-surface causes; they're build-failed for an unknown reason. Investigate via the v1.49 preamble or `Complex<Double>.rescaledDivide` API signature.

4. **v1.54-v1.55 — TypeShape-driven generic instantiation** for OC + Algo types. Dominant remaining category (60+ picks).

5. **v1.54 — Methodology guard**: fixture-level check that every `GenericBindingResolver.curatedBindings` key matches at least one indexer-produced carrier name. Prevents the V1.51.B + V1.52.C latent-key-format recurrence.

6. **v1.55+ — Phase 2 accept-flow integration** — gated on cycle-51+ growing the agreement-rate sample to 20+ picks for statistical reliability.

## Methodology notes

- **Wall-clock**: ~5 minutes for the 109-pick survey (vs cycle-49's ~4 min). The increase reflects the 12 picks now running their full trial-budget property check (100 default trials + edge pass where applicable).
- **DYLD propagation**: confirmed via the 12 picks reaching the property check. SIP scrubbing did not apply — verifier binary is user-built in the workdir, no Apple-signed binary in the spawn chain.
- **Per-pick cost when running the property check**: ~100-500ms for FP carriers (Complex/Double) with the default `small` budget (N=100). Build cost dominates total per-pick time on cold runs.
- **Cache behavior**: V1.53.A's `static let cachedTestingLibraryDirectory` ran once at survey start; 0.05ms amortized cost per pick after that.
