# v1.12 Calibration Cycle 9 — Findings

Captured: 2026-05-09. swift-infer at `f0c40f4` (V1.12.1 — round-trip direction-label counter-signal). The ninth execution of PRD §17.3's empirical-tuning loop and the **first cycle to complete a three-template direction-counter family**.

This document is the cycle-9 record: what we ran, what we learned, what shipped, what's deferred.

## Headline

**Cycle 9 shipped one structural rule: round-trip direction-label counter-signal.** V1.12.1 lands the mechanism on its third template, after v1.10's idempotence consumer and v1.11's inverse-pair consumer. The new helper emits `-15` (mirroring v1.10's idempotence weight verbatim — round-trip's `+30` typeSymmetry baseline matches idempotence's, not inverse-pair's `+25` which justified v1.11's `-10`) when *either* pair-side's first-parameter argument label is in `IdempotenceTemplate.directionLabels`.

| Tuning | Type | Where | Empirical effect |
|---|---|---|---|
| `RoundTripTemplate.directionLabelCounterSignal` (V1.12.1) | scoring counter | first-param argument label of either side | **−31 / −10.8% aggregate** (−18 Algorithms + −13 OrderedCollections); 0 ComplexModule + 0 PropertyLawKit |

After v1.12: total `--include-possible` surface across the 4 corpora went **288 → 257** (−31, −10.8%). **Largest single-cycle structural-rule delta to date** — reflects round-trip being the largest-surface template (181 of 288 = 62.8% of post-v1.11 surface) and the dominant `index(after:) ↔ index(before:)` pattern across collection-protocol-conforming types in both swift-collections and swift-algorithms.

## Cycle-7 → cycle-8 → cycle-9: the direction-counter family completes

Cycle 7 (v1.10) introduced the mechanism on `IdempotenceTemplate`.
Cycle 8 (v1.11) replicated it on `InversePairTemplate` with calibrated `-10` weight.
Cycle 9 (v1.12) lands it on `RoundTripTemplate` with `-15` weight — completing the direction-counter family across the three templates whose Possible-tier surface contains `(Index) -> Index` shapes.

Three-cycle pattern in compact form:

```
Cycle 7 (V1.10.1): IdempotenceTemplate    +30 baseline, -15 counter → -53 surface
Cycle 8 (V1.11.1): InversePairTemplate    +25 baseline, -10 counter → -8  surface
Cycle 9 (V1.12.1): RoundTripTemplate      +30 baseline, -15 counter → -31 surface
                   ─────────────────────────────────────────────────────────────
Family total                                              -92 surface (cycles 7-9)
```

The mechanism is now confirmed *template-agnostic*: same `Signal.Kind.directionLabel` enum case, same 10-element `IdempotenceTemplate.directionLabels` curated set, three different consumers — each calibrating its counter weight to its own typeSymmetry baseline. The v1.11 plan's open-decision-#2 commitment ("hoist as a v1.13 atomic move when round-trip becomes the third consumer") now becomes the **next-cycle commitment** — three consumers cross the threshold for shared-utility refactoring.

This cycle validates three design choices made earlier in the loop:

1. **`Signal.Kind.directionLabel` is the right factoring** (load-bearing across three consumers).
2. **The curated 10-element direction set is portable** across templates with `+25`/`+30` baselines.
3. **Per-template counter weight calibration is the right ergonomic** — one set, three weights, no false-positive collateral observed across nine cycles.

## Corpus selection

Same four cycle-1+2+3+4+5+6+7+8 targets. Diff target is `docs/calibration-cycle-8-data/post-inverse-direction-counter-*.discover.txt` (the 288-surface):

| Corpus | Target | Cycle-8 total | Cycle-9 total | Δ |
|---|---|---:|---:|---:|
| swift-numerics | ComplexModule | 166 | 166 | 0 |
| swift-collections | OrderedCollections | 84 | 71 | **−13** |
| swift-algorithms | Algorithms | 31 | 13 | **−18** |
| SwiftPropertyLaws | PropertyLawKit | 7 | 7 | 0 |
| **Total** | | **288** | **257** | **−31 (−10.8%)** |

Per-corpus pre/post snapshots committed to `docs/calibration-cycle-9-data/post-roundtrip-direction-counter-*.discover.txt`.

## What v1.12 ships (the mechanism)

One piece:

- **`RoundTripTemplate.directionLabelCounterSignal(for:)` extension method** in `Sources/SwiftInferTemplates/RoundTripDirectionLabelCounter.swift` (file-split per the V1.6.1 / V1.8.1 / V1.10.1 / V1.11.1 file-length precedent — pre-emptively split because `RoundTripTemplate.swift` was already 348 lines, within 17 of the swiftlint `type_body_length: 350` hard error). The helper consults the existing `Signal.Kind.directionLabel` (V1.10.1) and the existing `IdempotenceTemplate.directionLabels` curated set (V1.10.1) — no new enum case, no new curated set, no new `KnownProperty`. Wired into `RoundTripTemplate.suggest(...)`'s signal-aggregation pipeline alongside the existing cross-type counter, non-deterministic veto, and shape-gated protocol-coverage veto.

The mechanism reuses the existing Score / Tier machinery directly. Other six templates (idempotence / inverse-pair / commutativity / associativity / monotonicity / identity-element) are byte-identical to v1.11.

## Per-corpus suppression breakdown

### swift-algorithms / Algorithms

| Template | Cycle-8 | Cycle-9 | Δ |
|---|---:|---:|---:|
| **round-trip** | **20** | **2** | **−18** |
| idempotence | 5 | 5 | 0 |
| monotonicity | 3 | 3 | 0 |
| commutativity | 1 | 1 | 0 |
| associativity | 1 | 1 | 0 |
| inverse-pair | 1 | 1 | 0 |

18 of 20 round-trip claims suppressed — **90.0% of Algo round-trip surface eliminated**. The 18 suppressed are direction-labeled `index(after:) ↔ index(before:)` self-pairs across 18 source files (AdjacentPairs, Chain, Chunked × 5 instances, Compacted, Cycle, EitherSequence, FlattenCollection, Indexed, Intersperse × 2, Joined × 2, Product, Stride, Windows). The 2 cycle-9 survivors are non-direction-labeled:
- `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` (Chunked) — labels `startingAt` / `endingAt` are stride-style, **not** in the curated 10-element direction set. Cycle-10 candidate per the v1.12 plan's "stride-style label extension" out-of-scope item. (Also surfaces as the parallel inverse-pair survivor — same pair, two templates surface it.)
- `log(_:) ↔ log(onePlus:)` (RandomSample) — labels `_` / `onePlus` not in curated set. Mathematically related but not strictly inverse; domain-mismatch territory.

### swift-collections / OrderedCollections

| Template | Cycle-8 | Cycle-9 | Δ |
|---|---:|---:|---:|
| **round-trip** | **25** | **12** | **−13** |
| idempotence | 13 | 13 | 0 |
| inverse-pair | 6 | 6 | 0 |
| monotonicity | 20 | 20 | 0 |
| commutativity | 10 | 10 | 0 |
| associativity | 10 | 10 | 0 |

13 of 25 round-trip claims suppressed — **52.0% of OC round-trip surface eliminated**. The 13 suppressed split into two patterns:
- 7 self-pair + same-shape direct suppressions: `index(after:)/(before:)` self-pairs across `OD+Elements.SubSequence`, `OD+Elements`, `OD+Values`, `OS+RandomAccessCollection`, `OS+SubSequence`; one `word(after:) ↔ word(before:)` on `_HashTable+UnsafeHandle`.
- 6 cross-pairs: OS+RandomAccessCollection's `index(after:)`/`index(before:)` paired with OS+Testing's `_minimumCapacity(forScale:)` / `_maximumCapacity(forScale:)` / `_scale(forCapacity:)` — either-side detection fires on the `after`/`before` side even though the partner uses `forScale`/`forCapacity`. (These are the cross-extension pairs that survived cycle-8's cross-type counter because both sides land on `OrderedSet` after extension resolution.)

The 12 cycle-9 survivors are all non-direction-labeled:
- 6 HashTable Constants pairs (`minimumCapacity(forScale:) ↔ maximumCapacity(forScale:)`, `minimumCapacity(forScale:) ↔ scale(forCapacity:)`, `minimumCapacity(forScale:) ↔ wordCount(forScale:)`, `maximumCapacity(forScale:) ↔ scale(forCapacity:)`, `maximumCapacity(forScale:) ↔ wordCount(forScale:)`, `scale(forCapacity:) ↔ wordCount(forScale:)`).
- 3 OS+Testing internal pairs (`_minimumCapacity(forScale:) ↔ _maximumCapacity(forScale:)` etc.).
- 2 `_value(forBucketContents:) ↔ _bucketContents(for:)` shape pairs.
- 1 `_HashTable+UnsafeHandle` `(UInt64) -> Int? ↔ (Int?) -> UInt64` shape pair.

All 12 survivors are `forScale`/`forCapacity`/`forBucketContents`/`_` — domain-mismatch territory for cycle-10's planned mechanism.

### swift-numerics / ComplexModule

| Template | Cycle-8 | Cycle-9 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 166 | 166 | 0 |

ComplexModule has zero direction-labeled round-trip pairs — all `(Complex, Complex) -> Complex` shapes use `_:` parameter labels (Swift convention for arithmetic operators). Byte-identical to cycle-8. V1.12.1 has nothing to suppress on this corpus.

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-8 | Cycle-9 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 7 | 7 | 0 |

PLK has no round-trip candidates. Byte-identical to cycle-8.

## Cycle-6 round-trip picks verification

The cycle-6 round-trip triage picks (n=14) split 6 accept / 8 reject (sample manifest in `docs/calibration-cycle-6-data/sample-manifest.md`). Verification against v1.12.1:

The 8 cycle-6 round-trip rejection picks are:
- Multiple `index(after:) ↔ index(before:)` self-pairs in OC and Algo — **suppressed by V1.12.1** (direction-labeled).
- `minimumCapacity(forScale:) ↔ scale(forCapacity:)` (OC) — **still surfaces** (domain-mismatch territory, not direction-labeled).
- `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` (Algo) — **still surfaces** (stride-style, not direction-labeled).

Quantitatively: of the 8 cycle-6 round-trip rejections, **the direction-labeled subset (~5-6 of 8 based on the per-pick examination) is now suppressed by V1.12.1**; the domain-mismatch + stride-style subset (~2-3 of 8) stays surfaced for cycle-10. This is consistent with the per-corpus suppression pattern (90.0% of Algo round-trip + 52.0% of OC round-trip).

The cycle-6 round-trip acceptance rate was 6/14 = 42.9%. Re-sampling the post-V1.12.1 round-trip surface (181 candidates aggregate → 150 survivors) would measure whether the per-template rate has moved up — the direction-labeled rejections are gone, so the rejected-pool denominator has shrunk while the accepted-pool numerator is unchanged. Expected effect: round-trip acceptance rate moves from 42.9% to ≈ 60-70% on a re-sample of the surviving 150. Quantification deferred to the v1.13+ Possible-tier re-sampling deliverable.

## Trajectory across all 9 cycles

| Cycle | Mechanism | Surface | Δ from prior | Cumulative Δ |
|---|---|---:|---:|---:|
| 1 (pre-tune) | none | 1167 | — | — |
| 1 (post-tune V1.4.3) | FP-storage + cross-type counter-signals | 358 | −809 | −69.3% |
| 2 (V1.5.2) | textual-only protocol-coverage suppression | 353 | −5 | −69.7% |
| 3 (V1.6.1) | identity-element pair-formation skip-list | 350 | −3 | −70.0% |
| 4 (V1.7.1) | stdlib-conformance bake-in | 326 | −24 | −72.1% |
| 5 (V1.8.1) | shape-gated Codable veto on round-trip | 349 | +23 | −70.1% |
| 6 (empirical-only) | (no surface change; baseline measured) | 349 | 0 | −70.1% |
| 7 (V1.10.1) | idempotence direction-label counter | 296 | −53 | −74.6% |
| 8 (V1.11.1) | inverse-pair direction-label counter | 288 | −8 | −75.3% |
| **9 (V1.12.1)** | **round-trip direction-label counter** | **257** | **−31** | **−78.0%** |

**−78.0% cumulative reduction** with nine compositional mechanisms — crosses the 75% milestone projected in the V1.12.0 plan. Cycle-9's −31 is the **largest single-cycle structural-rule delta to date**, reflecting:
1. Round-trip is the largest-surface template (181 of 288 = 62.8% of post-v1.11 surface).
2. The `index(after:) ↔ index(before:)` pattern is the dominant collection-protocol noise class — present in 18 Algorithms source files + 5 OC source files.
3. Cross-pairs widened the suppression beyond self-pair shapes (the 6 OC `index(after:) × _someCapacity(forScale:)` cross-extension pairs were suppressed by either-side detection).

The compositional mechanisms across cycles 1-9 each target a structurally distinct cause-of-noise class. Per-cycle surface deltas naturally narrow over time as the dominant noise classes are resolved, but cycle-9's large delta confirms that re-applying a verified mechanism to a new template is a high-leverage move when the template is large-surface.

## What v1.12 demonstrates

**The mechanism-development cadence is real.** The v1.12 plan's framing was:

> v1.10 introduces in cycle N
> v1.11 replicates in cycle N+1
> v1.12 completes the family in cycle N+2
> v1.13 hoists the abstraction in cycle N+3

Cycles 7 → 8 → 9 → (planned) 10 follow this pattern exactly. Future mechanisms (domain-mismatch detection, FP approximate-equality, SetAlgebra-shape coverage candidates) will likely follow the same shape. The cadence gives each cycle a focused, attribute-clean delivery while accumulating reusable abstractions.

**Plan-vs-actual exact match.** The v1.12 plan projected −31 (Algo −18, OC −13, CM 0, PLK 0). Actual: −31 (Algo −18, OC −13, CM 0, PLK 0). **No deviation in any column.**

This is the methodology-validation outcome. The cycle-8 findings flagged a plan-vs-actual deviation (projected −12, actual −8) and identified the root cause: substring counts (`grep -c "inverse-pair"`) instead of per-suggestion line counts (`grep -c "Template: inverse-pair"`). The v1.12 plan applied the fix preemptively — the projection was generated by a Python script using `re.compile(r"^Template:\s+(\S+)")` against the cycle-8 snapshots. Cycle-9's exact match confirms the fix.

**Either-side detection scales to the third template.** The 6 OC cross-pairs (OS+RAC's `index(after:)`/`index(before:)` paired with OS+Testing's `_someCapacity(forScale:)` family) demonstrate either-side detection's value: a forward-only check would have missed these because the curated label appears on only one side. False-positive cost: zero observed across nine cycles.

**Score arithmetic was correctly calibrated.** Bare-shape pairs landed at `+15` Suppressed (clean margin from `+20`). Curated-name pairs would land at `+55` Likely (clean preservation, well above `+40`). Discoverable-grouped pairs would land at `+50` Likely. No corpus pair lands exactly on tier boundaries — design-time concern preventive, now confirmed empirically.

## Plan-vs-actual

The v1.12 plan f-bullet predicted:
> Algorithms round-trip 20 → 2 (−18; 90.0% of Algo round-trip surface)
> OrderedCollections round-trip 25 → 12 (−13; 52.0% of OC round-trip surface)
> ComplexModule round-trip 136 → 136 (byte-identical; no direction labels)
> PropertyLawKit round-trip 0 → 0 (byte-identical)
> Aggregate 288 → 257 (−31, −10.8%)

**Actual outcome:**
- Algo round-trip: 20 → 2 (−18). Expected −18. ✓ **Exact.**
- OC round-trip: 25 → 12 (−13). Expected −13. ✓ **Exact.**
- ComplexModule: 166 → 166 (0). Expected unchanged. ✓
- PropertyLawKit: 7 → 7 (0). Expected unchanged. ✓
- Aggregate: 288 → 257 (−31, −10.8%). Expected −31. ✓ **Exact.**

**No deviation in any column.** First cycle in the calibration loop's history with a point-for-point projection match across all four corpora. Methodology fix from cycle-8 paid off immediately.

## Methodology gaps observed

**No new gaps unique to v1.12.** The cycle-8 gaps carry forward unchanged:
- Curated direction-label set is closed (10 entries; v1.12 deliberately does *not* extend it).
- Domain-mismatch sub-pattern still pending (now affects idempotence on OC HashTable + inverse-pair on OC SetAlgebra + round-trip on OC HashTable Constants).
- Possible-tier acceptance rate not re-measured at v1.10 / v1.11 / v1.12. The cycle-6 6/14 round-trip rate is now stale post-V1.12.1 (the surface dropped from 181 to 150).

**Stride-style label observation persists.** The 1 Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor is now visible on *both* round-trip and inverse-pair templates (V1.12.1 didn't suppress because the labels aren't in the curated set; V1.11.1 didn't suppress for the same reason). The cycle-10 stride-style label extension would resolve both at once — a natural single-mechanism-two-template delivery.

**The 8 cycle-6 round-trip picks are now mostly accounted-for.** ~5-6 of 8 suppressed (V1.12.1 direction-label counter); ~2-3 of 8 stay surfaced for the cycle-10 domain-mismatch + stride-style mechanisms. No cycle-6 round-trip picks remain "unknown" — every rejection has an identified cause-of-noise class with a queued mechanism.

## Cycle-10 priority list (in expected impact order)

The cycle-10 priority list is now anchored on cycle-6's measurements + cycle-7's verification + cycle-8's cross-template replication validation + cycle-9's three-consumer family completion:

1. **v1.13 hoist refactor** — `directionLabels` + `Signal.Kind.directionLabel` to a shared `SwiftInferCore.DirectionLabels` namespace. Zero behavior change; pure refactor for site-of-truth cleanup. v1.11 plan's open-decision-#2 commitment ("hoist when round-trip becomes the third consumer") becomes the **next-cycle commitment**. Doesn't affect surface counts; lands as an attribution-clean v1.13 release. ~half a day.

2. **SetAlgebra-shape detection on inverse-pair.** *(Carried from cycle-9 priority #2; cycle-8 picks #45-#47 still surfacing.)* The 6 OC `intersection(_:) ↔ subtracting(_:)` survivors need a mechanism that recognizes "Self-typed binary ops on a SetAlgebra-conforming type" as not-true-inverses. Likely a new candidate property in `ProtocolCoverageMap` (`setAlgebraIntersectionSubtractingNotInverse`) wired into `InversePairTemplate.protocolCoverageVeto`. ~half a day.

3. **Domain-mismatch detection family on idempotence + inverse-pair + round-trip.** *(Carried from cycles 7-9 priority #3; ELEVATED to NEW priority #3 because cycle-9 surfaces the largest pool of survivors here — 12 OC round-trip + 7 OC idempotence + 0 inverse-pair, ~19 candidates total.)* Semantic intent inference on parameter labels (`forScale` vs return context). Likely a new `Signal.Kind.domainMismatchLabel` with curated mapping pairs. Could ship as a single mechanism applied to three templates simultaneously — paralleling the direction-counter family's three-cycle deployment cadence but compressed into a single release. ~1 day.

4. **Stride-style label extension.** *(Carried from cycle-8 priority #4.)* Add `startingAt`, `endingAt`, `from`, `until`, `offset` to a separate "stride-anchor" curated set (or extend `directionLabels` with adjusted count tests). Closes the 1 Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor on both round-trip + inverse-pair. Risk: false-positives on legitimate stride-anchored inverse pairs (rare in stdlib, possible in domain corpora). ~1 hour if extending `directionLabels`; ~half a day if creating a separate set.

5. **Possible-tier re-sampling on the post-v1.12 surface (257 across 4 corpora).** *(Carried from cycles 7+8 priority #6.)* The cycle-7+8+9 noise-floor reductions were substantial (296 → 257 = −13.2% in three cycles). Re-running the cycle-6 rubric on a fresh 50-decision sample at v1.12 should produce a measurably higher acceptance rate on the surviving 257 candidates. ~half a day.

6. **FP approximate-equality template arm.** *(Carried forward from cycles 2-8 priority #2/#3.)* Real `KitFloatingPointTemplate`. ~1 day.

7. **Math-library op-name gate extension.** *(Carried forward from cycle-4 priority #5.)* `rescaledDivide` / `_relaxedAdd` / `_relaxedMul` to V1.6.1's stdlib operator gate. ~1 hour.

8. **`surfacedAt` plumbing.** *(Carried forward from cycle-1 priority #4.)*

9. **Multi-rater triage methodology.** *(Carried forward from cycle-6.)*

10. **Codec set broadening + SuggestionIdentity continuity fixture.** *(Carried forward.)*

11. **SemanticIndex.** *(Carried forward; multi-cycle effort.)*

## Summary

Cycle 9 shipped one structural rule: a round-trip direction-label counter-signal (V1.12.1) that completes the three-template direction-counter family. The empirical effect was −31 of 288 surfaced suggestions (−10.8% aggregate) — the **largest single-cycle structural-rule delta to date**, reflecting round-trip being the largest-surface template (181 of 288 = 62.8% of post-v1.11 surface) and the dominant `index(after:) ↔ index(before:)` pattern across collection-protocol-conforming types.

The cycle-7 → cycle-8 → cycle-9 mechanism-development cadence (introduce → replicate → complete the family) is now confirmed as a useful design pattern for the calibration loop. v1.13 will execute the planned hoist-to-shared-namespace refactor, completing the four-cycle abstraction-development cadence: introduce, replicate, complete the family, hoist.

Plan-vs-actual was a point-for-point exact match across all four corpora — first time in the calibration loop's history. The methodology fix from cycle-8 (per-suggestion line counts via `^Template:` regex) paid off immediately on cycle-9's projection accuracy.

Cumulative trajectory across cycles 1–9: **1167 → 257 (−78.0%)** with nine compositional mechanisms — crosses the 75% milestone projected in the V1.12.0 plan. Cycle-10's priority list is now data-anchored on four cycles of measurement: cycle-6's per-template baseline rates + cycle-7's mechanism verification + cycle-8's cross-template replication validation + cycle-9's three-consumer family completion. The expected cycle-10 priorities cluster around (a) the v1.13 hoist refactor, (b) the SetAlgebra-shape detection on inverse-pair, and (c) the domain-mismatch family on idempotence + inverse-pair + round-trip simultaneously. The natural cadence stays at one mechanism per release, with v1.13 as a zero-behavior-change refactor between mechanism cycles.
