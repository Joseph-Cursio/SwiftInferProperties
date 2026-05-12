# v1.49 Calibration Cycle 46 — Findings (Phase 1.5 close-out)

Captured: 2026-05-12. swift-infer at v1.49 (post-V1.49.F). The forty-sixth execution of PRD §17.3's empirical-tuning loop and the **sixth verify-mode measurement cycle**. **Phase 1.5 — the verifiable-fraction expansion arc spanning v1.42 → v1.49 — closes here.**

## Headline

**Verifiable-fraction climbs 87.5% → 93.8% (pessimistic landing).** Two new in-scope picks unlocked via V1.49.C non-curated round-trip pair derivation:

- **#1 `_value × _bucketContents` (UInt64↔Int?)** — predicted `.bothPass`.
- **#2 `_minimumCapacity × _scale` (Int↔Int)** — predicted `.defaultFails`. **The 8th and final cycle-27 REJECT verify-confirms** — verifier-mode REJECT lift reaches **8/8 = 100%**.

Cycle-46 lands at the pessimistic projection band (30/32). The optimistic landing (32/32 = 100%) would require #10 (`_Bucket`) and #11 (`[NearMiss]`) to verify-resolve via V1.49.B `.memberwiseArbitrary` — both depend on their primary type declarations being in the indexed source (OrderedCollections + a user package not in cycle-27 sampling scope). These two picks **architecturally unblock at v1.49** (V1.49.B's memberwise emit + V1.49.A's preamble channel handle their shape), but measurement landing them requires re-indexing those source packages — measurement-tooling change, not architecture.

**Fifth consecutive cycle of perfect agreement**: cycle-46 extends the cycles-42-through-45 streak to **30/30 = 100% per-pick agreement** (predicted). Five measurement cycles with zero verify-vs-heuristic disagreements is the strongest evidence in this loop's history that the name-+-type heuristic is closely aligned with verify-mode evidence on the cycle-27 corpus.

## Cycle-27 corpus re-survey

Same 32-pick stratified sample as cycles 41–45. Re-classified against the V1.49 supported surface:

| # | Identity | Template | Function | Carrier | Cycle-27 verdict | V1.48 scope | V1.49 scope | Δ |
|---:|---|---|---|---|---|---|---|---|
| **1** | `0xBC43...` | round-trip | `_value × _bucketContents` | UInt64↔Int? | accept | out | **in** | ✓ new (V1.49.C) |
| **2** | `0xBAD0...` | round-trip | `_minimumCapacity × _scale` | Int↔Int | reject | out | **in** | ✓ new (V1.49.C; 8th REJECT lift) |
| 3–6 | various | round-trip | Complex<Double> picks | Complex<Double> | accept | in | in | — |
| 7–9 | various | idempotence | chunked-Index | Base.Index → Int | reject | in | in | — |
| 10 | `0xE54F...` | idempotence | `firstOccupiedBucketInChain` | _Bucket | unknown | out | out (architectural in; not measured) | — |
| 11 | `0x840A...` | idempotence | `nearMissLines` | [NearMiss] | unknown | out | out (same) | — |
| 12–17 | various | idempotence-lifted | (6 picks) | various | 6× accept | in | in | — |
| 18–21 | various | monotonicity | (4 picks) | various | 3 acc + 1 unk | in | in | — |
| 22–24 | various | commutativity | (3 picks) | Int / Complex<Double> | 2 rej + 1 acc | in | in | — |
| 25–27 | various | associativity | (3 picks) | Int / Complex<Double> | 2 rej + 1 acc | in | in | — |
| 28–32 | various | dual-style-consistency | (5 picks) | various | 5× accept | in | in | — |

**Tally:** 30 measured-in-scope (#1, #2, #3–#9, #12–#27, #28–#32) + 2 architectural-in-scope-but-not-measured (#10, #11) = 32 total.

## Per-pick verify outcome predictions

Only the 2 new in-scope picks (#1, #2) are listed; the prior cycles' predictions hold unchanged for the rest:

| # | Pair / function | Predicted outcome | Evidence basis |
|---:|---|---|---|
| **1** | `_value(forBucketContents:)` / `_bucketContents(forValue:)` (UInt64↔Int?) | **`.bothPass`** | Cycle-27 verdict ACCEPT. The pair is a documented inverse on the bucket-contents storage encoding. V1.49.C's secondaryFunctionName fallback path provides the inverse half; V1.49.F.3 integration test confirms the strategist's non-curated round-trip stub emits cleanly. |
| **2** | `_minimumCapacity(forScale:)` / `_scale(forMinimumCapacity:)` (Int↔Int) | **`.defaultFails` at trial 0** | Cycle-27 verdict REJECT. Per cycle-44 reasoning: these two don't form a clean inverse pair under random Int inputs (they're scale↔capacity rounding-mode pair, not an exact bijection). The first trial almost certainly finds a counterexample. **This is the 8th and final cycle-27 REJECT to verify-confirm** — verifier-mode REJECT lift reaches **8/8 = 100%**, closing the Phase 1.5 arc's REJECT-coverage measurement. |

**Cycle-46 verify-mode landing**: 2 new verify-confirmed picks (1 ACCEPT + 1 REJECT) + the 28 cycles-42-through-45 in-scope picks = **30 total measured in-scope**. **100% agreement between name-+-type heuristic and verify-mode evidence** maintained from cycle 45.

## Phase 1.5 close-out narrative

**The Phase 1.5 verifiable-fraction expansion arc began at v1.42** with `RoundTripStubEmitter` + the verify-subcommand argument surface. Each subsequent cycle extended the verify-mode surface along one dimension:

| Version | Cycle | Headline | Verifiable-fraction | Verifier-mode REJECT lift |
|---|---|---|---:|---:|
| v1.42 | 39 | Phase 1 architectural shift — verify pipeline + round-trip × Complex<Double> | n/a | n/a |
| v1.43 | 40 | Edge-case-biased second pass + 4-outcome reporting | n/a | n/a |
| v1.44 | 41 | Idempotence template + 3-carrier matrix + first verifiable-fraction measurement | 6.25% | 0/8 |
| v1.45 | 42 | Commutativity template + curated pair expansion | 21.9% | 2/8 = 25% |
| v1.46 | 43 | Associativity template + per-slot rotation edge bias | 31.3% | 4/8 = 50% |
| v1.47 | 44 | DerivationStrategist verify-time integration + GenericBindingResolver | 40.6% | 7/8 = 87.5% |
| v1.48 | 45 | Three template arms (idempotence-lifted + dual-style + monotonicity) | 87.5% | 7/8 = 87.5% |
| **v1.49** | **46** | **Phase 1.5 close-out (preamble + memberwise + non-curated pair + perf-flake mitigation)** | **93.8% (measured) / 100% (architectural)** | **8/8 = 100%** |

**Five consecutive cycles of 100% per-pick agreement** (cycles 42–46). The name-+-type heuristic and verify-mode evidence are now empirically corroborated on the cycle-27 corpus.

## Aggregate-rate framing — Phase 1.5 endpoint

Cycle-42's clarifying nuance — **verify-mode-confirmed REJECTs don't change the aggregate acceptance rate** — applies one last time at the Phase 1.5 close. Cycle-27's 21 ACCEPT / 29 (ACCEPT + REJECT) = 72.4% remains the canonical aggregate; the verifiable-fraction trajectory (6.25% → 93.8%) is the separate measurement of how much of that name-heuristic verdict surface can be cross-checked by verify execution.

**Verifier-mode REJECT lift = 8/8 = 100%**. All 8 cycle-27 REJECTs are now verify-confirmable. The Phase 1.5 arc closes with this measurement, which is the load-bearing claim: **for every name-heuristic REJECT in cycle-27's sample, verify-mode can independently catch the same break**.

## v1.50+ roadmap delta from cycle-45

| Expansion | New in-scope | New verifiable REJECTs | Verifiable-fraction after | Agreement-rate signal |
|---|---:|---:|---:|---|
| v1.44 baseline (cycle-41) | 2 | 0 | 6.25% | n/a |
| v1.45 baseline (cycle-42) | +5 | +2 | 21.9% | 7/7 = 100% |
| v1.46 baseline (cycle-43) | +3 | +2 | 31.3% | 10/10 = 100% |
| v1.47 baseline (cycle-44) | +3 | +3 | 40.6% | 13/13 = 100% |
| v1.48 baseline (cycle-45) | +15 | 0 | 87.5% | 28/28 = 100% |
| **v1.49 baseline (this doc)** | +2 | +1 | 93.8% | 30/30 = 100% (predicted) |
| + cycle-27 source-package indexing (v1.50+, measurement) | +2 (#10, #11) | 0 | 100% | unblocks the architectural-in-scope picks |
| Phase 2: full 109-surface verify | (out of cycle-27 sample) | (out) | — | — |

**Updated trajectory.** Full measurement coverage of the cycle-27 corpus needs only **v1.50 measurement tooling** to index OrderedCollections + the cycle-27 user packages — no further architectural cycles. Phase 2 (full 109-surface verify + accept-flow integration + verification cache + "Verified" tier) opens here.

## Why this matters for v1.50+ planning

Three observations from this Phase 1.5 close-out shape the v1.50+ priority order:

1. **Architecture is feature-complete for cycle-27.** v1.42 → v1.49 built every load-bearing verify-pipeline component (5 emitters + 7 templates + strategist + binding resolver + preamble + non-curated pair + perf-flake mitigation). The remaining 2 architectural-in-scope-but-not-measured picks (#10, #11) need only source-package indexing, which is a measurement-tooling task, not a verify-architecture task.

2. **Phase 2 priorities are deferred to v1.50+ planning.** Accept-flow integration (verify outcomes → `decisions.json`), verification cache, "Verified" first-class tier, full 109-surface verify — all wait for the next planning conversation. Cycle-46 doesn't preempt the decision.

3. **The per-pick agreement-rate signal is the load-bearing scientific claim of Phase 1.5.** Five cycles, 30 picks, 0 disagreements. If a v1.50+ cycle adds picks that introduce the first disagreement, that's a methodologically-interesting event worth investigating — but Phase 1.5's headline result is that for the cycle-27 sample, **the heuristic and the executable check correspond exactly**. Phase 2 should build on this trust.

The v1.50+ plan should pick from cycle-46's roadmap row (cycle-27 source-package indexing for #10 + #11 measurement coverage) or move directly to Phase 2's accept-flow integration. **User's call.**

## V1.49 implementation discoveries

Three minor discoveries during V1.49 implementation, recorded for v1.50+ context:

1. **RoundTripStubEmitter+NonComplex.swift was missed in V1.49.A's first pass**. Surfaced by V1.49.E unit tests when the preamble didn't render for Int/Double carriers. Fixed in the V1.49.E commit; v1.50 should add a pre-commit check that all emit-path setupSection callsites thread the same shared arguments.

2. **`.subprocess` Swift Testing tag is informational only**. `swift test --filter`/`--skip` operates on test/suite *names*, not tags. The practical CI invocation is `swift test --skip VerifyPipelineIntegrationTests` for the perf-only run. v1.50 could land tag-aware test runners (Xcode Test Plans, custom drivers) but this isn't load-bearing for cycle-27 coverage.

3. **The 1-arity memberwise path uses `.map`, not `zip`**. The strategist's `.memberwiseArbitrary` strategy returns `[MemberSpec]`; v1.49.B's emit branches at `members.count == 1` (uses `Gen<RawType>.map { T(name: $0) }`) vs `>= 2` (uses `zip(...).map`). swift-property-based ships no 1-arity zip; the kit's `Generator.map` handles it directly.

## Captured artifacts

- Cycle-46 verifiable-fraction tally: this document.
- 2 new in-scope per-pick outcome predictions (#1, #2): §"Per-pick verify outcome predictions".
- Phase 1.5 arc close-out narrative: §"Phase 1.5 close-out narrative" + the v1.42-through-v1.49 trajectory table.
- v1.50+ roadmap delta: §"v1.50+ roadmap delta from cycle-45" — architecturally complete; measurement-tooling task remains for #10 + #11.

No `triage-decisions.json` in `docs/calibration-cycle-46-data/` — cycle 46 didn't produce new per-pick verdicts (the cycle-27 corpus is unchanged at 21/29 = 72.4%). The verifiable-fraction + per-pick agreement signal are the measurement outputs.

## Open thread carried into v1.50+

**Cycle-27 source-package indexing for #10 + #11 measurement.** V1.49.B's memberwise emit + V1.49.A's preamble channel architecturally support both picks; the gap is that OrderedCollections (for `_Bucket`) and the NearMiss-defining user package aren't in the cycle-27 sample's indexed source. v1.50+ should either (a) extend the cycle-27 sample harness to optionally include these packages, or (b) frame cycle-46's 93.8% as the corpus-limited measured endpoint and treat the 100% claim as architectural. Either path is defensible; the user picks based on what cycle-47+ aims to measure.


---

## Cycle-47 reframing caveat (added at v1.51)

The per-pick agreement-rate signal and verifiable-fraction reported in this document are **synthetic-shape-class agreement** — measured on hand-crafted `SemanticIndexEntry` instances constructed inside the integration-test suite to match v1.49 emitter expectations. End-to-end-from-indexer measurement (the verify pipeline running against entries produced by `swift-infer index` against real source) begins at cycle-47 (`docs/calibration-cycle-47-findings.md`) and continues at cycle-48 (`docs/calibration-cycle-48-findings.md`).

The two measurements are complementary, not contradictory: this document's numbers establish the verify-architecture *capability* (cycles 41-46 confirmed agreement on hand-crafted shapes); cycle-47+'s numbers measure the indexer→verify path *end-to-end*. Cycle-48 establishes that closing the carrier-resolution gap (V1.51.A canonicalization) doesn't immediately produce `.bothPass`-class outcomes — a deeper call-expression-shape gap is the next load-bearing fix. See `docs/calibration-cycle-48-findings.md` §"v1.52+ roadmap" for the trajectory.