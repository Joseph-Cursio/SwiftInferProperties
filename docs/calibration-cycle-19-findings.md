# v1.22 Calibration Cycle 19 — Findings

Captured: 2026-05-10. swift-infer at `e22f076` (V1.22.D; v1.22 working copy). The nineteenth execution of PRD §17.3's empirical-tuning loop and the **second consecutive mechanism cycle whose priorities are directly informed by measurement-based reject classes** (cycles 15-16 priorities were projected from non-empirical reasoning; cycle 18 = v1.21 was the first measurement-driven cycle; cycle 19 = v1.22 is the second). Four independently-mergeable workstreams shipped in one release:

- **Workstream A (V1.22.A)** — BucketIterator name extension on V1.21.A's IteratorProtocol carrier veto (cycle-18 finding closure).
- **Workstream B (V1.22.B)** — `RoundTripTemplate` both-sides direction-counter -15 → -25 magnitude bump on V1.12.1 (cycle-18 finding closure).
- **Workstream C (V1.22.C)** — Fixed-point-name positive signal on non-lifted idempotence (3-cycle carry-forward; **first recall-positive signal in the post-V1.4.3 era**).
- **Workstream D (V1.22.D)** — Stride-style label both-sides veto on round-trip + inverse-pair (cycle-14 demotion target; 4-cycle carry-forward).

This document is the cycle-19 record: surface delta, per-workstream contribution, mechanism-class taxonomy update (13 → **14**, the first new class since v1.19's class 13), and the cycle-20 priority list rotation.

## Headline

| Metric | Cycle 18 (v1.21) | **Cycle 19 (v1.22)** | Δ |
|---|---:|---:|---:|
| Surface measured (post-v1.22) | 165 | **152** | **−13 (−7.9%)** |
| Cumulative trajectory (cycle 1 = 1167) | −85.86% | **−86.97%** | new low (first cycle past −86%) |
| Mechanism-class taxonomy | 13 | **14** | +1 (first new class since v1.19) |
| Test count | 1804 | **1845** | +41 |

**152-candidate surface is the headline number.** A measurable -7.9% reduction from cycle-18's 165-surface and **-87.0% below cycle-1's 1167-baseline**. v1.22 is the first cycle to cross the -86% cumulative-reduction threshold (prior low: -85.86% at cycle 18; -80.4% at cycle 13 before that). The descending trend continues with steady momentum (cycle-18: -85.86%; cycle-19: -86.97%; +1.11pp incremental reduction).

**Plan-vs-actual closure:** -13 vs projected -17 to -27. Variance attributable to the **asymmetric cross-pair noise class** identified in cycle-19 measurement: V1.22.B's both-sides direction-counter only fires when both pair sides are direction-labeled; ~5-10 OC `index(after:) × _minimumCapacity(forScale:)` pairs (one direction-labeled, one domain-marker-labeled) survive at score 20 (Possible). This class is a **cycle-20+ candidate** for an "asymmetric label class mismatch" counter.

| Workstream | Projected closure | Actual closure | Variance |
|---|---:|---:|---:|
| A — BucketIterator name extension | ~3 | -3 | 0 (exact) |
| B — both-sides direction full-veto | ~12 | -8 (7 OC + 1 Algo) | -4 (asymmetric pairs survive) |
| C — fixed-point-name positive signal | +5 to +10 (recall-positive) | 0 (no fixed-point names in cycle-1..14 corpora) | -5 to -10 (no surfacing) |
| D — stride-style label extension | ~2 | -2 | 0 (exact) |
| **Total** | **-17 to -27** | **-13** | **-4 to -14** |

**Two of four workstreams hit projection exactly** (V1.22.A and V1.22.D). V1.22.B's variance is a cycle-19 finding (asymmetric cross-pair noise class). V1.22.C's variance is "infrastructure-ready but didn't fire" — the recall-positive mechanism is in place; it just doesn't have functions in `FixedPointNames.curated` on the four cycle-1..14 corpora.

## Per-corpus surface delta

| Corpus | Cycle-18 (165) | V1.22.A | V1.22.B | V1.22.C | V1.22.D (cycle-19) | Total Δ |
|---|---:|---:|---:|---:|---:|---:|
| ComplexModule | 21 | 21 | 21 | 21 | **21** | **0** (no v1.22 mechanism targets) |
| OrderedCollections | 124 | 121 | 114 | 114 | **114** | **−10 (−8.1%)** |
| Algorithms | 13 | 13 | 12 | 12 | **10** | **−3 (−23.1%)** |
| PropertyLawKit | 7 | 7 | 7 | 7 | **7** | **0** (no v1.22 mechanism targets) |
| **Total** | **165** | **162** | **154** | **154** | **152** | **−13 (−7.9%)** |

**OrderedCollections absorbs 77% of the v1.22 closure** (-10 of -13). The OC surface is dominated by direction-pair cross-cell noise (V1.22.B target) + the BucketIterator class (V1.22.A target).

**Algorithms surface drops 23%** (13 → 10) — a mix of V1.22.B catching `EitherSequence.index(after:) × index(before:)` (the cycle-19 measurement found this Algo direction-pair was missed by V1.22.B's commit message which only noted OC) + V1.22.D closing the cycle-14-demoted `endOfChunk × startOfChunk` round-trip + inverse-pair pair on the same site.

**ComplexModule + PropertyLawKit byte-stable** at 21 + 7 = 28 — no v1.22 mechanism targets these corpora's surface composition.

## Per-template surface composition (post-V1.22.D)

| Template | Algo | OC | CM | PLK | Total | Cycle-18 total | Δ |
|---|---:|---:|---:|---:|---:|---:|---:|
| round-trip | 0 | 10 | 8 | 0 | **18** | 27 | **−9** |
| idempotence (non-lifted) | 0 | 22 | 0 | 1 | **23** | 23 | 0 (V1.22.C didn't surface) |
| monotonicity | 3 | 20 | 0 | 6 | **29** | 29 | 0 |
| commutativity | 1 | 10 | 6 | 0 | **17** | 17 | 0 |
| associativity | 1 | 10 | 6 | 0 | **17** | 17 | 0 |
| inverse-pair | 0 | 3 | 0 | 0 | **3** | 4 | **−1** |
| identity-element | 0 | 0 | 1 | 0 | **1** | 1 | 0 |
| dual-style-consistency | 0 | 22 | 0 | 0 | **22** | 22 | 0 |
| composition (lifted) | 0 | 1 | 0 | 0 | **1** | 1 | 0 |
| idempotence-lifted | 5 | 16 | 0 | 0 | **21** | 24 | **−3** |
| **Total** | **10** | **114** | **21** | **7** | **152** | **165** | **−13** |

**Round-trip drops 9** (27 → 18): V1.22.B closes 8 (7 OC + 1 Algo EitherSequence index-pair); V1.22.D closes 1 (Algo `endOfChunk × startOfChunk`).

**Idempotence-lifted drops 3** (24 → 21): V1.22.A closes 3 OC `_HashTable.BucketIterator.{advance, findNext, advanceToNextUnoccupiedBucket}` picks via the extended `Iterator` suffix rule.

**Inverse-pair drops 1** (4 → 3): V1.22.D closes 1 Algo `endOfChunk × startOfChunk` on the same site as the round-trip closure.

**Idempotence non-lifted byte-stable at 23.** V1.22.C is recall-positive but no functions in `FixedPointNames.curated` surface on the cycle-1..14 corpora; the cycle-17 OC `_description(type:)` formatter pick (which inspired the priority) is NOT in `FixedPointNames.curated` (it's a non-curated formatter that the rubric correctly leaves at Possible visibility).

## Mechanism-class taxonomy update

Pre-v1.22 (13 classes per `docs/calibration-cycle-18-findings.md`):

(unchanged from cycle 18)

Post-v1.22 (**14 classes**):

- Workstream A (V1.22.A): **extends class 7** carrier-protocol-conformance veto sub-class (V1.21.A lineage). No new class.
- Workstream B (V1.22.B): **extends class 6** parameter-label direction-counter (V1.10.1/V1.12.1/V1.15.1 lineage) with both-sides full-veto magnitude. No new class.
- **Workstream C (V1.22.C): NEW class 14 — fixed-point-name positive signal.** First recall-positive signal in the post-V1.4.3 era. All prior 13 classes are suppression-only (cycles V1.4.3 onward). Adding class 14 documents a structural shift in the loop's mechanism mix: the loop is no longer suppression-only. The +10 magnitude (vs the V1.4.1 curated-verb +40) reflects lower-confidence indicators.
- Workstream D (V1.22.D): **extends class 6** parameter-label semantic-intent counter with a new curated set `StrideStyleLabels.curated` (mirrors V1.12.1 direction-counter shape; different curated content). No new class.

**Class 14 is the first taxonomic shift to a positive-signal class** since the loop began. All prior cycles (V1.4.3 onward) were suppression-only — the loop's mechanism portfolio was 13 negative classes + 0 positive classes. v1.22 establishes the precedent: cycle-20+ work can introduce more positive signals if cycle-N measurement reveals additional fixed-point-style or canonical-form-style names.

## Per-mechanism effectiveness ranking (cycle-19)

| Mechanism (rank) | Cycle | Workstream | Surface closure | Per-construction precision |
|---|---|---|---:|---|
| **#1 by surface impact** | 19 (V1.22.B) | RoundTripTemplate both-sides direction full-veto | -8 | Closes structurally-symmetric direction-pair noise (`index(after:) × index(before:)` cross-cell pairs) at -25 magnitude; preserves V1.12.1's single-side -15 path verbatim |
| **#2 by surface impact** | 19 (V1.22.A) | IteratorProtocol carrier veto BucketIterator extension | -3 | Closes the cycle-18-finding `_HashTable.BucketIterator.*` picks; joint match (carrier + curated method name) preserves false-positive guardrail |
| **#3 by surface impact** | 19 (V1.22.D) | Stride-style label both-sides veto | -2 | Cycle-14 demotion target finally shipped (4-cycle carry-forward); cycle-14/17 ACCEPTED but auto-emit usability blocker — calibration trade-off |
| **#4 (recall-positive infrastructure)** | 19 (V1.22.C) | Fixed-point-name positive signal | 0 (no surfacing on cycle-1..14 corpora; recall-positive infrastructure ready) | First positive signal in post-V1.4.3 era; +10 magnitude on `{dedupe, simplify, clamp, truncate, standardize}` (excludes V1.4.1 overlap by design) |

V1.22 ships **four small mechanisms** vs v1.21's three large mechanisms. The aggregate surface impact (-13) is smaller than v1.21's (-170) because:

- **v1.22 targets the residual long-tail noise classes** identified by cycle-18 measurement (smaller per-class surface than cycle-15/16's projected mechanism classes).
- **The CM elementary-functions class was closed in v1.21.C (-148 in one workstream)** — the largest single-class noise pool in the corpora was already addressed.
- **V1.22.C is recall-positive infrastructure** — it doesn't suppress; the surface delta from this workstream is 0 on the cycle-1..14 corpora.

## Cycle-18 picks status at v1.22

The cycle-18 V1.21.D capture had 165 candidates. At v1.22:

- **Round-trip (27 picks) → 18:** V1.22.B + V1.22.D closed 9.
- **Idempotence non-lifted (23 picks) → 23:** byte-stable (V1.22.C recall-positive).
- **Idempotence-lifted (24 picks) → 21:** V1.22.A closed 3.
- **Inverse-pair (4 picks) → 3:** V1.22.D closed 1.
- **All other templates byte-stable.**

**Aggregate cycle-18 picks status at v1.22:** 13 of 165 cycle-18 candidates were the precise reject classes v1.22 targeted; 152 candidates preserve. The cycle-18 measurement → cycle-19 mechanism flow continues to ship targeted closures.

## Cycle-20 priority list (rotated post-v1.22)

The v1.22 cycle-19 finding closes the two direct cycle-18 findings + the 4-cycle stride-style carry-forward + the 3-cycle fixed-point-name carry-forward. Cycle-20 priorities (in expected impact order):

1. **v1.23 = cycle 20 empirical-only re-measurement** on the post-v1.22 surface. Plan: 50-decision triage stratified across the 152-surface; reports aggregate acceptance rate vs cycles 6 (26.7%) + 14 (34.8%) + 17 (52.3%); four-point trajectory analysis. Surface composition: round-trip 18 + idempotence-non-lifted 23 + monotonicity 29 + commutativity 17 + associativity 17 + inverse-pair 3 + identity-element 1 + dual-style 22 + composition-lifted 1 + idempotence-lifted 21. Provisional aggregate projection: **57-65%** (continued upward from cycle-17's 52.3%, reflecting cycle-18+19's precision-positive movement removing 22 reject picks across the cycle-18-→-cycle-20 surface).

2. **NEW (cycle-19 finding): Asymmetric label class mismatch counter** on round-trip. The 5-10 OC `index(after:) × _minimumCapacity(forScale:)` cross-pairs (one direction-labeled, one domain-marker-labeled) survive V1.22.B at score 20. Mechanism: when forward has `direction-label` and reverse has `domain-marker` (or vice versa), fire at -15 (matching V1.15.1 magnitude); when both have direction labels with V1.22.B already firing -25, no overlap. Magnitude: closes ~5-10 OC cross-pair noise candidates.

3. **FP approximate-equality template arm** (cycle-14 priority #4 carry-forward; cycle-18 priority #2 carry-forward). Required for production CM round-trip property tests on the 7 surviving canonical-inverse anchors. Out-of-band (changes property body emission, not surface). High-priority for v1.24+ (cycle-21+ mechanism release after the cycle-20 empirical re-measurement).

4. **Math-library op-name gate extension to `rescaledDivide` / `_relaxed*`** (carried forward; cycle-17 + cycle-18 measure these as 0% rate). Closes the 1 CM identity-element survivor + ~5 CM associativity/commutativity picks involving `_relaxedAdd` / `_relaxedMul` (cycle-17 measured these as ACCEPT — the curated `_relaxed*` math op-name gate would not suppress them; rather the cycle-17/18 evidence justifies promoting the existing curated set with the `_relaxed*` variants).

5. **CompositionTemplate non-numeric monoid extension** (NEW carry-forward from v1.19; cycle-17/18/19 measurement does not yet motivate; revisit at v1.24+).

6. **Lift admission relaxation from strict to permissive** (carry-forward; v1.21 + v1.22 precision-positive movement on the lifted-idempotence class continues to support strict-only admission; revisit at v1.24+).

7. **`Signal.Kind.liftedFromMutation` magnitude re-baselining** (carry-forward; cycle-19 lifted-idempotence projection ~67% does not motivate +10 → +5 demotion).

## Cumulative noise-floor + acceptance trajectory

| Cycle | Surface | Aggregate rate | Δ surface vs cycle 1 |
|---|---:|---:|---:|
| 1 (pre-tune) | 1167 | n/a | — |
| 6 (v1.9) | 349 | 26.7% | −70.1% |
| 13 (v1.16) | 229 | n/a | −80.4% |
| 14 (v1.17) | 229 | 34.8% | −80.4% |
| 17 (v1.20) | 335 | 52.3% | −71.3% (first reversal) |
| 18 (v1.21) | 165 | n/a | −85.9% (restored descending; new low) |
| **19 (v1.22)** | **152** | **n/a** | **−87.0% (new low; +1.1pp from cycle 18)** |

**Cycle 19 sets the second consecutive new cumulative-reduction low.** The post-cycle-17 mechanism cadence is producing steady incremental progress: cycle 18's -50.7% surface delta (cycle-17→cycle-18) + cycle 19's -7.9% (cycle-18→cycle-19) = cumulative -54.6% across the two-mechanism-cycle window. The §19 ≥70% acceptance-rate target depends on the cycle-20 measurement; provisional projection 57-65% from cycle-17's 52.3% baseline + the cycle-18/19 precision-positive movement.

**The mechanism-cycle cadence at this point is mature.** Cycle-15/16 introduced ambitious new template families (dual-style, lifted, composition); cycle-18 and cycle-19 are precision-positive long-tail closures. The pattern that's emerging:

- **Empirical cycles (6, 14, 17, 20=v1.23)** produce measurement data driving the next 1-3 mechanism cycles' priority list.
- **Mechanism cycles target measured reject classes** (cycle 18 = cycle-17 findings; cycle 19 = cycle-18 findings).
- **Long-running carry-forwards** (FP approximate-equality 6 cycles overdue; math-library `_relaxed*` 4 cycles overdue) accumulate during mechanism cycles when their measurement evidence is weak; cycle-20 measurement may redistribute.

## Conclusion

Cycle 19 produced the **second consecutive measurement-driven mechanism cycle** — V1.22.A and V1.22.B closed cycle-18's measured reject classes (BucketIterator-named picks; both-sides direction-pair noise); V1.22.D closed the 4-cycle stride-style demotion target. V1.22.C introduced the **first recall-positive signal in the post-V1.4.3 era** (mechanism class 14), establishing the precedent for cycle-20+ recall-positive work.

Surface 165 → **152** (-13 = -7.9%); cumulative reduction crosses -87% threshold. Mechanism-class taxonomy 13 → **14** (first new class since v1.19's class 13 composition-template additive-monoid scoring). Test count 1804 → **1845** (+41). Plan-vs-actual: -13 vs projected -17 to -27 (variance attributable to asymmetric cross-pair noise + recall-positive infrastructure with no surfacing). Two workstreams hit projection exactly (V1.22.A: -3, V1.22.D: -2).

**Cycle-20 = v1.23 empirical-only re-measurement** is the next planned cycle. Provisional aggregate projection 57-65% from cycle-17's 52.3% baseline. v1.23 will produce the **fourth measurement point** in the loop's history (cycles 6 + 14 + 17 + 20), enabling a four-point trajectory analysis that tracks the precision-positive movement of cycles 18 + 19 against the §19 ≥70% target.
