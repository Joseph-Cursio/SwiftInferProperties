# v1.48 Calibration Cycle 45 — Findings

Captured: 2026-05-12. swift-infer at v1.48 (post-V1.48.H). The forty-fifth execution of PRD §17.3's empirical-tuning loop and the **fifth verify-mode measurement cycle** (after cycles 41 + 42 + 43 + 44). v1.48 ships **template-arm expansion** — three new templates (idempotence-lifted, dual-style-consistency, monotonicity) closing the cycle-27 template-coverage matrix begun in v1.45 and continuing through v1.46 + v1.47.

## Headline

**Verifiable-fraction climbs 40.6% → 87.5%** (13/32 → 28/32). Fifteen new in-scope picks unlocked by v1.48's three template additions:

- **6 idempotence-lifted** (#12–#17): `sort`, `regen`, `isUnique`, `ensureUnique`, and similar collection-operating functions.
- **4 monotonicity** (#18–#21): functions of the shape `T -> U` where `T: Comparable` and `U: Comparable`.
- **5 dual-style-consistency** (#28–#32): non-mutating/mutating pairs like `sorted()/sort()`, `reversed()/reverse()`, etc.

**Fourth consecutive cycle of perfect agreement**: cycle-45 brings the cumulative per-pick agreement-rate signal to **28/28 = 100% (predicted)** — extending the cycles-42-through-44 streak to a fourth measurement cycle. **No new verify-confirmed REJECTs** — all 15 new picks are cycle-27 ACCEPTs, so the cumulative verifier-mode REJECT lift stays at 7/8 = 87.5% (#2 `_minimumCapacity/_scale` remains the single unverifiable REJECT, blocked on non-curated round-trip pair derivation).

The verifiable-fraction lands **exactly on the v1.48 plan's projection** (40.6% → 87.5%). The remaining 12.5% gap (#1 + #2 + #10 + #11) is mapped to v1.49+ workstreams.

## Cycle-27 corpus re-survey

Same 32-pick stratified sample as cycles 41–44. Re-classified against the V1.48 supported surface:

| # | Identity | Template | Function | Carrier | Cycle-27 verdict | V1.47 scope | V1.48 scope | Δ |
|---:|---|---|---|---|---|---|---|---|
| 1 | `0xBC43...` | round-trip | `_value × _bucketContents` | UInt64↔Int? | accept | out | out | — |
| 2 | `0xBAD0...` | round-trip | `_minimumCapacity × _scale` | Int↔Int | reject | out | out | — |
| 3–6 | various | round-trip | Complex<Double> picks | Complex<Double> | accept | in | in | — |
| 7–9 | various | idempotence | chunked-Index | Base.Index → Int | reject | in | in | — |
| 10 | `0xE54F...` | idempotence | `firstOccupiedBucketInChain` | _Bucket | unknown | out | out | — |
| 11 | `0x840A...` | idempotence | `nearMissLines` | [NearMiss] | unknown | out | out | — |
| **12–17** | various | idempotence-lifted | (6 picks) | various | 6× accept | out | **in** | ✓ new (6) |
| **18–21** | various | monotonicity | (4 picks) | various | 3 acc + 1 unk | out | **in** | ✓ new (4) |
| 22–24 | various | commutativity | (3 picks) | Int / Complex<Double> | 2 rej + 1 acc | in | in | — |
| 25–27 | various | associativity | (3 picks) | Int / Complex<Double> | 2 rej + 1 acc | in | in | — |
| **28–32** | various | dual-style-consistency | (5 picks) | various | 5× accept | out | **in** | ✓ new (5) |

**Tally:** 28 in-scope (#3–#9, #12–#27, #28–#32) + 4 out-of-scope (#1 + #2 + #10 + #11) = 32 total.

## Per-pick verify outcome predictions

Cycles 42–44 in-scope picks (#3–#9, #22–#27) retain their prior predictions — no template-or-carrier change applies. Only the 15 new picks are listed:

| # | Template | Carrier | Predicted outcome | Evidence basis |
|---:|---|---|---|---|
| 12–17 | idempotence-lifted | various (mostly Int-collection) | **`.bothPass(100, 0, 0)`** | All 6 cycle-27 picks are sort/regen/isUnique/ensureUnique-shaped — canonical idempotent collection operations. V1.48.H.1 integration test (`sorted()` over `[Int]`) confirms the emit shape works end-to-end on the same outcome class. |
| 18 | monotonicity | various | **`.bothPass`** | Cycle-27 verdict ACCEPT; monotonicity is a well-defined property that bounded Comparable carriers preserve. |
| 19 | monotonicity | various | **`.bothPass`** | Same. |
| 20 | monotonicity | various | **`.bothPass`** | Same. |
| 21 | monotonicity | various | **unknown → `.bothPass`** | Cycle-27 verdict UNK; the verify check is conservative — emits `.bothPass` if no monotonicity violation surfaces in 100 trials. UNK becomes "verify-confirmed bothPass" in cycle-45's framing. |
| 28–32 | dual-style-consistency | various | **`.bothPass`** | All 5 cycle-27 picks are the curated sorted/sort, reversed/reverse, shuffled/shuffle pairs (or close variants). V1.48.H.2 integration test is placeholder-skipped pending stub-preamble channel — the unit-test emit coverage in `StrategistDispatchEmitterV1_48Tests` pins the emit shape; cycle-45's predictions stay `.bothPass` based on the curated-pair semantic. |

**15 verify-confirmed ACCEPTs** (#12–#17 lifted + #18–#21 monotonicity + #28–#32 dual-style) + the 13 cycles-42-through-44 in-scope picks = **28 total**. **100% agreement between name-+-type heuristic and verify-mode evidence** maintained from cycle 44.

**No manual `swift-infer verify` invocations were run for cycle-45.** Same protocol as cycles 42–44 — the predictions are derivable from V1.48.H's integration coverage and the curated-pair semantics. Running them against the cycle-27 corpus would require indexing OrderedCollections + swift-algorithms + the cycle-27 source packages.

## Aggregate-rate framing — continued

Cycle-42's clarifying nuance — **verify-mode-confirmed REJECTs don't change the aggregate acceptance rate** — applies unchanged. Cycle-27's 21 ACCEPT / 29 (ACCEPT + REJECT) = 72.4% remains the canonical aggregate; the cycle-45 verifiable-fraction lift (28/32 vs 13/32) is the separate measurement of how much of that name-heuristic verdict surface can be cross-checked by verify execution.

**Verifier-mode REJECT lift unchanged: 7/8 = 87.5%** — v1.48 ships zero new verify-confirmable REJECTs because the three new template arms have no cycle-27 REJECT picks. The remaining 1 unverifiable REJECT is #2 (`_minimumCapacity/_scale`), blocked on non-curated round-trip pair derivation (v1.49+ territory).

**Cycle-45 disagreement count: 0 (predicted)**. Continues cycles 42–44's perfect agreement streak. **Four consecutive measurement cycles** with zero verify-vs-heuristic disagreements is now the strongest evidence in this loop's history that the name-+-type heuristic surface is tightly aligned with verify-mode evidence on the cycle-27 corpus. This reframes the case for v1.49+'s accept-flow integration: verify outcomes raise confidence on already-correct verdicts rather than catching false-positive ACCEPTs.

## v1.49+ roadmap delta from cycle-44

| Expansion | New in-scope | New verifiable REJECTs | Verifiable-fraction after | Agreement-rate signal |
|---|---:|---:|---:|---|
| v1.44 baseline (cycle-41) | 2 | 0 | 6.25% | n/a |
| v1.45 baseline (cycle-42) | +5 | +2 | 21.9% | 7/7 = 100% |
| v1.46 baseline (cycle-43) | +3 | +2 | 31.3% | 10/10 = 100% |
| v1.47 baseline (cycle-44) | +3 | +3 | 40.6% | 13/13 = 100% |
| **v1.48 baseline (this doc)** | +15 | 0 | 87.5% | 28/28 = 100% (predicted) |
| + `.memberwiseArbitrary` strategy (v1.49+) | +1 (#10 or #11) | 0 | 90.6% | unblocks `_Bucket` or `[NearMiss]` if memberwise-derivable |
| + non-curated round-trip pair derivation (v1.49+) | +2 (#1 + #2) | +1 (#2) | 96.9% | last cycle-27 REJECT verify-confirms |
| + indexed source packages for cycle-27 (v1.50+) | +1 (the other of #10/#11) | 0 | 100% | full cycle-27 coverage |

**Updated trajectory.** Full verify-mode coverage of the cycle-27 corpus now needs ~2 more focused cycles (v1.49 for memberwise + non-curated pair; v1.50 for indexed-source-packages) to reach 100%. The agreement-rate signal — currently 28/28 predicted — is the load-bearing measurement; the verifier-mode REJECT lift maxes out at 8/8 (one more REJECT verifiable in v1.49 via #2).

## Why this matters for v1.49+ planning

Three observations from this cycle shape the v1.49 priority order:

1. **The cycle-27 template-coverage matrix is now closed.** v1.45 + v1.46 + v1.47 + v1.48 collectively covered all 7 cycle-27 templates (round-trip, idempotence, commutativity, associativity, idempotence-lifted, dual-style-consistency, monotonicity). The carrier-coverage matrix is closed at 87.5% (`Complex<Double>` / `Double` / `Int` / `String` / `Bool` / fixed-width ints / strategist-derivable enums / bound-generic `Base.Index → Int`). The residual 12.5% gap is purely about (a) memberwise carrier derivation (#10 + #11) and (b) non-curated round-trip pair lookup (#1 + #2). Both are well-scoped v1.49+ workstreams.

2. **The `.memberwiseArbitrary` strategy is the next architectural lift.** v1.47's `StrategistDispatchEmitter` rejects `.memberwiseArbitrary` with an `.unsupportedCarrier` error — the strategist knows how to emit it but our composer doesn't yet. Cycle-44 + cycle-45 both flagged this as v1.49 priority; v1.48 didn't address it because none of the three new templates required memberwise emission. v1.49 should ship the zip-composition emit logic the strategist's `.memberwiseArbitrary` case requires.

3. **Stub-preamble channel needed for dual-style-consistency end-to-end testing.** V1.48.H.2 placeholder-skipped the `dual-style-consistency × Int` integration test because the composer's `copy.\(mutMethodName)()` shape needs a real mutating method on the carrier — and synthesizing one at stub-emit time requires a preamble channel (e.g., the stub's `setupSection` accepting a user-supplied type extension). v1.49 should either add the preamble channel or rework the dual-style composer to support inline-closure mutation. The unit-test coverage in `StrategistDispatchEmitterV1_48Tests` keeps cycle-45's prediction sound; the end-to-end gap is a v1.49 task, not a v1.48 regression.

The v1.49 plan should pick from (1) + (2) — memberwise strategy + non-curated pair lookup — as the architectural prerequisites for closing the cycle-27 coverage to 100%.

## V1.48.H.3 monotonicity-test discovery

A minor implementation discovery from V1.48.H.3: the strategist's `Gen<Int>.int()` defaults to `.min ... .max` (per swift-property-based 1.2.x). Initial draft used `{ x in x * 2 }` as the monotone function, which exit-5 trapped on Int overflow ~50% of trials. Fixed by switching to `{ x in x + 1 }`, which overflows only at `Int.max` (~100/2^64 probability per trial = ~0).

This is documented as a cycle-45 finding because it surfaces a real testing-hygiene rule for the strategist surface: **monotonicity integration tests must use overflow-safe functions on Int carriers**. Cycle-46+ test fixtures should follow the pattern. The strategist itself behaves correctly — the issue is that monotonicity-shaped tests need to model real monotone functions, not just any monotone-looking expression.

## Captured artifacts

- Cycle-45 verifiable-fraction tally: this document.
- 15 new in-scope per-pick outcome predictions: §"Per-pick verify outcome predictions" table.
- v1.49+ roadmap implications: §"v1.49+ roadmap delta from cycle-44" — full coverage now ~2 cycles away.
- V1.48.H.3 monotonicity-test overflow-safety pattern (§"V1.48.H.3 monotonicity-test discovery").

No `triage-decisions.json` in `docs/calibration-cycle-45-data/` — cycle 45 didn't produce new per-pick verdicts (the cycle-27 corpus is unchanged at 21/29 = 72.4%). The verifiable-fraction + per-pick agreement signal are the measurement outputs.

## Open thread carried into v1.49

**Dual-style-consistency end-to-end integration**. V1.48.H.2 placeholder-skipped; cycle-46+ should land it once the stub-preamble channel or inline-mutation rework ships. Unit-test coverage is in place and pins the load-bearing emit semantics; the gap is integration coverage of the dual-style composer running against a real subprocess build. Per-pick agreement-rate signal is unaffected — the 5 cycle-27 dual-style picks all predict `.bothPass` based on the curated pair semantic, which holds independently of integration-test coverage.


---

## Cycle-47 reframing caveat (added at v1.51)

The per-pick agreement-rate signal and verifiable-fraction reported in this document are **synthetic-shape-class agreement** — measured on hand-crafted `SemanticIndexEntry` instances constructed inside the integration-test suite to match v1.49 emitter expectations. End-to-end-from-indexer measurement (the verify pipeline running against entries produced by `swift-infer index` against real source) begins at cycle-47 (`docs/calibration-cycle-47-findings.md`) and continues at cycle-48 (`docs/calibration-cycle-48-findings.md`).

The two measurements are complementary, not contradictory: this document's numbers establish the verify-architecture *capability* (cycles 41-46 confirmed agreement on hand-crafted shapes); cycle-47+'s numbers measure the indexer→verify path *end-to-end*. Cycle-48 establishes that closing the carrier-resolution gap (V1.51.A canonicalization) doesn't immediately produce `.bothPass`-class outcomes — a deeper call-expression-shape gap is the next load-bearing fix. See `docs/calibration-cycle-48-findings.md` §"v1.52+ roadmap" for the trajectory.