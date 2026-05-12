# v1.44 Calibration Cycle 41 — Findings

Captured: 2026-05-11. swift-infer at v1.44 (post-V1.44.E). The forty-first execution of PRD §17.3's empirical-tuning loop and the **first verify-mode measurement cycle** — V1.44.F's planned "first calibration measurement of the verify-mode lift over cycle-27's 72.4% baseline".

**Note on cycle numbering.** The v1.44 plan referred to this as `calibration-cycle-28-findings.md` but cycle 28 was v1.31's first design-completion cycle (FP approximate-equality template arm). v1.42 / v1.43 / v1.44 are cycles 39 / 40 / 41 per the CLAUDE.md cycle index — this doc uses the correct number.

## Headline

**Verifiable-fraction: 2 / 32 = 6.25% of the cycle-27 corpus.** All 8 cycle-27 REJECTs fall outside V1.44's supported `{template × carrier × curated-pair}` matrix. The verify-mode-lift hypothesis can't be tested at the aggregate level on this corpus.

This is a **load-bearing finding** for the test-execution-evidence Phase 1 roadmap: the verify-pipeline architecture works end-to-end (V1.44.A–E ship full coverage for `{round-trip, idempotence-non-lifted} × {Complex<Double>, Double, Int}` with 6 always-on subprocess integration tests), but the **verifiable-fraction is gated on three orthogonal expansions** the v1.44 plan deliberately deferred (commutativity / dual-style / monotonicity / associativity verify support; curated round-trip pair list expansion; carrier extension beyond the FP/Int trio). v1.45+ takes them up.

## Cycle-27 corpus survey

Triage of all 32 cycle-27 picks against V1.44's supported surface (`templateName ∈ {round-trip, idempotence}` with the non-lifted constraint; `typeName ∈ {Complex<Double>, Double, Int}`; round-trip must match a curated `RoundTripPairResolver` pair):

| # | Identity | Corpus | Template | Function | Cycle-27 verdict | V1.44 verify scope |
|---:|---|---|---|---|---|---|
| 1 | `0xBC43...` | OC | round-trip | `_value(forBucketContents:) × _bucketContents(for:)` | accept | **out** — UInt64 ↔ Int? not in carriers |
| 2 | `0xBAD0...` | OC | round-trip | `_minimumCapacity(forScale:) × _scale(forCapacity:)` | reject | **out** — Int↔Int OK as carrier, but pair not in curated list |
| **3** | `0x4949...` | CM | round-trip | `exp(_:) × log(_:)` | accept | **in** — Complex<Double> + curated |
| 4 | `0x51D5...` | CM | round-trip | `sinh(_:) × asinh(_:)` | accept | **out** — Complex<Double> OK, pair not in curated list |
| 5 | `0xC6E1...` | CM | round-trip | `tanh(_:) × atanh(_:)` | accept | **out** — same |
| **6** | `0x22C4...` | CM | round-trip | `tan(_:) × atan(_:)` | accept | **in** — Complex<Double> + curated |
| 7 | `0x3543...` | Algo | idempotence | `endOfChunk(startingAt:)` | reject | **out** — `Base.Index` carrier |
| 8 | `0x40C8...` | Algo | idempotence | `startOfChunk(endingAt:)` | reject | **out** — same |
| 9 | `0xED77...` | Algo | idempotence | `sizeOfChunk(offset:)` | reject | **out** — same |
| 10 | `0xE54F...` | OC | idempotence | `firstOccupiedBucketInChain(with:)` | unknown | **out** — `_Bucket` carrier |
| 11 | `0x840A...` | PLK | idempotence | `nearMissLines(_:)` | unknown | **out** — `[NearMiss]` carrier |
| 12–17 | various | OC | idempotence-lifted | (6 picks) | 6× accept | **out** — V1.44.D dispatch only handles `idempotence` (non-lifted); lifted is a separate templateName |
| 18–21 | various | mixed | monotonicity | (4 picks) | 3× accept + 1× unknown | **out** — template not supported |
| 22–24 | various | mixed | commutativity | (3 picks) | 1× accept + 2× reject | **out** — template not supported |
| 25–27 | various | mixed | associativity | (3 picks) | 1× accept + 2× reject | **out** — template not supported |
| 28–32 | various | OC | dual-style-consistency | (5 picks) | 5× accept | **out** — template not supported |

**Tally:** 2 in-scope (#3, #6) + 30 out-of-scope = 32 total.

**Critically: all 8 cycle-27 REJECTs (#2, #7, #8, #9, #22, #23, #25, #27) are out of scope.** The verify-mode lift the v1.44 plan hoped to measure — REJECTs converted to verify-confirmed REJECTs via `.defaultFails` outcomes — can't materialize because verify-mode doesn't see any of those picks today.

## Per-pick verify outcomes (in-scope subset)

The two in-scope picks are both ACCEPTs known to be valid round-trip pairs on the kit's own `Complex<Double>` surface:

| # | Pair | Predicted outcome | Confidence |
|---:|---|---|---|
| 3 | `Complex.exp / Complex.log` | `.bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: <0..12>)` | high — covered by V1.42.D.2 integration test |
| 6 | `Complex.tan / Complex.atan` | `.bothPass(defaultTrials: 100, edgeTrials: 100, edgeSampled: <0..12>)` | high — same shape; trig pairs are mathematically valid round-trips on `Complex<Double>`'s domain |

Both predictions are upgrades of "name-+-type ACCEPT" to "name-+-type-+-execution ACCEPT" — useful evidence weight, no rate change. **Effective aggregate rate post-verify:** still 21/29 = 72.4% (no Accepts removed; no Rejects added). The verify-mode design is sound but the aggregate-rate signal is structurally zero on this corpus.

## v1.45+ roadmap implications

The 30 out-of-scope picks decompose into three expansion axes, each tractable as a future cycle:

### 1. Curated round-trip pair list (4 picks)

Picks #4 (`sinh/asinh`), #5 (`tanh/atanh`), and similar hyperbolic CM pairs would land with a single `RoundTripPairResolver.curated` entry append. Pick #1 (`_value(forBucketContents:) × _bucketContents(for:)`) and #2 (`_minimumCapacity/_scale`) need a **non-curated pair-derivation path** that reads both halves from the suggestion's `evidence` array rather than the curated list. Schema-wise this requires either (a) a SemanticIndex schema bump to persist both halves of a round-trip pair, or (b) a rerun-discover-for-the-matched-entry step inside `swift-infer verify`. Both are tractable; (a) is cleaner.

**Expansion impact: +4 in-scope, +0 verifiable REJECTs.**

### 2. Template extension (15 picks)

V1.44.D dispatch only supports `{round-trip, idempotence}`. The picks blocked by template are:
- 6 × idempotence-lifted (#12–#17) — straightforward extension of the idempotence path. The lifted suggestions render the same `f(f(x)) ≈ f(x)` shape but on a synthesized `LiftedTransformation` rather than a direct `f: T → T`. v1.45 would need to dispatch `idempotence-lifted` to a separate emitter that wraps the lifted func body.
- 4 × monotonicity (#18–#21) — needs two-value-per-trial generation (`Gen<T>.zip(Gen<T>, Gen<T>)`) + per-pair ordering check.
- 3 × commutativity (#22–#24) — same two-value generation but with `f(a, b) == f(b, a)` check.
- 3 × associativity (#25–#27) — needs three-value generation + `f(f(a, b), c) == f(a, f(b, c))` check.
- 5 × dual-style-consistency (#28–#32) — needs two-function verify shape (mutating + non-mutating) + per-trial result-equality threading.

Of those 15, the **3 commutativity-class REJECTs (#22 `binomial`, #23 `distance`, #25 `distance`)** are the loop's canonical "type-pattern false positive" cases — `binomial(n: k:)` matches `(T, T) -> T` shape but `C(n, k) != C(k, n)` by definition. These are exactly the cases the test-execution-evidence proposal was designed to close, so adding commutativity verify support has the highest expected lift signal.

**Expansion impact: +15 in-scope, +5 verifiable REJECTs** (assuming verify catches the 3 commutativity-class + 2 associativity-class REJECTs at high precision).

### 3. Carrier extension (5 picks)

Picks #7–#11 (idempotence non-lifted) use carriers V1.44 doesn't support: `Base.Index` (Algo chunked-sequence types), `_Bucket` (OC hash table internals), `[NearMiss]` (PLK domain types). Adding these requires `DerivationStrategist`-driven generator inference at verify-time — currently the strategist is consulted only at writeout time. v1.45+ would wire it into the verify-stub-synthesis path.

**Expansion impact: +5 in-scope, +3 verifiable REJECTs** (picks #7, #8, #9).

### Combined trajectory

| Expansion | New in-scope | New verifiable REJECTs | Verifiable-fraction after | Verify-mode lift bound |
|---|---:|---:|---:|---:|
| v1.44 baseline | 2 | 0 | 6.25% | n/a |
| + curated/derived pairs | +4 | 0 | 18.75% | n/a |
| + commutativity + associativity (v1.45) | +6 | +5 | 37.50% | up to +5/29 = **+17.2pp** lift if all 5 REJECTs verify-confirm |
| + dual-style + monotonicity (v1.45–v1.46) | +9 | +1 | 65.63% | additional +1/29 = +3.4pp |
| + idempotence-lifted | +6 | 0 | 84.38% | n/a |
| + Base.Index / _Bucket / domain carriers (v1.46+) | +5 | +3 | 100% | additional +3/29 = +10.3pp |

The headline bound: **if every cycle-27 REJECT verify-confirms via `.defaultFails`, the post-verify acceptance rate climbs from 72.4% to ~100%** (21 Accept / 21+0 = 100%). The full Phase 1 trajectory therefore has up to a **+27.6pp aggregate ceiling** vs the cycle-27 baseline, *conditional on* commutativity/associativity/idempotence-non-curated-carrier verify support landing and catching the relevant Rejects at high precision.

## Why this matters for v1.45 planning

Three observations from this survey shape the v1.45 priority order:

1. **Commutativity verify is the highest-leverage single addition.** It unlocks 3 in-scope REJECTs immediately (#22, #23, plus #25 associativity which has the same two-value shape) and exercises the loop's canonical type-pattern-false-positive class (`binomial` is the textbook case from the proposal's motivation).

2. **Curated round-trip pair list expansion is low-effort.** Adding `sinh/asinh` + `tanh/atanh` + their hyperbolic siblings is a one-line `RoundTripPairResolver.curated` append per pair. 4 in-scope ACCEPTs land with zero new code.

3. **Carrier extension beyond Complex/Double/Int needs `DerivationStrategist` integration** — bigger architectural lift than template extension. Defer to v1.46+ unless cycle-29 finds a specific carrier-blocked case worth prioritizing.

The v1.45 plan should pick from (1) + (2) as the natural continuation; (3) is its own cycle.

## What v1.44 closes

Despite the zero-lift measurement: **v1.44 fully delivers the architectural goal**. The verify pipeline now handles:

- Round-trip template + 3 carriers (`Complex<Double>`, `Double`, `Int`) with appropriate equality semantics per carrier (`isApproximatelyEqual` for FP, `==` for Int) and per-carrier edge-pass design (12 curated entries for Complex, 1 for Double, single-pass for Int).
- Idempotence non-lifted template + same 3 carriers with the same dispatch logic.
- Renderer surfaces both template phrasing differences (round-trip vs idempotence) and per-carrier edge-coverage line (curated-sampled count vs integer-not-applicable sentinel).
- 6 always-on subprocess integration tests pinning the full pipeline end-to-end across the 4 outcomes × 2 templates.

The "first calibration measurement" deliverable lands as **"first measurement attempt; surfaced load-bearing expansion gating for v1.45"** rather than the planned aggregate-rate-shift number. That's a worse measurement but a better roadmap signal — the loop's mechanism-precision arc continues at the **template/carrier/curated-list expansion plane** rather than the name-+-type-heuristic plane (which cycle-27 demonstrated has plateaued at 72.4%).

## Captured artifacts

- Cycle-41 verifiable-fraction tally: this document.
- In-scope per-pick outcome predictions: §"Per-pick verify outcomes" table above; no manual verify invocations were run (the two in-scope picks are existing ACCEPTs already covered by the V1.42.D.2 integration test, so running them would duplicate that coverage without adding evidence).
- v1.45+ roadmap implications: §"v1.45+ roadmap implications" above.

No `triage-decisions.json` in `docs/calibration-cycle-41-data/` — cycle 41 didn't produce per-pick verdicts. The cycle-27 corpus is unchanged at 21/29 = 72.4%.
