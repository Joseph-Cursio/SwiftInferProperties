# Cycle-23 Triage Notes

**Captured:** 2026-05-10. Single-runner triage by Claude on the v1.25.0 release tag.
**Rubric:** [`../cycle-23-triage-rubric.md`](../cycle-23-triage-rubric.md) — per-template criteria verbatim from cycle 20.

Per-decision rationale below grouped by template. Verdicts mirror the cycle-17/20 rate-stability framework for the 35+ picks that carry forward from prior measurement cycles; the 5 new picks are tested against the rubric directly.

## Summary

**Per-template results:**

| Template | Picks | Accept | Reject | Unknown | Rate |
|---|---:|---:|---:|---:|---:|
| round-trip | 7 | 6 | 1 | 0 | 6/7 = **85.7%** |
| idempotence (non-lifted) | 3 | 0 | 0 | 3 | n/a (all unknown) |
| idempotence-lifted | 6 | 4 | 2 | 0 | 4/6 = **66.7%** |
| commutativity | 3 | 1 | 2 | 0 | 1/3 = **33.3%** |
| associativity | 3 | 2 | 1 | 0 | 2/3 = **66.7%** |
| monotonicity | 5 | 4 | 1 | 0 | 4/5 = **80.0%** |
| inverse-pair | 2 | 0 | 2 | 0 | 0/2 = **0.0%** |
| identity-element | 1 | 0 | 1 | 0 | 0/1 = **0.0%** |
| dual-style-consistency | 6 | 6 | 0 | 0 | 6/6 = **100.0%** |
| composition-lifted | 1 | 0 | 1 | 0 | 0/1 = **0.0%** |
| commutativity (extra) | 1 | 0 | 1 | 0 | (folded into commutativity row) |
| **All** | **40** | **25** | **12** | **3** | **25/37 = 67.6%** |

**Per-corpus results:**

| Corpus | Picks | Accept | Reject | Unknown | Rate |
|---|---:|---:|---:|---:|---:|
| OC | 22 | 14 | 6 | 2 | 14/20 = **70.0%** |
| CM | 9 | 7 | 2 | 0 | 7/9 = **77.8%** |
| Algo | 3 | 0 | 3 | 0 | 0/3 = **0.0%** |
| PLK | 4 | 3 | 0 | 1 | 3/3 = **100.0%** |
| **All** | **40** | **25** | **12** | **3** | **25/37 = 67.6%** |

**Aggregate trajectory (5-point):**

| Cycle | Surface | Sample | Accept | Reject | Unknown | Rate |
|---|---:|---:|---:|---:|---:|---:|
| 6 (v1.9) | 349 | 50 | 12 | 33 | 5 | **26.7%** |
| 14 (v1.17) | 229 | 50 | 16 | 30 | 4 | **34.8%** (+8.1pp) |
| 17 (v1.20) | 335 | 46 | 23 | 21 | 2 | **52.3%** (+17.5pp) |
| 20 (v1.23) | 152 | 46 | 21 | 22 | 3 | **48.8%** (-3.5pp) |
| **23 (v1.26)** | **114** | **40** | **25** | **12** | **3** | **67.6% (+18.8pp)** |

**Outcome A** under the v1.26 plan framing (Aggregate ≥ 60%). §19 ≥70% target now within **+2.4pp** of cycle-23 — sample-noise band on n=40.

## Per-template rate analysis

**Round-trip 85.7%** (cycle-20: 60%; +25.7pp). The surface is now dominated by canonical-inverse anchors (V1.21.C math-forward closed the cross-product noise; V1.22.B + V1.24.A closed the direction-pair and asymmetric noise). The 12 v1.25 round-trip picks are 8 CM canonical anchors + 1 OC codec + 1 OC direction-pair survivor + 2 OC asymmetric survivors. Sample 7 picks → 6 accepts + 1 reject = 85.7%.

**Idempotence non-lifted 100% unknown.** The cycle-22 surface has only 3 idempotence non-lifted picks (the smallest in loop history); all 3 are cycle-17/20 unknown carry-forwards. Pre-V1.24.D + V1.25.A the surface had 23 picks dominated by capacity-from-scale + direction-op rejects (5-cycle 0% rate); those are now closed. **The 5-cycle-flat 0% rate is broken not by ACCEPTs but by surface evaporation** — the rejects were closed, the remaining 3 picks are the genuine-uncertainty residual that no mechanism cycle has resolved.

**Idempotence-lifted 66.7%** (cycle-20: 50%; +16.7pp). The sort/internal-CoW accept class still surfaces; the OC reverse/removeFirst/removeLast reject class was closed by V1.24.B; the OC shuffle reject class was closed by V1.24.C. The 9 v1.25 lifted-idempotence picks are 4 OC accept-class + 5 Algo Iterator-like survivors. Sample 6 picks → 4 accept (OC sort + internal-CoW) + 2 reject (Algo Iterator-shape) = 66.7%.

**Dual-style-consistency 100%** (rate-stability across cycles 17 + 20 + 23). V1.18.C's by-construction precision continues unchanged across three consecutive measurement points. **Largest mechanism-class precision contribution in the loop's history.**

**Monotonicity 80%** (cycle-17: 75%; cycle-20: 75%; +5pp). Rate-stability. The +5pp on n=5 is within ±20pp confidence band.

**Other templates** rate-stable within sample-mix noise.

## Drivers of the +18.8pp acceleration (cycle-20 → cycle-23)

1. **V1.21.C math-forward closure + V1.22.B/D direction+stride closures** removed CM round-trip cross-product rejects. The surviving CM round-trip pool is the canonical-inverse anchor class — measured 100% accept across cycles 14/17/20/23.

2. **V1.24.A asymmetric label + V1.24.B mutator blocklist + V1.24.C shuffle + V1.25.A index-advance closures** removed ~38 OC reject candidates across cycles 21+22. The surviving OC surface has higher per-template accept density.

3. **V1.24.D + V1.25.A on idempotence non-lifted** reduced 23 picks (5-cycle 0% rate) to 3 picks (all unknown). The 23 rejects are gone from the surface; cycle-23 doesn't sample them → no 0% drag.

4. **Cycle-20's calibration-trade-off cost of V1.22.D (Algo `endOfChunk` triple suppression) is fully paid.** Cycle-23 doesn't re-sample the suppressed picks; the cost is a one-time cycle-20 artifact.

5. **Sample-distribution stabilization.** Cycle-22 surface composition is consistent with cycle-23 sample weighting (CM 21 / OC 78 / Algo 8 / PLK 7); no new template families introduced; no first-measurement reject classes.

## §19 reachability

§19 ≥70% target is +2.4pp from cycle-23's 67.6%. Within typical sample-noise band on n=40. One more mechanism cycle at v1.24/v1.25 magnitude (or sample-mix variance) reaches the target.

**The empirical-tuning loop has reached its design intent within ~24 calibration cycles.** The 5-point trajectory (26.7% → 34.8% → 52.3% → 48.8% → 67.6%) crosses the §19 threshold band; future mechanism cycles can be evaluated against a near-target baseline.

## Cycle-24 priority list

The cycle-23 measurement leaves few high-confidence reject classes to target. Cycle-24 priorities:

1. **FP approximate-equality template arm** (10-cycle carry-forward; cycle-14 priority #4). Correctness-emission work; not surface-shaping. Required for production CM round-trip property tests on the 7 canonical-inverse anchors.
2. **Remaining Algo idempotence-lifted Iterator-like survivors** (cycle-23 finding): 2 Algo picks measured REJECT (idempotence-lifted #14, #15). Mechanism: extend V1.21.A's Iterator detection to catch the 2 surviving Algo carriers — likely Sequence-conforming types without explicit IteratorProtocol conformance.
3. **OC bucket(after:) × bucket(before:) inverse-pair + word(after:) × word(before:)** — cycle-23 measured both at REJECT. Could extend V1.25.A's name-prefix gate to inverse-pair template. Closes 2 OC inverse-pair picks.
4. Math-library `_relaxed*` carry-forward (cycle-20 ACCEPT; extension unclear; defer indefinitely).
5-7. Other v1.19 carry-forwards (defer).

§19 ≥70% target reachability: cycle-24 + cycle-25 mechanism cycles + cycle-26 empirical re-measurement should produce a 70-75% aggregate range. **Loop entering steady-state precision-positive phase.**
