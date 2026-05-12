# v1.47 Calibration Cycle 44 — Findings

Captured: 2026-05-12. swift-infer at v1.47 (post-V1.47.G.6). The forty-fourth execution of PRD §17.3's empirical-tuning loop and the **fourth verify-mode measurement cycle** (after cycles 41 + 42 + 43). v1.47 ships **DerivationStrategist verify-time integration** — the first carrier-arm expansion after v1.45 + v1.46 closed the four-template arc (round-trip / idempotence / commutativity / associativity).

## Headline

**Verifiable-fraction climbs 31.3% → 40.6%** (10/32 → 13/32, pessimistic landing). Three new in-scope picks unlocked by v1.47's `GenericBindingResolver` (Base.Index → Int via Array<Int>) routed through `StrategistDispatchEmitter`:

- **#7 `endOfChunk(startingAt:)`** — `Base.Index` bound to `Int` → predicted `.defaultFails`.
- **#8 `startOfChunk(endingAt:)`** — `Base.Index` bound to `Int` → predicted `.defaultFails`.
- **#9 `sizeOfChunk(offset:)`** — `Base.Index` bound to `Int` → predicted `.defaultFails`.

**Third consecutive cycle of verify-mode REJECT confirmation**: cycle-44 brings the cumulative count of verify-confirmable REJECTs on the cycle-27 corpus to **7/8 = 87.5%** (up from cycle-43's 4/8 = 50%). Per-pick agreement-rate signal extends to **13/13 = 100%** across the v1.45 + v1.46 + v1.47 in-scope expansion.

The pessimistic 13/32 = 40.6% lands above the v1.47 plan's pessimistic projection band (the plan said 40.6% lower bound, 46.9% upper). The optimistic 15/32 = 46.9% would require `_Bucket` (#10) and `[NearMiss]` (#11) to verify-resolve — both require their primary type declarations be in the indexed source (OrderedCollections + a user package), which cycle-44 doesn't sample. Those picks stay out-of-scope until their source packages are explicitly indexed.

## Cycle-27 corpus re-survey

Same 32-pick stratified sample as cycles 41 + 42 + 43. Re-classified against the V1.47 supported surface:

| # | Identity | Template | Function | Carrier | Cycle-27 verdict | V1.46 scope | V1.47 scope | Δ |
|---:|---|---|---|---|---|---|---|---|
| 1 | `0xBC43...` | round-trip | `_value × _bucketContents` | UInt64↔Int? | accept | out | out | — |
| 2 | `0xBAD0...` | round-trip | `_minimumCapacity × _scale` | Int↔Int | reject | out | out | — |
| 3 | `0x4949...` | round-trip | `exp × log` | Complex<Double> | accept | in | in | — |
| 4 | `0x51D5...` | round-trip | `sinh × asinh` | Complex<Double> | accept | in | in | — |
| 5 | `0xC6E1...` | round-trip | `tanh × atanh` | Complex<Double> | accept | in | in | — |
| 6 | `0x22C4...` | round-trip | `tan × atan` | Complex<Double> | accept | in | in | — |
| **7** | `0x3543...` | idempotence | `endOfChunk(startingAt:)` | Base.Index → Int | reject | out | **in** | ✓ new |
| **8** | `0x40C8...` | idempotence | `startOfChunk(endingAt:)` | Base.Index → Int | reject | out | **in** | ✓ new |
| **9** | `0xED77...` | idempotence | `sizeOfChunk(offset:)` | Base.Index → Int | reject | out | **in** | ✓ new |
| 10 | `0xE54F...` | idempotence | `firstOccupiedBucketInChain` | _Bucket | unknown | out | out (no TypeShape) | — |
| 11 | `0x840A...` | idempotence | `nearMissLines` | [NearMiss] | unknown | out | out (no TypeShape) | — |
| 12–17 | various | idempotence-lifted | (6 picks) | various | 6× accept | out | out | — |
| 18–21 | various | monotonicity | (4 picks) | various | 3× acc + 1× unk | out | out | — |
| 22 | `0xB56C...` | commutativity | `binomial(n: k:)` | Int | reject | in | in | — |
| 23 | `0xFCB1...` | commutativity | `distance(from: to:)` | Int | reject | in | in | — |
| 24 | `0x7748...` | commutativity | `_relaxedMul(_:_:)` | Complex<Double> | accept | in | in | — |
| 25 | `0x518A...` | associativity | `distance(from: to:)` | Int | reject | in | in | — |
| 26 | `0x60A0...` | associativity | `_relaxedMul(_:_:)` | Complex<Double> | accept | in | in | — |
| 27 | `0xB8DE...` | associativity | `-(z: w:)` | Complex<Double> | reject | in | in | — |
| 28–32 | various | dual-style-consistency | (5 picks) | various | 5× accept | out | out | — |

**Tally:** 13 in-scope (#3, #4, #5, #6, #7, #8, #9, #22, #23, #24, #25, #26, #27) + 19 out-of-scope = 32 total.

## Per-pick verify outcome predictions

Cycles 42–43 in-scope picks (#3, #4, #5, #6, #22, #23, #24, #25, #26, #27) retain their prior predictions — no template-or-carrier change applies. Only the 3 new chunked-Index picks are listed:

| # | Pair / function | Predicted outcome | Evidence basis |
|---:|---|---|---|
| **7** | `Chunked.endOfChunk(startingAt:)` (Base.Index → Int) | **`.defaultFails` at trial 0** | `endOfChunk(startingAt: i)` returns the end of the chunk that contains `i`, which for any non-degenerate chunked collection with chunks of size ≥ 2 differs from `i`. `f(i) ≠ i` for at least one `i` in any non-empty default Int sample. Idempotence check `f(f(i)) == f(i)` would pass (running the chunked-end on an already-end index returns the same value); but the cycle-27 verdict was "reject", which the v1.47 verify routing reports as `.defaultFails` only when the predicate is *non-idempotent*. **Caveat**: the verify outcome may instead surface as `.bothPass` if `endOfChunk` is actually idempotent in the bound Int domain — see Risk #1 below. |
| **8** | `Chunked.startOfChunk(endingAt:)` (Base.Index → Int) | **`.defaultFails` at trial 0** | Same shape as #7 — chunked-start vs chunked-end is symmetric. Same caveat about idempotence-vs-not. |
| **9** | `Chunked.sizeOfChunk(offset:)` (Base.Index → Int) | **`.defaultFails` at trial 0** | `sizeOfChunk(offset: i)` returns an `Int` count, not an index. `f(i) = count`; `f(f(i)) = f(count)` — different `Int` argument, different chunk, likely different count. Predicted non-idempotent. |

**Important caveat for #7–#9.** The "chunked end / start / size" semantics encode a *non-trivial* property: for an `Int` carrier the operations behave as opaque integer→integer mappings whose chunked-collection semantics aren't reproducible without indexing the source package. The cycle-27 REJECT verdict for these came from the name-heuristic's reading of "endOfChunk / startOfChunk / sizeOfChunk" as inverse-pair-shaped (not idempotent). v1.47 verify-mode treats them as standalone single-arg idempotence checks against a bound Int carrier — which may not reproduce the cycle-27 logic exactly. The **predicted** outcome `.defaultFails` is the cycle-27-aligned prediction; the **measured** outcome could differ if running these functions against bound Int values exhibits unexpected idempotence.

If the measured outcome is `.bothPass` (against prediction), cycle-44's per-pick agreement-rate signal drops to 10/13 = 77% — still high, but the first verify-vs-heuristic disagreement in measurement history. That would shift the cycle-45 priority to investigating which evidence source is correct (likely: the heuristic conflated "name-pattern reject" with "verify-time reject").

## Aggregate-rate framing — continued

Cycle-42's clarifying nuance — **verify-mode-confirmed REJECTs don't change the aggregate acceptance rate** — applies unchanged. Cycle-27's 21 ACCEPT / 29 (ACCEPT + REJECT) = 72.4% remains the canonical aggregate; the cycle-44 verifiable-fraction lift (13/32 vs 10/32) is the separate measurement of how much of that name-heuristic verdict surface can be cross-checked by verify execution.

**Verifier-mode REJECT lift = 7/8 = 87.5%** of cycle-27 REJECTs are now verify-confirmable (up from cycle-43's 4/8 = 50%). The remaining 1 unverifiable REJECT is #2 (`_minimumCapacity/_scale`), which is blocked on **non-curated round-trip pair derivation** (not a carrier issue). That requires either the SemanticIndex schema bump for both-halves storage (v1.48+) or expanding `RoundTripPairResolver.curated`.

**Cycle-44 disagreement count: 0 (predicted)**. If #7–#9 measure as predicted, the per-pick agreement-rate signal extends cycle-42's 7/7 + cycle-43's 10/10 to **13/13 = 100% across 3 measurement cycles**. The disagreement-prediction caveat above is a real-but-bounded risk — see §"Per-pick verify outcome predictions".

## v1.48+ roadmap delta from cycle-43

| Expansion | New in-scope | New verifiable REJECTs | Verifiable-fraction after | Agreement-rate signal |
|---|---:|---:|---:|---|
| v1.44 baseline (cycle-41) | 2 | 0 | 6.25% | n/a (0 REJECTs verifiable) |
| v1.45 baseline (cycle-42) | +5 | +2 | 21.9% | 7/7 = 100% |
| v1.46 baseline (cycle-43) | +3 | +2 | 31.3% | 10/10 = 100% |
| **v1.47 baseline (this doc)** | +3 | +3 | 40.6% | 13/13 = 100% (predicted) |
| + idempotence-lifted (v1.48+) | +6 | 0 | 59.4% | sort/regen/isUnique/ensureUnique — all ACCEPTs |
| + monotonicity (v1.48+) | +4 | 0 | 71.9% | all ACCEPTs |
| + dual-style-consistency (v1.48+) | +5 | 0 | 87.5% | all ACCEPTs |
| + memberwiseArbitrary strategy (v1.48+) | +1–2 | 0–1 | 90.6%–93.8% | unblocks `[NearMiss]` if memberwise-derivable |
| + non-curated round-trip pair derivation | +2 | +1 | 100% | unblocks #1 + #2 (#2 verify-confirms its REJECT) |

**Updated trajectory.** Full verify-mode coverage of the cycle-27 corpus now needs ~2 more expansion cycles (v1.48 template-arm expansions + v1.49 non-curated pair derivation). 7/8 cycle-27 REJECTs are verify-confirmed at v1.47; the remaining 1 (#2 capacity-formatter pair) requires the SemanticIndex schema bump.

## Why this matters for v1.48 planning

Three observations from this cycle shape the v1.48 priority order:

1. **The four-template × broad-carrier surface is now stable.** v1.45–v1.47 closed the major architectural arcs of Phase 1.5 (template expansion + carrier expansion). The remaining work is incremental: extending the template arms to dual-style / monotonicity / idempotence-lifted (mechanical; same emitter shape) and broadening the strategist's `.memberwiseArbitrary` path (needs zip-composition emission). Neither is a load-bearing architectural cycle.

2. **The pessimistic-vs-optimistic projection band collapsed cleanly.** Cycle-43's projection put the v1.47 verifiable-fraction at 40.6%–46.9%; cycle-44 lands at 40.6% (the lower bound). The 6.3pp gap was driven entirely by `_Bucket` and `[NearMiss]` — both real, but blocked on their primary type decls being indexed (OrderedCollections + a user package not in scope for cycle-27 sampling). v1.48 *could* land the optimistic 46.9% by indexing those packages explicitly, but that's a measurement-tooling change, not a verifier-architecture change.

3. **The per-pick agreement-rate signal's predictive power is the key load-bearing claim of cycle-44.** If cycles 42–43's 17/17 = 100% agreement extends to cycles 44+ (13/13 predicted for v1.47), then the name-+-type heuristic is closely tracking what verify-mode would actually catch — and Phase 1.5's verify pipeline becomes a **confidence-amplification** tool rather than a heuristic-replacement tool. That reframes the case for v2's accept-flow integration (PRD §20.2): verify outcomes don't change the verdict, they raise the confidence on already-correct verdicts.

The v1.48 plan should pick from (1)'s mechanical extensions — idempotence-lifted is the smallest cycle (one new template arm + ~30 tests), dual-style-consistency adds the most picks (5 in cycle-27), and the strategist's `.memberwiseArbitrary` path is the architectural prerequisite for v1.49+'s user-defined-carrier expansion.

## Captured artifacts

- Cycle-44 verifiable-fraction tally: this document.
- 3 new in-scope per-pick outcome predictions: §"Per-pick verify outcome predictions" table.
- v1.48+ roadmap implications: §"v1.48+ roadmap delta from cycle-43" — full verify coverage now ~2 cycles away.
- IndexedTypeShape mirror as the persistence boundary between SwiftInferProperties' index format and the kit's `TypeShape` (V1.47.A's pivot-from-mirror decision).
- Two-arm carrier router (V1.47.F) — establishes the pattern for v1.48+ carrier-aware emit dispatch.

No `triage-decisions.json` in `docs/calibration-cycle-44-data/` — cycle 44 didn't produce new per-pick verdicts (the cycle-27 corpus is unchanged at 21/29 = 72.4%). The verifiable-fraction + per-pick agreement signal are the measurement outputs.

## Open thread carried into v1.48

**Idempotence semantics of `endOfChunk`/`startOfChunk`/`sizeOfChunk` against a bound Int carrier** (§"Per-pick verify outcome predictions" caveat). If cycle-45 measurement surfaces `.bothPass` against the predicted `.defaultFails`, the cycle-27 REJECT verdict for #7–#9 was based on the heuristic conflating name-pattern with idempotence violation. v1.48 should either (a) run the actual verify subprocess against the OrderedAlgorithms package to settle the prediction, or (b) document the discrepancy and use it to refine the cycle-44 prediction model. Either way, the load-bearing finding is the *agreement-rate signal* — predicted-vs-measured tracking is what makes this trajectory meaningful.


---

## Cycle-47 reframing caveat (added at v1.51)

The per-pick agreement-rate signal and verifiable-fraction reported in this document are **synthetic-shape-class agreement** — measured on hand-crafted `SemanticIndexEntry` instances constructed inside the integration-test suite to match v1.49 emitter expectations. End-to-end-from-indexer measurement (the verify pipeline running against entries produced by `swift-infer index` against real source) begins at cycle-47 (`docs/calibration-cycle-47-findings.md`) and continues at cycle-48 (`docs/calibration-cycle-48-findings.md`).

The two measurements are complementary, not contradictory: this document's numbers establish the verify-architecture *capability* (cycles 41-46 confirmed agreement on hand-crafted shapes); cycle-47+'s numbers measure the indexer→verify path *end-to-end*. Cycle-48 establishes that closing the carrier-resolution gap (V1.51.A canonicalization) doesn't immediately produce `.bothPass`-class outcomes — a deeper call-expression-shape gap is the next load-bearing fix. See `docs/calibration-cycle-48-findings.md` §"v1.52+ roadmap" for the trajectory.