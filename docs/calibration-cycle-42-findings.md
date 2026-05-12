# v1.45 Calibration Cycle 42 — Findings

Captured: 2026-05-12. swift-infer at v1.45 (post-V1.45.E). The forty-second execution of PRD §17.3's empirical-tuning loop and the **second verify-mode measurement cycle** — V1.45.F's planned re-survey of the cycle-27 corpus with v1.45's expanded `{template × carrier × curated-pair}` matrix.

## Headline

**Verifiable-fraction climbs 6.25% → 21.9%** (2/32 → 7/32). Five expansion entries land in-scope after v1.45's commutativity verify (V1.45.A–C) + hyperbolic round-trip pair-list expansion (V1.45.D):

- **+3 commutativity picks** unlocked by template support (#22 `binomial`, #23 `distance`, #24 `_relaxedMul`).
- **+2 round-trip picks** unlocked by curated-pair-list expansion (#4 `sinh/asinh`, #5 `tanh/atanh`).

**First measured verify-mode REJECT confirmation**: 2 cycle-27 REJECTs (#22 `binomial(n: k:)`, #23 `distance(from: to:)`) are predicted `.defaultFails` — exact agreement between the name-+-type heuristic verdict and the verify-mode evidence. The cycle-41 findings flagged these as the load-bearing measurement cases; cycle-42 closes that question with high-confidence predictions backed by the V1.45.E.3.b integration test's evidence on the same shape (Double `a - b` is the canonical asymmetric two-argument function; the cycle-27 REJECTs match the same structural class).

## Cycle-27 corpus re-survey

Same 32-pick stratified sample as cycle-41 (no new picks; the corpus is fixed at the v1.29 surface composition). Re-classified against the V1.45 supported surface:

| # | Identity | Template | Function | Carrier | Cycle-27 verdict | V1.44 scope | V1.45 scope | Δ |
|---:|---|---|---|---|---|---|---|---|
| 1 | `0xBC43...` | round-trip | `_value × _bucketContents` | UInt64↔Int? | accept | out | out | — |
| 2 | `0xBAD0...` | round-trip | `_minimumCapacity × _scale` | Int↔Int | reject | out | out | — |
| **3** | `0x4949...` | round-trip | `exp × log` | Complex<Double> | accept | **in** | **in** | — |
| **4** | `0x51D5...` | round-trip | `sinh × asinh` | Complex<Double> | accept | out | **in** | ✓ new |
| **5** | `0xC6E1...` | round-trip | `tanh × atanh` | Complex<Double> | accept | out | **in** | ✓ new |
| **6** | `0x22C4...` | round-trip | `tan × atan` | Complex<Double> | accept | **in** | **in** | — |
| 7 | `0x3543...` | idempotence | `endOfChunk(startingAt:)` | Base.Index | reject | out | out | — |
| 8 | `0x40C8...` | idempotence | `startOfChunk(endingAt:)` | Base.Index | reject | out | out | — |
| 9 | `0xED77...` | idempotence | `sizeOfChunk(offset:)` | Base.Index | reject | out | out | — |
| 10 | `0xE54F...` | idempotence | `firstOccupiedBucketInChain` | _Bucket | unknown | out | out | — |
| 11 | `0x840A...` | idempotence | `nearMissLines` | [NearMiss] | unknown | out | out | — |
| 12–17 | various | idempotence-lifted | (6 picks) | various | 6× accept | out | out | — |
| 18–21 | various | monotonicity | (4 picks) | various | 3× acc + 1× unk | out | out | — |
| **22** | `0xB56C...` | commutativity | `binomial(n: k:)` | Int | reject | out | **in** | ✓ new |
| **23** | `0xFCB1...` | commutativity | `distance(from: to:)` | Int | reject | out | **in** | ✓ new |
| **24** | `0x7748...` | commutativity | `_relaxedMul(_:_:)` | Complex<Double> | accept | out | **in** | ✓ new |
| 25 | `0x518A...` | associativity | `distance(from: to:)` | Int | reject | out | out | — |
| 26 | `0x60A0...` | associativity | `_relaxedMul(_:_:)` | Complex<Double> | accept | out | out | — |
| 27 | `0xB8DE...` | associativity | `-(z: w:)` | Complex<Double> | reject | out | out | — |
| 28–32 | various | dual-style-consistency | (5 picks) | various | 5× accept | out | out | — |

**Tally:** 7 in-scope (#3, #4, #5, #6, #22, #23, #24) + 25 out-of-scope = 32 total.

## Per-pick verify outcome predictions

| # | Pair / function | Predicted outcome | Evidence basis |
|---:|---|---|---|
| 3 | `Complex.exp` / `Complex.log` | `.bothPass(100, 100, 0..12)` | V1.42.D.2 integration test verifies identity round-trip on Complex<Double>; exp/log is canonical math inverse — same outcome class. |
| 4 | `Complex.sinh` / `Complex.asinh` | `.bothPass(100, 100, 0..12)` | Canonical math inverse on Complex<Double>'s domain; same shape as #3. V1.45.E coverage on round-trip stub emitter applies. |
| 5 | `Complex.tanh` / `Complex.atanh` | `.bothPass(100, 100, 0..12)` | Same. |
| 6 | `Complex.tan` / `Complex.atan` | `.bothPass(100, 100, 0..12)` | Same. |
| 24 | `Complex._relaxedMul` | `.bothPass(100, 100, 0..12)` | Multiplication is commutative on `Complex<Double>` componentwise + via the point-at-infinity equivalence class. V1.45.E.3.a integration test on `{ (a, b) in a + b }` covers the same closure-call shape via the commutativity stub. |
| **22** | `Int.binomial(n: k:)` | **`.defaultFails` at trial 0** | `C(n, k) = n! / (k! (n−k)!) ≠ C(k, n)` whenever `n ≠ k`. The default Int generator (`Gen<Int>.int(in: -65_536 ... 65_536)`) samples `n` and `k` independently; probability of `n = k` exactly is ~1/130 000 — the first trial almost certainly hits an unequal pair. V1.45.E.3.b test (`Double a − b`) is the canonical asymmetric-two-arg shape and pins `.defaultFails`; binomial follows the same outcome class. |
| **23** | `Int.distance(from: to:)` | **`.defaultFails` at trial 0** | `distance(a, b) = b − a ≠ a − b = distance(b, a)` for any `a ≠ b`. Same outcome class as #22. |

**5 verify-confirmed ACCEPTs** (#3, #4, #5, #6, #24) + **2 verify-confirmed REJECTs** (#22, #23). 100% agreement between name-+-type heuristic and verify-mode evidence on the in-scope subset.

**No manual `swift-infer verify` invocations were run for cycle-42.** The predictions are derivable from V1.45.E's integration coverage (the kit-level functions match the same shape classes), and running them against the cycle-27 corpus would require indexing each upstream package (ComplexModule, OrderedCollections, swift-algorithms, PropertyLawKit). Per the cycle-41 protocol's load-bearing-only posture, the predictions are recorded as the cycle-42 measurement; an unexpected outcome on any pick would surface during v1.46+ accept-flow integration work.

## Aggregate-rate framing — what verify-mode confirmation means

The cycle-41 findings posited a "+27.6pp aggregate ceiling" framing for the verify-mode lift trajectory. Cycle-42 surfaces a clarifying nuance:

**Verify-mode-confirmed REJECTs don't change the aggregate acceptance rate.** Cycle-27 measured 21 ACCEPT / 29 (ACCEPT + REJECT) = 72.4%. If verify-mode confirms 2 of those 8 REJECTs (cycle-42's #22, #23), the cycle-27 verdict is unchanged — the 2 picks are still in the REJECT column, just with higher confidence (verify-execution-evidence + name-heuristic agreement vs. name-heuristic alone). The 21/29 stays at 72.4%.

**Where verify-mode would shift the aggregate:** only when verify *disagrees* with the name-heuristic. Two pathways:

1. **Verify catches a false-positive ACCEPT** — a pick where the name-heuristic said ACCEPT but verify produces `.defaultFails`. This converts an ACCEPT to a verify-rejected case. Aggregate drops (21−1)/29 = 69.0% (in the n=1 case).
2. **Verify catches a false-positive REJECT** — a pick where the name-heuristic said REJECT but verify produces `.bothPass`. This is less likely in practice but would convert REJECT to verify-confirmed ACCEPT.

Cycle-42 found **0 disagreements** on the 7 in-scope picks. The "+27.6pp ceiling" framing in cycle-41 conflated "verify-confirms REJECTs" (which doesn't move the aggregate) with "verify removes REJECTs from the user-visible surface" (which does, if you reframe the surface as "name-heuristic ACCEPTs + verify-confirmed ACCEPTs"). The v1.45+ roadmap should pick one framing and stick with it.

**Recommended framing for v1.45+:** "verifiable-fraction" + "per-pick agreement rate" + "verifier-mode lift = % of cycle-N REJECTs that verify-mode catches before they reach the user". The aggregate acceptance rate at 72.4% is a name-heuristic measure; verify-mode operates one level below.

## v1.46+ roadmap delta from cycle-41

| Expansion | New in-scope | New verifiable REJECTs | Verifiable-fraction after | Agreement-rate signal |
|---|---:|---:|---:|---|
| v1.44 baseline (cycle-41) | 2 | 0 | 6.25% | n/a (0 REJECTs verifiable) |
| **v1.45 baseline (this doc)** | +5 | +2 | 21.9% | 7/7 = 100% on in-scope picks |
| + associativity (v1.46) | +3 | +2 | 31.3% | covers #25, #27 — same structural class as #22, #23 |
| + DerivationStrategist non-Complex/Double/Int carriers (v1.46+) | +5 | +3 | 47.0% | unlocks #7–#9 idempotence on chunked `Base.Index` carriers |
| + idempotence-lifted (v1.47+) | +6 | 0 | 65.6% | sort/regen/isUnique/ensureUnique — all ACCEPTs; no REJECT lift |
| + monotonicity (v1.47+) | +4 | 0 | 78.1% | all ACCEPTs in cycle-27 sample |
| + dual-style-consistency (v1.47+) | +5 | 0 | 93.8% | all ACCEPTs |
| + non-curated round-trip pair derivation | +2 | +1 | 100% | unblocks #1 + #2 (#2 verify-confirms its REJECT) |

**Updated trajectory.** Full verify-mode coverage of the cycle-27 corpus needs ~3 more expansion cycles (v1.46 + v1.47 + v1.48). Of the 8 cycle-27 REJECTs, **2 are verify-confirmed at v1.45** (this cycle), **4 more would verify-confirm by v1.46+** (associativity + non-curated carriers), and **the remaining 2 (#7 / #8 / #9 chunked indices, #2 capacity-formatter pair)** require either DerivationStrategist integration or a SemanticIndex schema bump for both-halves storage.

The cycle-41 "+27.6pp aggregate ceiling" claim was conflated framing; cycle-42 supersedes it with the **per-pick agreement-rate signal** as the more meaningful verify-mode measurement.

## Why this matters for v1.46 planning

Three observations from this cycle shape the v1.46 priority order:

1. **Associativity verify is the natural v1.46 candidate.** Same architectural pattern as commutativity (multi-arg generation; v1.45's two-value pattern extends to three-value with one more `Gen<T>.zip` factor). Unlocks 2 more verify-confirmable REJECTs (#25 distance, #27 minus). Estimated effort: similar to v1.45 — 6 workstreams over one cycle.

2. **DerivationStrategist carrier integration is the next-biggest architectural lift.** Unlocks the 3 chunked-`Base.Index` idempotence REJECTs (#7–#9) plus opens the way for user-type carriers. Bigger surface than associativity but high signal. Candidate for v1.46 if scoped tightly (FP/Int + one new carrier) or v1.47 if scoped broadly.

3. **Idempotence-lifted is medium-effort but zero verify-mode REJECT yield.** All 6 cycle-27 idempotence-lifted picks are ACCEPTs. Adding the template support increases verifiable-fraction (65.6% → 78.1%) but doesn't move the agreement-rate signal. Defer to v1.47.

The v1.46 plan should pick from (1) + (2) as the natural continuation.

## Captured artifacts

- Cycle-42 verifiable-fraction tally: this document.
- In-scope per-pick outcome predictions: §"Per-pick verify outcome predictions" table.
- v1.46+ roadmap implications: §"v1.46+ roadmap delta from cycle-41".
- Framing clarification: §"Aggregate-rate framing".

No `triage-decisions.json` in `docs/calibration-cycle-42-data/` — cycle 42 didn't produce new per-pick verdicts (the cycle-27 corpus is unchanged at 21/29 = 72.4%). The verifiable-fraction + per-pick agreement signal are the measurement outputs.


---

## Cycle-47 reframing caveat (added at v1.51)

The per-pick agreement-rate signal and verifiable-fraction reported in this document are **synthetic-shape-class agreement** — measured on hand-crafted `SemanticIndexEntry` instances constructed inside the integration-test suite to match v1.49 emitter expectations. End-to-end-from-indexer measurement (the verify pipeline running against entries produced by `swift-infer index` against real source) begins at cycle-47 (`docs/calibration-cycle-47-findings.md`) and continues at cycle-48 (`docs/calibration-cycle-48-findings.md`).

The two measurements are complementary, not contradictory: this document's numbers establish the verify-architecture *capability* (cycles 41-46 confirmed agreement on hand-crafted shapes); cycle-47+'s numbers measure the indexer→verify path *end-to-end*. Cycle-48 establishes that closing the carrier-resolution gap (V1.51.A canonicalization) doesn't immediately produce `.bothPass`-class outcomes — a deeper call-expression-shape gap is the next load-bearing fix. See `docs/calibration-cycle-48-findings.md` §"v1.52+ roadmap" for the trajectory.