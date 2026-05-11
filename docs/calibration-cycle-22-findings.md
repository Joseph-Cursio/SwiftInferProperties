# v1.25 Calibration Cycle 22 — Findings

Captured: 2026-05-10. swift-infer at `308245e` (V1.25.A; v1.25 working copy). The twenty-second execution of PRD §17.3's empirical-tuning loop and the **fourth consecutive measurement-driven mechanism cycle** (cycles 18 + 19 + 21 + 22 = v1.21 + v1.22 + v1.24 + v1.25). Single-workstream cycle closing the cycle-21 finding.

## Headline

| Metric | Cycle 21 (v1.24) | **Cycle 22 (v1.25)** | Δ |
|---|---:|---:|---:|
| Surface measured | 130 | **114** | **−16 (−12.3%)** |
| Cumulative trajectory (cycle 1 = 1167) | −88.86% | **−90.23%** | **first cycle to cross −90%** |
| Mechanism-class taxonomy | 14 | **14** | 0 (one extension of class 6) |
| Test count | 1884 | **1893** | +9 |

**114-candidate surface is the headline number, crossing -90% cumulative reduction for the first time.** A measurable -12.3% reduction from cycle-21's 130, exceeding plan projection (-13 to -15). The plan projected primarily OC closures; cycle-22 closure includes 2 Algo picks the plan didn't enumerate (Algo direction-op idempotence picks on Iterator-like index names that survived V1.21.A + V1.22.A IteratorProtocol vetoes because the carriers don't conform to IteratorProtocol).

## Per-corpus surface delta

| Corpus | Cycle-21 | V1.25.A (cycle-22) | Δ |
|---|---:|---:|---:|
| ComplexModule | 21 | **21** | **0** (byte-stable; no v1.25 mechanism targets CM) |
| OrderedCollections | 92 | **78** | **−14** (matches plan projection of 13-15) |
| Algorithms | 10 | **8** | **−2** (unexpected Algo closure — index-advance pattern catches 2 more direction-labeled cursor picks) |
| PropertyLawKit | 7 | **7** | **0** (byte-stable) |
| **Total** | **130** | **114** | **−16 (−12.3%)** |

**Plan-vs-actual:** -16 vs projected -13 to -15. Slightly exceeded because V1.25.A's `index*`/`bucket*`/`word*` name-prefix gate matched 2 Algo functions in addition to the 14 OC variants the cycle-21 findings enumerated.

## Per-template surface composition

| Template | Cycle-22 total | Cycle-21 total | Δ |
|---|---:|---:|---:|
| round-trip | 12 | 12 | 0 |
| idempotence (non-lifted) | **3** | 19 | **−16** (all V1.25.A closures land here) |
| idempotence-lifted | 9 | 9 | 0 |
| monotonicity | 29 | 29 | 0 |
| commutativity | 17 | 17 | 0 |
| associativity | 17 | 17 | 0 |
| inverse-pair | 3 | 3 | 0 |
| identity-element | 1 | 1 | 0 |
| dual-style-consistency | 22 | 22 | 0 |
| composition (lifted) | 1 | 1 | 0 |
| **Total** | **114** | **130** | **−16** |

**Idempotence non-lifted drops 19 → 3 (-84%).** The single largest per-template percentage reduction in the loop's history. The surviving 3 picks are the residual non-index-advance + non-formatter + non-capacity remainder (likely `firstOccupiedBucketInChain(with:)` (cycle-17/20 unknown) + `nearMissLines(_:)` (PLK unknown) + 1 carry-forward).

## Mechanism-class taxonomy update

Pre-v1.25 (14 classes per cycle-21 findings):

(unchanged)

Post-v1.25 (**14 classes — no new classes; one extension of class 6**):

- V1.25.A extends class 6 (parameter-label direction-counter, V1.10.1 / V1.12.1 / V1.22.B lineage) with name-prefix-gated magnitude bump. Mirrors V1.22.B's both-sides direction full-veto pattern but on idempotence template with name-prefix gate.

## Cumulative noise-floor trajectory

| Cycle | Surface | Cumulative Δ vs cycle-1 (1167) |
|---|---:|---:|
| 1 (pre-tune) | 1167 | — |
| 6 (v1.9) | 349 | −70.1% |
| 13 (v1.16) | 229 | −80.4% (first past −80%) |
| 17 (v1.20) | 335 | −71.3% (first reversal) |
| 18 (v1.21) | 165 | −85.86% |
| 19 (v1.22) | 152 | −86.97% |
| 21 (v1.24) | 130 | −88.86% (first past −88%) |
| **22 (v1.25)** | **114** | **−90.23% (first past −90% threshold)** |

**Cycle 22 sets a new cumulative-reduction low at -90.23%.** First cycle to cross the **-90% threshold** vs cycle-1's 1167-baseline. Cumulative aggregate movement across cycles 17 → 22 (5 cycles since the cycle-17 measurement): 335 → 114 = **-66.0%**.

## Per-mechanism effectiveness ranking (cycle-22)

| Mechanism | Cycle | Surface closure |
|---|---|---:|
| **V1.25.A index-advance direction-op idempotence veto** | 22 | **-16 (single mechanism)** |

V1.25 ships **one targeted mechanism** vs v1.21's 3 / v1.22's 4 / v1.24's 4. The cycle-22 magnitude is intermediate between v1.22's -13 and v1.24's -22. Single-workstream cycle precedent: v1.19's Workstream B = mutating-method lift (-2 surface but new template family); v1.25 = pure suppression on a specific reject class.

## Cycle-23 priority list (rotated post-v1.25)

The cycle-22 closure resolves the direct cycle-21 finding. Cycle-23 priorities:

1. **v1.26 = cycle 23 empirical-only re-measurement** (the natural next step in the post-cycle-17 cadence: 2-3 mechanism cycles → 1 empirical re-measurement). Provisional aggregate projection: **55-65%** from cycle-20's 48.8% baseline + cycles 21+22's -38 reject closures across the cycle-1..14 corpora. Outcome A or B from the v1.26 plan's framing.

2. **FP approximate-equality template arm** (9-cycle carry-forward; cycle-14 priority #4). Required for production CM round-trip property tests on the surviving canonical-inverse anchors. Out-of-band correctness-emission work.

3. **Math-library `_relaxed*` extension** (7-cycle carry-forward). Cycle-20 measured ACCEPT; extension target unclear; defer indefinitely.

4. **CompositionTemplate non-numeric monoid extension** (carry-forward from v1.19). Defer.

5. **Lift admission relaxation** (carry-forward). Defer.

6. **`Signal.Kind.liftedFromMutation` magnitude re-baselining** (carry-forward). Defer.

The cycle-22 measurement-driven cycle exhausts the direct findings from cycles 19+20+21. v1.26 = cycle 23 empirical re-measurement will produce the **fifth measurement point** in the loop's history; the 5-point trajectory provides the strongest evidence yet for the §19 ≥70% target projection.

## Conclusion

Cycle 22 produced the **fourth consecutive measurement-driven mechanism cycle** — single targeted closure of the cycle-21 finding. Surface 130 → 114 (-12.3%); first cycle to cross -90% cumulative reduction. The cycle-21 finding (`index*`/`bucket*`/`word*` direction-op idempotence) was the dominant residual non-lifted idempotence reject class; V1.25.A closes 14 OC + 2 Algo variants, reducing idempotence non-lifted surface from 19 to 3 (-84%, largest per-template reduction in the loop's history).

The post-cycle-17 mechanism cadence has now shipped **four consecutive measurement-driven mechanism releases** (v1.21 → v1.22 → v1.24 → v1.25) closing direct findings from cycles 17 + 18 + 19 + 20 + 21 empirical/mechanism-cycle triages. The cumulative effect: cycle-17 → cycle-22 surface delta 335 → 114 = -66.0%. The §19 ≥70% target reachability remains on-track; v1.26 = cycle 23 empirical re-measurement will measure the resulting aggregate.
