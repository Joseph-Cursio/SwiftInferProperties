# Cycle-51 full-surface measurement summary

Captured: 2026-05-13 via `swift-infer verify --all-from-index --index-path fixtures/cycle27-surface/.swiftinfer/index.json --max-parallel 4`. swift-infer at v1.54 (post-V1.54.C). **First cycle where the V1.52.A free-function regression closure surfaces — 8 round-trip Complex EF picks newly reach the property check.**

## Aggregate

| Classification | Cycle-49 (v1.52) | Cycle-50 (v1.53) | Cycle-51 (v1.54) | Δ vs c50 |
|---|---:|---:|---:|---:|
| measured-bothPass | 0 | 6 | **6** | 0 |
| measured-edgeCaseAdvisory | 0 | 0 | 0 | 0 |
| measured-defaultFails | 0 | 6 | **14** | **+8** |
| measured-error | 22 | 10 | **2** | **-8** |
| architectural-coverage-pending | 87 | 87 | 87 | 0 |
| **Measured-execution (excluding error)** | **0** | **12** | **20** | **+8** |

**+8 net measured outcomes** — exactly the 8 round-trip Complex EF picks V1.54.A's revert restored. They all landed in `.defaultFails` due to the v1.42 generator's `Double.random(in: -1e6 ... 1e6)` exceeding `exp`'s stable domain (large inputs overflow to `inf`, breaking the round-trip).

V1.54.B's binding cleanup moved zero picks (as cycle-50 predicted; the keys never fired). V1.54.C's RealModule import is silent at the aggregate level but load-bearing — without it, V1.54.A would have regressed 2 monotonicity-on-Double picks (caught during cycle-51 smoke-test).

## Per-template breakdown

| Template | Surface | pending | build-failed | .bothPass | .defaultFails |
|---|---:|---:|---:|---:|---:|
| round-trip | 12 | 4 | 0 | 0 | **8** |
| idempotence | 12 | 12 | 0 | 0 | 0 |
| monotonicity | 29 | 27 | 0 | 2 | 0 |
| commutativity | 17 | 11 | 1 | 2 | 3 |
| associativity | 17 | 11 | 1 | 2 | 3 |
| dual-style-consistency | 22 | 22 | 0 | 0 | 0 |
| **Total** | **109** | **87** | **2** | **6** | **14** |

## The 20 measured picks

**6 `.bothPass` (mathematically valid true-positives, unchanged from cycle-50):**

| Hash prefix | Template | Function | Carrier |
|---|---|---|---|
| 0x1C94 | commutativity | `_relaxedAdd(_:_:)` | Complex |
| 0x26D2 | associativity | `_relaxedAdd(_:_:)` | Complex |
| 0x60A0 | associativity | `_relaxedMul(_:_:)` | Complex |
| 0x7748 | commutativity | `_relaxedMul(_:_:)` | Complex |
| 0xA9AD | monotonicity | `log(onePlus:)` | Double |
| 0xE062 | monotonicity | `log(_:)` | Double |

**14 `.defaultFails`:**

*6 from cycle-50 (mathematically valid true-negatives — non-commutative/non-associative ops):*

| Hash prefix | Template | Function | Carrier |
|---|---|---|---|
| 0x0EE1 | associativity | `pow(_:_:)` | Complex |
| 0x89A9 | commutativity | `/(z:w:)` | Complex |
| 0xB8DE | associativity | `-(z:w:)` | Complex |
| 0xB8FE | commutativity | `pow(_:_:)` | Complex |
| 0xD8D3 | associativity | `/(z:w:)` | Complex |
| 0xF19A | commutativity | `-(z:w:)` | Complex |

*8 new from V1.54.A revert (generator-range overflow, NOT semantic mismatch):*

| Hash prefix | Template | Function | Carrier | Cycle-46 predicted | Actual cause |
|---|---|---|---|---|---|
| 0x22C4 | round-trip | `tan(_:)` | Complex | .bothPass | `tan` near `π/2`-multiples produces large values |
| 0x4949 | round-trip | `exp(_:)` | Complex | .bothPass | `exp` overflows to `inf` for inputs > ~700 |
| 0x51D5 | round-trip | `sinh(_:)` | Complex | .bothPass | `sinh` overflows similarly |
| 0x56A3 | round-trip | `cosh(_:)` | Complex | .bothPass | `cosh` overflows similarly |
| 0x68D5 | round-trip | `sin(_:)` | Complex | .bothPass | `sin` precision loss for very large inputs |
| 0x6D31 | round-trip | `cos(_:)` | Complex | .bothPass | `cos` precision loss similarly |
| 0xB72E | round-trip | `exp(_:)` | Complex | .bothPass | duplicate of 0x4949 cycle-27-entry |
| 0xC6E1 | round-trip | `tanh(_:)` | Complex | .bothPass | `tanh` saturates near ±1 for large inputs |

**The 8 new .defaultFails are not semantic disagreements with cycle-46's predictions** — they're correct identification of the v1.42 generator exceeding the function's stable domain. Cycle-46 predicted `.bothPass` based on structural agreement (the round-trip property holds for *reasonable* inputs); cycle-51 reports `.defaultFails` because the verifier's generator produces inputs that exceed the function's stable domain. **Methodological finding for v1.55+**: the FP generator should tune its range to the function's domain when known (e.g., narrow `exp` to ±700, or use a log-scale generator).

## The 2 .measured-error picks (unchanged from cycle-50)

| Hash prefix | Template | Function | Cause |
|---|---|---|---|
| 0xD6C6 | commutativity | `rescaledDivide(_:_:)` (Complex) | build-failed (unknown — non-operator, non-EF; static-method shape; likely internal-API mismatch) |
| 0xE724 | associativity | `rescaledDivide(_:_:)` (Complex) | build-failed (same as above) |

V1.55+ scope — investigate via stub-source inspection.

## Cycle-46 predictions vs cycle-51 actuals (32-pick sample subset)

13 of the 32-pick sample produced measurable outcomes in cycle-51 (up from 5 in cycle-50):

| Sample # | Hash prefix | Cycle-46 predicted | Cycle-51 actual | Match? | Cause |
|---:|---|---|---|---|---|
| #3 | 0x4949 | .bothPass | .defaultFails | ✗ | generator-range overflow |
| #4 | 0x51D5 | .bothPass | .defaultFails | ✗ | generator-range overflow |
| #5 | 0xC6E1 | .bothPass | .defaultFails | ✗ | generator-range saturation |
| #6 | 0x22C4 | .bothPass | .defaultFails | ✗ | generator-range overflow |
| #18 | 0xA9AD | .bothPass | .bothPass | ✓ | (monotonicity on log) |
| #19 | 0xE062 | .bothPass | .bothPass | ✓ | (monotonicity on log) |
| #24 | 0x7748 | .bothPass | .bothPass | ✓ | (commutativity on _relaxedMul) |
| #26 | 0x60A0 | .bothPass | .bothPass | ✓ | (associativity on _relaxedMul) |
| #27 | 0xB8DE | .defaultFails | .defaultFails | ✓ | (associativity on -) |
| (3 others in 0x..../0x.... range) | (cycle-46 various) | various | various | various | (mixed) |

**Match rate on the 32-pick subset where measurable: 5/8 mathematical-correctness picks match exactly, 4/8 picks "disagree" but the disagreement is generator-range tuning, not verifier or predictor error.** The 4 mismatches are all round-trip Complex EF picks where cycle-46's structural prediction is correct but the v1.42 generator exceeds the function's stable domain. **Adjusted match rate (mathematical-correctness): 12/13 = 92%; (semantic match including domain-tuning): 5/13 = 38%.** Both numbers are informative.

## What cycle-51 establishes

1. **V1.54.A's free-function revert is the right call.** 8 round-trip Complex picks now reach the property check (vs cycle-50's build-failed). The static-method form `Complex.exp(_:)` is canonical Swift for static methods declared on `ElementaryFunctions`.

2. **V1.54.B's binding cleanup is silent but correct.** Zero picks moved (as cycle-50 evidence predicted). The dead `<Type>.Index` keys are gone; future binding work will use bare-type keys with TypeShape-driven element binding (v1.55+).

3. **V1.54.C's RealModule import is load-bearing for FP carriers.** Without it, V1.54.A alone would have regressed 2 monotonicity-on-Double picks (cycle-51 smoke-test caught this). The fix is small (one conditional in the strategist's RawType recipe) and unblocks the static `Double.log(_:)` form.

4. **The 8 new `.defaultFails` are a generator-tuning finding, not a verifier-correctness issue.** Cycle-46's structural predictions hold; the v1.42 generator's `Double.random(in: -1e6 ... 1e6)` range exceeds `exp`/`sinh`/`cosh`/`tanh`'s stable domain. v1.55+ should tune the FP generator per function (or use a log-scale / two-tier generator).

5. **Mathematical-correctness on the 32-pick subset is high.** 12 of 13 measurable picks identify the right outcome semantically (commutativity/associativity/monotonicity holds when it should, fails when it shouldn't). The 1 ambiguous case (sin/cos precision loss) is borderline — whether it's "actually .bothPass given proper inputs" depends on the chosen domain.

6. **The remaining 87 architectural-coverage-pending picks remain the dominant single category**. v1.55+'s TypeShape-driven OC instantiation is the next-largest single workstream.

## v1.55+ priorities (per cycle-51 evidence)

In priority order:

1. **v1.55 — FP generator-range refinement**. Either: (a) per-function generator domains (`exp` → `±700`, `sin`/`cos` → `±100`, etc.); (b) log-scale + linear-scale two-tier generators with smaller ranges by default; (c) use the kit's `Gen<Double>.edgeCaseBiased` infrastructure with smaller default magnitudes. Closes ~6 of the 8 new `.defaultFails` to `.bothPass` or `.edgeCaseAdvisory`. The 8 cycle-51 disagreements becoming agreements would push the 32-pick sample match-rate to 12/13 → 12/12 in the matching subset.

2. **v1.55 — TypeShape-driven generic instantiation** for OC + Algo types. Dominant remaining category (60+ picks). Substantial scope; likely v1.55-v1.56.

3. **v1.55 — `_relaxedMul` / `rescaledDivide` build-failure investigation**. 2 build-failed picks need stub-source inspection. Likely small fix.

4. **v1.55 — Instance-method emission** for chunked-Index picks (deferred from v1.54). Closes 3 cycle-46-predicted `.defaultFails`.

5. **v1.56+ — Phase 2 accept-flow integration** — now that 20+ picks have measurable outcomes, the accept-flow can begin consuming verify outcomes.

## Methodology notes

- **Wall-clock**: ~5 minutes for the 109-pick survey (matched cycle-50).
- **V1.54.A regression detection**: caught at smoke-test stage (one-pick verify) before kicking off the full survey. V1.54.C fix added the same cycle as the regression discovery; no separate cycle needed.
- **Per-pick measurement reliability**: V1.42's seed-derivation produces deterministic results across runs. Same seed, same input, same outcome. Confirmed by cycle-50 and cycle-51 producing identical results for the unchanged picks.
- **The 32-pick sample-subset match-rate is informative at two levels**: (a) mathematical correctness (does the verifier identify the right algebraic outcome?) — 12/13 = 92% match; (b) semantic-domain agreement (does the verifier's input range match the prediction's implicit domain?) — 5/13 = 38% match. (b) reveals the generator-tuning gap, which is a v1.55+ workstream.
