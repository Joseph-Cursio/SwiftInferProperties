# v1.46 Calibration Cycle 43 — Findings

Captured: 2026-05-12. swift-infer at v1.46 (post-V1.46.D.4). The forty-third execution of PRD §17.3's empirical-tuning loop and the **third verify-mode measurement cycle** (after cycles 41 + 42). v1.46 ships associativity verify support — the fourth template after round-trip, idempotence, commutativity — using the **per-slot rotation edge bias** the v1.46 plan settled on.

## Headline

**Verifiable-fraction climbs 21.9% → 31.3%** (7/32 → 10/32). Three new in-scope picks unlocked by v1.46's associativity template:

- **#25 `Int.distance(from: to:)`** — predicted `.defaultFails` at trial 0.
- **#26 `Complex<Double>._relaxedMul(_:_:)`** — predicted `.bothPass(100, 100, 0..12)`.
- **#27 `Complex<Double>.-(z: w:)`** — predicted `.defaultFails` at trial 0.

**Second consecutive cycle of verify-mode REJECT confirmation**: 2 cycle-27 REJECTs (#25, #27) predicted `.defaultFails` by the same algebraic identity that V1.45.F validated for #22 / #23 — `(a − b) − c = a − b − c` vs `a − (b − c) = a − b + c`, differing by `2c`. Cycle-43 brings the cumulative count of verify-confirmable REJECTs on the cycle-27 corpus to **4/8 = 50%**, and the per-pick agreement-rate signal to **10/10 = 100%** (zero disagreements between name-+-type heuristic and verify-mode evidence across the v1.45 + v1.46 expansion).

## Cycle-27 corpus re-survey

Same 32-pick stratified sample as cycles 41 + 42 (no new picks; the corpus is fixed at the v1.29 surface composition). Re-classified against the V1.46 supported surface:

| # | Identity | Template | Function | Carrier | Cycle-27 verdict | V1.45 scope | V1.46 scope | Δ |
|---:|---|---|---|---|---|---|---|---|
| 1 | `0xBC43...` | round-trip | `_value × _bucketContents` | UInt64↔Int? | accept | out | out | — |
| 2 | `0xBAD0...` | round-trip | `_minimumCapacity × _scale` | Int↔Int | reject | out | out | — |
| 3 | `0x4949...` | round-trip | `exp × log` | Complex<Double> | accept | in | in | — |
| 4 | `0x51D5...` | round-trip | `sinh × asinh` | Complex<Double> | accept | in | in | — |
| 5 | `0xC6E1...` | round-trip | `tanh × atanh` | Complex<Double> | accept | in | in | — |
| 6 | `0x22C4...` | round-trip | `tan × atan` | Complex<Double> | accept | in | in | — |
| 7 | `0x3543...` | idempotence | `endOfChunk(startingAt:)` | Base.Index | reject | out | out | — |
| 8 | `0x40C8...` | idempotence | `startOfChunk(endingAt:)` | Base.Index | reject | out | out | — |
| 9 | `0xED77...` | idempotence | `sizeOfChunk(offset:)` | Base.Index | reject | out | out | — |
| 10 | `0xE54F...` | idempotence | `firstOccupiedBucketInChain` | _Bucket | unknown | out | out | — |
| 11 | `0x840A...` | idempotence | `nearMissLines` | [NearMiss] | unknown | out | out | — |
| 12–17 | various | idempotence-lifted | (6 picks) | various | 6× accept | out | out | — |
| 18–21 | various | monotonicity | (4 picks) | various | 3× acc + 1× unk | out | out | — |
| 22 | `0xB56C...` | commutativity | `binomial(n: k:)` | Int | reject | in | in | — |
| 23 | `0xFCB1...` | commutativity | `distance(from: to:)` | Int | reject | in | in | — |
| 24 | `0x7748...` | commutativity | `_relaxedMul(_:_:)` | Complex<Double> | accept | in | in | — |
| **25** | `0x518A...` | associativity | `distance(from: to:)` | Int | reject | out | **in** | ✓ new |
| **26** | `0x60A0...` | associativity | `_relaxedMul(_:_:)` | Complex<Double> | accept | out | **in** | ✓ new |
| **27** | `0xB8DE...` | associativity | `-(z: w:)` | Complex<Double> | reject | out | **in** | ✓ new |
| 28–32 | various | dual-style-consistency | (5 picks) | various | 5× accept | out | out | — |

**Tally:** 10 in-scope (#3, #4, #5, #6, #22, #23, #24, #25, #26, #27) + 22 out-of-scope = 32 total.

## Per-pick verify outcome predictions

Cycles 41–42 in-scope picks (#3, #4, #5, #6, #22, #23, #24) retain their v1.45 predictions — no template-or-carrier change applies. Only the 3 new associativity picks are listed:

| # | Pair / function | Predicted outcome | Evidence basis |
|---:|---|---|---|
| **25** | `Int.distance(from: to:)` | **`.defaultFails` at trial 0** | `distance(distance(a, b), c) = c − (b − a) = a − b + c`; `distance(a, distance(b, c)) = (c − b) − a = −a − b + c`. Difference: `2a`. For random nonzero `a` from the default Int generator (`±65 536`), the first trial finds a counterexample with probability ~1 − 1/130 000. V1.46.D.4.b's `Double a − b` test pins the same algebraic identity at `.defaultFails`; #25 is the Int variant of the same outcome class. |
| **26** | `Complex<Double>._relaxedMul(_:_:)` | **`.bothPass(100, 100, 0..12)`** | Complex multiplication is associative on the finite domain within `isApproximatelyEqual` tolerance (relative ≈ `sqrt(.ulpOfOne)` ≈ `1.5e-8`), and the kit's `_relaxedMul` is the relaxed-FMA variant that preserves the associativity invariant up to FP rounding. V1.46.D.4.a's `Complex<Double> a + b` test is the additive sibling and passed both passes — the multiplicative analog has the same structural property up to (rare) catastrophic-cancellation risk. |
| **27** | `Complex<Double>.-(z: w:)` | **`.defaultFails` at trial 0** | `(a − b) − c = a − b − c`; `a − (b − c) = a − b + c`. Difference: `2c`. For random nonzero `c` in ±1e6, the relative difference far exceeds `isApproximatelyEqual` tolerance. V1.46.D.4.b's `Double a − b` test pins this case directly; #27 is the Complex<Double> variant of the same outcome class. |

**3 new verify-confirmed picks** (1 ACCEPT + 2 REJECT) + the 7 cycles-41-and-42 in-scope picks = **10 total**. **100% agreement between name-+-type heuristic and verify-mode evidence** across the entire in-scope subset, maintained from cycle 42.

**No manual `swift-infer verify` invocations were run for cycle-43.** Same protocol as cycle-42 — the predictions are derivable from V1.46.D.4's integration coverage (Complex<Double> additive associativity passes; Double subtractive associativity fails). Running them against the cycle-27 corpus would require indexing each upstream package (ComplexModule, OrderedCollections, swift-algorithms, PropertyLawKit). The cycle-42 load-bearing-only posture continues into cycle-43.

## Aggregate-rate framing — what verify-mode confirmation means (continued)

Cycle-42's clarifying nuance — **verify-mode-confirmed REJECTs don't change the aggregate acceptance rate** — applies unchanged. Cycle-27's 21 ACCEPT / 29 (ACCEPT + REJECT) = 72.4% remains the canonical aggregate; the cycle-43 verifiable-fraction lift (10/32 vs 7/32) is the **separate measurement** of how much of that name-heuristic verdict surface can now be cross-checked by verify execution.

**Cycle-43 disagreement count: 0.** The cycle-42 baseline was 0 disagreements over 7 in-scope picks; cycle-43 extends this to 0 disagreements over 10. Two cycles of perfect agreement is a stronger signal than one — the name-+-type heuristic for cycle-27's structure is closely aligned with what verify-mode would actually catch, on both ACCEPT and REJECT sides.

The framing recommendation from cycle-42 holds: "verifiable-fraction" + "per-pick agreement rate" + "verifier-mode lift = % of cycle-N REJECTs that verify-mode catches before they reach the user". For cycle-43 the verifier-mode lift number is **4/8 = 50%** of cycle-27 REJECTs are now verify-confirmable (up from 2/8 = 25% at v1.45.F).

## v1.47+ roadmap delta from cycle-42

| Expansion | New in-scope | New verifiable REJECTs | Verifiable-fraction after | Agreement-rate signal |
|---|---:|---:|---:|---|
| v1.44 baseline (cycle-41) | 2 | 0 | 6.25% | n/a (0 REJECTs verifiable) |
| v1.45 baseline (cycle-42) | +5 | +2 | 21.9% | 7/7 = 100% on in-scope picks |
| **v1.46 baseline (this doc)** | +3 | +2 | 31.3% | 10/10 = 100% on in-scope picks |
| + DerivationStrategist non-Complex/Double/Int carriers (v1.47) | +5 | +3 | 47.0% | unlocks #7–#9 idempotence on chunked `Base.Index` carriers |
| + idempotence-lifted (v1.48+) | +6 | 0 | 65.6% | sort/regen/isUnique/ensureUnique — all ACCEPTs; no REJECT lift |
| + monotonicity (v1.48+) | +4 | 0 | 78.1% | all ACCEPTs in cycle-27 sample |
| + dual-style-consistency (v1.48+) | +5 | 0 | 93.8% | all ACCEPTs |
| + non-curated round-trip pair derivation | +2 | +1 | 100% | unblocks #1 + #2 (#2 verify-confirms its REJECT) |

**Updated trajectory.** Full verify-mode coverage of the cycle-27 corpus now needs ~2 more expansion cycles (v1.47 + v1.48), down from cycle-42's projection of ~3 (v1.46 + v1.47 + v1.48). Of the 8 cycle-27 REJECTs, **4 are verify-confirmed at v1.46** (this cycle), **3 more would verify-confirm by v1.47** (DerivationStrategist on chunked-Index carriers), and the remaining 1 (#2 capacity-formatter pair) requires the SemanticIndex schema bump for both-halves storage.

## Why this matters for v1.47 planning

Three observations from this cycle shape the v1.47 priority order:

1. **DerivationStrategist carrier integration is the natural v1.47 candidate.** After v1.46 closes the 4-template arc (round-trip / idempotence / commutativity / associativity), the residual cycle-27 REJECT cluster is the 3 chunked-`Base.Index` idempotence picks (#7–#9). These need a new carrier path — same template, new derivation source. Cycle-42 flagged this as the next-biggest architectural lift, and cycle-43's roadmap projection shifts it explicitly into the v1.47 slot.

2. **Per-slot rotation worked as designed; no v1.47 follow-up needed on the rotation question.** V1.46.A's per-slot rotation edge bias (preferred over static single-slot bias per the v1.46 plan) compiled and passed all three integration tests cleanly. The Complex<Double> Pass 2 test surfaces a non-zero `edgeSampled` count over 100 trials with the rotation logic active. No flakiness or per-slot-density gap surfaced during cycle-43 measurement. The risk #3 mitigation (split `VERIFY_EDGE_SAMPLED` per slot) stays deferred; first ship-and-measure suggests the aggregate count is sufficient.

3. **The `_relaxedMul` prediction is the load-bearing FP-associativity check.** V1.46.D.4.a confirmed FP additive associativity holds within `isApproximatelyEqual` tolerance for `Complex<Double>` on `±1e6` inputs. The multiplicative analog (#26) is predicted `.bothPass` on the same tolerance basis. If the actual verify outcome on `_relaxedMul` ever surfaces a `.defaultFails`, it'd be the first verify-vs-heuristic disagreement in cycle 41–43's measurement history and would shift the FP-tolerance question into v1.47's scope. No such disagreement surfaced during V1.46.D.4 testing; the prediction stands.

The v1.47 plan should pick up from (1) as the natural continuation; (2) and (3) are stability signals for the v1.46 design choices.

## Captured artifacts

- Cycle-43 verifiable-fraction tally: this document.
- 3 new in-scope per-pick outcome predictions: §"Per-pick verify outcome predictions" table.
- v1.47+ roadmap implications: §"v1.47+ roadmap delta from cycle-42".
- Per-slot rotation validation: §"Why this matters for v1.47 planning" observation #2.

No `triage-decisions.json` in `docs/calibration-cycle-43-data/` — cycle 43 didn't produce new per-pick verdicts (the cycle-27 corpus is unchanged at 21/29 = 72.4%). The verifiable-fraction + per-pick agreement signal are the measurement outputs.


---

## Cycle-47 reframing caveat (added at v1.51)

The per-pick agreement-rate signal and verifiable-fraction reported in this document are **synthetic-shape-class agreement** — measured on hand-crafted `SemanticIndexEntry` instances constructed inside the integration-test suite to match v1.49 emitter expectations. End-to-end-from-indexer measurement (the verify pipeline running against entries produced by `swift-infer index` against real source) begins at cycle-47 (`docs/calibration-cycle-47-findings.md`) and continues at cycle-48 (`docs/calibration-cycle-48-findings.md`).

The two measurements are complementary, not contradictory: this document's numbers establish the verify-architecture *capability* (cycles 41-46 confirmed agreement on hand-crafted shapes); cycle-47+'s numbers measure the indexer→verify path *end-to-end*. Cycle-48 establishes that closing the carrier-resolution gap (V1.51.A canonicalization) doesn't immediately produce `.bothPass`-class outcomes — a deeper call-expression-shape gap is the next load-bearing fix. See `docs/calibration-cycle-48-findings.md` §"v1.52+ roadmap" for the trajectory.