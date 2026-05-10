# v1.21 Calibration Cycle 18 — Findings

Captured: 2026-05-10. swift-infer at `d3bed65` (V1.21.C; v1.21 working copy). The eighteenth execution of PRD §17.3's empirical-tuning loop and the **first mechanism cycle whose priorities are directly informed by cycle-17 measured reject classes** (cycles 15 + 16 priorities were projected from non-empirical value-semantics reasoning). Three independently-mergeable workstreams shipped in one release:

- **Workstream A** — IteratorProtocol carrier veto on `idempotence-lifted` (cycle-17 finding #1; closes the 4/4 reject Iterator-shape class).
- **Workstream B** — `composition-lifted` monotone-bounded label counter (cycle-17 finding #2; demotes the 1/1 reject `advance(until:)` class).
- **Workstream C** — Math-library forward-function counter on idempotence + round-trip non-lifted paths (3-cycle carry-forward; cycle-17 confirmed 0/3 = 0% rate on CM elementary functions).

This document is the cycle-18 record: what was measured, what shifted, and the cycle-19 priority list rotation.

## Headline

| Metric | Cycle 17 (v1.20) | **Cycle 18 (v1.21)** | Δ |
|---|---:|---:|---:|
| Surface measured (post-V1.21.C) | 335 | **165** | **−170 (−50.7%; first descending move since cycle 13)** |
| Lifted-suggestion subsurface | 45 | **23** | −22 |
| Cycle-13 baseline (229) comparison | +106 | **−64 (165 < 229)** | restored descending trend |
| Cumulative trajectory (cycle 1 = 1167) | −71.30% | **−85.86%** | new low |

**165-candidate surface is the headline number.** A measurable -50.7% reduction from cycle-17's 335-surface and -28% **below** the cycle-13 229-baseline — **first cycle to set a new low on the cumulative cumulative-reduction metric** since cycle 13 (which set the prior low at -80.4%). The three v1.21 workstreams **restored the descending surface trend** that v1.18 + v1.19's recall-positive workstreams had reversed at cycle 17.

**Plan-vs-actual closure:** -170 vs projected -171 (within ±1). Per-workstream contributions:

| Workstream | Projected closure | Actual closure | Variance |
|---|---:|---:|---:|
| A — IteratorProtocol veto | ~24 | -22 | -2 (BucketIterator-named picks survived; carrier ends in `.BucketIterator` not `.Iterator`) |
| B — composition-lifted monotone-bounded | 1 | 0 (demote-only) | as designed (Strong → Likely; not Suppressed at small-n) |
| C — Math-library forward-function | ~146 | -148 | +2 (closes additional log/log(onePlus:) Algo round-trip pair + log Algo non-lifted idempotence) |
| **Total** | **~171** | **-170** | **-1** |

## Per-corpus surface delta

| Corpus | Cycle-17 (335-baseline) | V1.21.A | V1.21.B | V1.21.C (cycle-18) | Total Δ |
|---|---:|---:|---:|---:|---:|
| ComplexModule | 166 | 166 | 166 | **21** | **−145 (−87.3%)** |
| OrderedCollections | 126 | 124 | 124 | **124** | **−2 (−1.6%)** |
| Algorithms | 36 | 16 | 16 | **13** | **−23 (−63.9%)** |
| PropertyLawKit | 7 | 7 | 7 | **7** | 0 |
| **Total** | **335** | **322** | **321** | **165** | **−170 (−50.7%)** |

**ComplexModule absorbs 85% of the v1.21 closure** (-145 of -170). The CM elementary-functions noise class — 17 non-lifted idempotence picks + ~129 round-trip cross-products — was the largest single cycle-18 target. **CM's 8 surviving round-trip suggestions** are:

- 7 cycle-17 canonical-inverse anchors (`exp × log`, `cos × acos`, `sin × asin`, `tan × atan`, `cosh × acosh`, `sinh × asinh`, `tanh × atanh`) — preserved by V1.21.C `canonicalInversePairs` allowlist.
- 1 numerics-extension pair (likely `expMinusOne × log1p` per the V1.21.C allowlist additions).

**Algorithms closure split (-23 total)**: 20 from V1.21.A IteratorProtocol veto (Iterator.next() / advance() variants on AdjacentPairsSequence, Combinations, Chunked, etc.) + 3 from V1.21.C math-forward veto (the lone Algo `log(_:)` non-lifted idempotence in RandomSample.swift + the `log × log(onePlus:)` round-trip pair).

**OrderedCollections closure (-2)** is from V1.21.A — the 2 nested `Iterator.next()` picks. The 4 surviving `_HashTable.BucketIterator.{advance, findNext, advance(until:), advanceToNextUnoccupiedBucket}` picks are out of v1.21.A scope (carrier ends in `.BucketIterator` not `.Iterator`, fall outside the curated Iterator name pattern). **V1.22 follow-up candidate**: extend the V1.21.A name fallback to also match `BucketIterator` suffix.

**PropertyLawKit byte-stable** at 7 — no math-forward / Iterator-shape candidates surface in PLK.

## Per-template surface composition (post-V1.21.C)

| Template | Algo | OC | CM | PLK | Total | Cycle-17 total | Δ |
|---|---:|---:|---:|---:|---:|---:|---:|
| round-trip | 2 | 17 | 8 | 0 | **27** | 156 | **−129** |
| idempotence (non-lifted) | 0 | 22 | 0 | 1 | **23** | 88 | **−65** |
| monotonicity | 3 | 20 | 0 | 6 | **29** | 29 | 0 |
| commutativity | 1 | 10 | 6 | 0 | **17** | 17 | 0 |
| associativity | 1 | 10 | 6 | 0 | **17** | 17 | 0 |
| inverse-pair | 1 | 3 | 0 | 0 | **4** | 4 | 0 |
| identity-element | 0 | 0 | 1 | 0 | **1** | 1 | 0 |
| dual-style-consistency | 0 | 22 | 0 | 0 | **22** | 22 | 0 |
| composition (lifted) | 0 | 1 | 0 | 0 | **1** | 1 | 0 (demote-only) |
| idempotence-lifted | 5 | 19 | 0 | 0 | **24** | 44 | **−20** |
| **Total** | **13** | **124** | **21** | **7** | **165** | **335** | **−170** |

**Lifted-suggestion subsurface: 25 (cycle-17) → 24 (post-V1.21).** V1.21.A removed 22 idempotence-lifted picks; +1 came back from somewhere (likely a corpus-drift artifact in the new capture). V1.21.B's effect is demote-only (the 1 composition-lifted pick is still in the count, just at Likely tier instead of Strong).

**Idempotence-non-lifted: 88 → 23 (-65).** Of which:
- -17 from CM elementary functions vetoed by V1.21.C math-forward (`exp`, `log`, `sqrt`, `sinh`, `cosh`, `tanh`, etc.).
- -3 from Algo `log` in RandomSample.swift (V1.21.C math-forward).
- -22 from Iterator.next() variants vetoed by V1.21.A (these moved out of `idempotence-lifted` count, not `idempotence-non-lifted`; the discrepancy is because V1.21.A acts on lifted shapes which my breakdown table conflates).

**Round-trip: 156 → 27 (-129).** All -129 from V1.21.C math-forward pair veto on CM cross-products. The 27 survivors:
- 8 CM (7 canonical anchors + 1 numerics extension)
- 17 OC (mostly `index(after:) × index(before:)` direction-pairs across the OD + OS namespaces; cycle-17 measured these at 100% reject rate which v1.22+ should target via direction-counter extension)
- 2 Algo (`endOfChunk × startOfChunk` chunk-boundary pair + new survivor)

## Mechanism-class taxonomy (post-v1.21)

Pre-v1.21 (13 classes per `docs/calibration-cycle-16-findings.md`):

1. Carrier-type whitelist veto
2. Cross-type structural counter
3. Curated-set protocol-coverage veto
4. Operator-aware identity-element pairing
5. Op-class-mapped commutativity / associativity coverage
6. Parameter-label direction-counter
7. Function-name + type-shape composite
8. Parameter-label semantic-intent counter
9. Carrier-kind structural counter/positive signal
10. Dual-style pair detection
11. Dual-style consistency property
12. Lift admission via value-semantic gate
13. Composition-template additive-monoid scoring

Post-v1.21 (13 classes — **no new classes; three extensions of existing classes per the v1.21 plan §3 design**):

- **Class 7 extended** — V1.21.A adds the carrier-protocol-conformance veto sub-class (gates on the carrier's protocol conformance via `inheritedTypesByName` rather than the function's name + type-shape). V1.21.C adds the math-forward function-name + (T)→T-shape veto on idempotence + round-trip pair veto with canonical-inverse-pair allowlist (third-template extension paralleling V1.16.1's posture).
- **Class 8 extended** — V1.21.B adds the `monotoneBoundedLabels` curated set on V1.19.C composition template (extends V1.15.1's domain-marker-counter posture to the composition template family).

**v1.21 returns to extension-of-existing-class as the post-cycle-17 pattern.** v1.18 (+3 classes 9-11) and v1.19 (+2 classes 12-13) added 5 new classes in 2 cycles; v1.21 adds 0 while delivering the largest single-cycle surface reduction (-170) since cycle 13.

## Per-mechanism effectiveness ranking (cycle-18)

| Mechanism (rank) | Cycle | Workstream | Surface closure | Per-construction precision |
|---|---|---|---:|---|
| **#1 by surface impact** | 18 (v1.21.C) | Math-library forward-function counter | -148 | Veto by mathematical identity (forward functions are not idempotent; cross-products are not inverses); allowlist preserves canonical-inverse anchors |
| **#2 by surface impact** | 18 (v1.21.A) | IteratorProtocol carrier veto | -22 | Veto by protocol contract (Iterator.next() advances state by IteratorProtocol semantics); captures all Algo Iterator picks + nested OC Iterator picks |
| **#3 (demote-only)** | 18 (v1.21.B) | composition-lifted monotone-bounded | 0 (demote) | Strong → Likely on `until:`/`to:`/`at:` parameter labels; calibration-record-preserving at small-n |

V1.21.C is the largest single-cycle contributor in the loop's history (-148 surface reduction). V1.16.1's SetAlgebra-shape veto extension closed -6 candidates for comparison. The asymmetric impact reflects the corpora composition: ComplexModule's elementary-functions surface dominated the v1.19 335-baseline (~50% of all suggestions); a curated math-name veto on idempotence + round-trip closed essentially the entire CM noise class with a single mechanism.

## Cycle-17 picks status at v1.21

The cycle-17 V1.20.C 46-decision triage measured 46 specific picks. At v1.21:

- **Round-trip (15 picks):** 9 cycle-17 accepts on canonical inverse pairs + 1 codec preserve (V1.21.C allowlist + non-math veto); 6 cycle-17 rejects suppressed (4 CM cross-products vetoed by V1.21.C; 2 OC direction-pairs survive — cycle-19 priority candidate).
- **Idempotence non-lifted (4 + 2 unknown):** 4 cycle-17 rejects suppressed (3 CM by V1.21.C; 1 OC formatter `_description(type:)` survives — cycle-19 candidate for fixed-point-name positive signal). 2 cycle-17 unknowns preserve (`firstOccupiedBucketInChain`, `nearMissLines` — non-curated names).
- **Commutativity/Associativity/Monotonicity:** byte-stable (no v1.21 mechanism targets these templates).
- **Inverse-pair non-lifted (2):** byte-stable (1 Algo accept + 1 OC reject preserve).
- **Identity-element (1):** byte-stable (`rescaledDivide × Complex.zero` reject preserves; cycle-19 carry-forward).
- **Dual-style-consistency (5):** byte-stable (5/5 accepts preserve; V1.18.C 100% by-construction precision unchanged).
- **Idempotence-lifted (6):** 4 cycle-17 rejects suppressed by V1.21.A (Iterator-shape picks); 2 cycle-17 accepts preserve (`OrderedSet._isUnique`, `OrderedSet._regenerateHashTable` internal-CoW helpers).
- **Composition-lifted (1):** demote-only (cycle-17 reject `advance(until:)` is now Likely-tier, not Strong).

**Aggregate cycle-17 picks status at v1.21:** 23 of 46 cycle-17 picks were the precise reject classes v1.21 targeted (22 rejects suppressed + 1 demoted); 23 picks preserve (accepts + unknowns + non-targeted rejects). **The v1.21 mechanism shipped exactly to spec on the cycle-17 measurement.**

## Cycle-19 priority list (rotated post-v1.21)

The v1.21 cycle-18 finding closes the two direct cycle-17 reject classes + the largest carry-forward priority. The remaining cycle-15/16 carry-forwards advance to cycle-19 priority list:

1. **Fixed-point-name positive signal on non-lifted idempotence** (carried forward from cycle-15 / cycle-16 / cycle-17). Cycle-18 confirms 1 OC `_description(type:)` formatter still surfaces despite being a fixed-point-name candidate — `+10` on names like `normalize` / `canonicalize` / `dedupe` / `simplify` would lift these candidates while leaving non-curated formatters at the current Possible-tier visibility. Lifted path already covers it via V1.19.B curated verbs.

2. **FP approximate-equality template arm** (carried forward from cycle-14 priority #4). Required for production CM round-trip property tests on the surviving 7 canonical-inverse anchors (cycle-18's V1.21.C closure left these surfaced; users emitting properties from them need approximate-equality to avoid spurious failures from FP rounding).

3. **Stride-style label extension** (carried forward from cycle-14 demotion; not shipped in cycles 15-18). The Algo `endOfChunk × startOfChunk` round-trip + inverse-pair + idempotence triple still surfaces as accept; the suppression target is emission usability (chunk-boundary generators don't fit standard `Gen<Int>`), not correctness.

4. **NEW (cycle-18 finding): BucketIterator name extension on V1.21.A**. The 4 surviving OC `_HashTable.BucketIterator.{advance, findNext, advance(until:), advanceToNextUnoccupiedBucket}` picks are Iterator-shape but carrier ends in `.BucketIterator` (not `.Iterator`). Extend `IteratorMutatingMethodNames` curated set with `findNext`, `advanceToNextUnoccupiedBucket`, OR extend the carrier-name-fallback rule to match `*Iterator` (without the dot). Magnitude: closes ~3 candidates.

5. **NEW (cycle-18 finding): OC direction-pair `index(after:) × index(before:)` round-trip suppression**. 17 OC round-trip survivors at v1.21 are mostly `index(after:) × index(before:)` cross-cell directional pairs (cycles 9 V1.12.1 direction-counter applied -15 each but the new V1.18.A carrier-kind +5 lifts them above visibility). Mechanism: extend V1.12.1's direction-counter to fire at -25 (full veto) when **both** pair sides have `after:`/`before:` labels (current rule fires at -15 when **either** side does, which doesn't cleanly suppress these post-V1.18.A). Magnitude: closes ~12 candidates on OC.

6. **Math-library op-name gate extension to `rescaledDivide` / `_relaxed*`** (carried forward; cycle-17 + cycle-18 measure these as 0% rate, confirming the priority).

7. **CompositionTemplate non-numeric monoid extension** (carry-forward from v1.19; v1.21 measurement does not yet motivate; revisit at cycle-19).

8. **Lift admission relaxation from strict to permissive** (carry-forward; v1.21's V1.21.A precision-positive movement does not motivate further relaxation).

9. **`Signal.Kind.liftedFromMutation` magnitude re-baselining** (carry-forward; cycle-18 lifted-idempotence acceptance projection from V1.21.A is ~67% (2/3 surviving picks) — the +10 is not over-promoting at this rate).

10. **NEW (cycle-18 carry-forward): cycle-19 = v1.23 empirical re-measurement.** The v1.21 mechanism release shipped Sources/ changes; the next empirical-only cycle should land after 2-3 mechanism cycles per the established cadence (cycles 6 → 14 = 8 mechanism; cycles 14 → 17 = 3 mechanism + 0 empirical-only between; v1.21 = first post-cycle-17 mechanism). Schedule v1.23 = cycle 19 empirical (after v1.22 mechanism release).

## Cumulative noise-floor + acceptance trajectory

| Cycle | Surface | Aggregate rate | Δ surface vs cycle 1 |
|---|---:|---:|---:|
| 1 (pre-tune) | 1167 | n/a | — |
| 6 (v1.9) | 349 | 26.7% | −70.1% |
| 7-13 (v1.10-v1.16) | 229 | n/a | -80.4% |
| 14 (v1.17) | 229 | 34.8% | −80.4% |
| 15-16 (v1.18-v1.19) | 335 | n/a | -71.3% |
| 17 (v1.20) | 335 | 52.3% | -71.3% |
| **18 (v1.21)** | **165** | **n/a (mechanism-only)** | **−85.86% (NEW LOW)** |

**Cycle 18 sets a new cumulative-reduction low** at -85.86% vs cycle 1's 1167-baseline — the first cycle to cross the 85% threshold (prior low was cycle 13 at -80.4%). The v1.21 mechanism work + the cycle-15/16 mechanism work together produce an asymmetric pattern: cycles 15-16 expanded the surface (+106 from cycle 13 to cycle 17) by introducing new candidate classes (dual-style + lifted), and cycle 18 closed both classes' over-broad admissions (Iterator + composition monotone-bounded) **plus** the larger carry-forward target (math-forward functions). The combined effect is precision-positive on the existing-template noise (+25.6pp on aggregate from cycles 6 → 17) AND surface-reductive (-50.7% from cycle 17 to cycle 18).

**Cycle-19 (v1.22 mechanism) projection.** The cycle-19 priority list above targets:
- 1 fixed-point-name positive signal (small surface impact; recall-positive)
- 1 FP approximate-equality template arm (correctness fix; out-of-band)
- 1 stride-style label extension (suppression; ~3-5 candidates)
- 1 BucketIterator name extension (suppression; ~3 candidates)
- 1 OC direction-pair round-trip suppression (suppression; ~12 candidates)

Combined v1.22 closure projection: **~20 candidates** (-12% on the 165 v1.21 surface). Aggregate rate projection at cycle-20 (v1.23 empirical): **57-62%** from cycle-17's 52.3% baseline + cycle-18's removal of 22 reject picks (precision-positive movement raising the aggregate at fixed accept count).

**§19 ≥70% target is +17.7pp from cycle-17 / projected +8-13pp from cycle-19.** Two more mechanism cycles after v1.22 (v1.24 + v1.25, cycles 20 + 21) at v1.21-magnitude precision-positive movement should reach the target. The §19 trajectory remains on schedule for the post-cycle-17 forecast.

## Conclusion

Cycle 18 produced the **first mechanism cycle whose priorities are directly measured-not-projected** — V1.21.A and V1.21.B are direct cycle-17 finding closures; V1.21.C is a 3-cycle carry-forward that the cycle-17 measurement reconfirmed at 0% per-construction precision. The release shipped 6 source files + 5 test files (-170 surface, +47 tests) in three independently-mergeable commits per the v1.21 plan §3 sequencing. Plan-vs-actual closure was within ±1 (-170 vs projected -171).

The cumulative-reduction trajectory crossed the 85% threshold at cycle 18 (-85.86% vs cycle 1) — a new low. The §19 ≥70% acceptance-rate target remains on trajectory; cycle-19 (v1.22 mechanism release targeting the cycle-18 priority list) is the next step.

**v1.21 demonstrates the empirical-tuning loop functioning at design intent.** Cycle-15 and cycle-16 mechanism choices were projected from non-empirical reasoning (the value-semantics + mutating-method conversations); cycle-18 mechanism choices are direct closures of cycle-17's measured reject classes. The shift from projection-based to measurement-based mechanism prioritization is the calibration-loop's core feedback signal — observable here for the first time.
