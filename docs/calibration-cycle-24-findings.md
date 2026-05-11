# v1.27 Calibration Cycle 24 — Findings

Captured: 2026-05-11. swift-infer at v1.27.B (`48919c5`). The twenty-fourth execution of PRD §17.3's empirical-tuning loop. Cycle 24 is a **measurement-driven mechanism cycle** closing two cycle-23 findings.

## Headline

| Metric | C23 (v1.26) | **C24 (v1.27)** | Δ |
|---|---:|---:|---:|
| Surface | 114 | **113** | −1 |
| Cumulative trajectory (cycle 1 = 1167) | −90.23% | **−90.32%** | small |

**Plan-vs-actual:** -1 vs projected -4. V1.27.A's Sequence-conformance path is infrastructure (no surface closure on cycle-1..14 — the cycle-23 Algo Iterator-like picks were already caught by V1.21.A/V1.22.A by the time V1.27.A's discover ran). V1.27.B closed 1 of 2 projected (cycle-23 sample-manifest listed `word × word` inverse-pair that didn't actually exist in the v1.25 surface — sample-manifest enumeration error).

## Per-workstream contribution

| Workstream | Source | Projected | Actual |
|---|---|---:|---:|
| A — Algo Iterator-like Sequence-conformance veto | cycle-23 #14, #15 | -2 | **0** (infrastructure; no current-corpus closure; cycle-23 picks caught by existing V1.21.A/V1.22.A paths) |
| B — OC bucket/word direction-pair name-prefix full-veto | cycle-23 #26, #27 | -2 | **-1** (cycle-23 #26 closed; #27 `word × word` listed in sample manifest didn't exist) |
| **Total** | | -4 | **-1** |

## Per-corpus surface delta

| Corpus | C23 | C24 |
|---|---:|---:|
| OC | 78 | **77** (-1) |
| CM | 21 | 21 |
| Algo | 8 | 8 |
| PLK | 7 | 7 |
| **Total** | **114** | **113** |

## Mechanism-class taxonomy

14 → **14** (no new classes; 2 extensions of existing classes 6 + 7).

- V1.27.A extends V1.21.A's class 7 carrier-protocol-conformance veto sub-class with Sequence-conformance path. Infrastructure ready for future Sequence-conforming carriers without explicit IteratorProtocol conformance.
- V1.27.B extends V1.11.1's class 6 parameter-label direction-counter on `InversePairTemplate` with name-prefix-gated magnitude bump. Parallel to V1.25.A (idempotence) + V1.22.B (round-trip).

## §19 reachability

Cycle-23 measured 67.6%. V1.27 closed 1 reject candidate (the `bucket × bucket` inverse-pair). Cycle-25 sample composition on the 113-surface is materially unchanged from cycle-23 — projected aggregate **65-72%** (sample-noise band of crossing §19's 70% target).

## Cycle-25 priority list

1. **v1.28 = cycle 25 empirical-only re-measurement.** Sixth measurement point. Validates whether cycle-23's 67.6% was sample-noise or a stable rate; whether v1.27's small closures shifted the aggregate above 70%.

2. **FP approximate-equality template arm** (11-cycle carry-forward). Correctness-emission work; required for production CM canonical-anchor property tests but doesn't shift the rate.

3. Carry-forwards from v1.19 (defer).

## Conclusion

Cycle 24 produced a small-magnitude closure (-1) — significantly under plan projection (-4). The variance is explained by enumeration error in cycle-23's sample-manifest (one of the two projected picks didn't exist in the actual surface) and by V1.27.A's infrastructure-only fire on the current corpora (the cycle-23 Algo picks were already caught by existing paths).

V1.27 still ships meaningful mechanism extensions: V1.27.A's Sequence-conformance path catches future Sequence-conforming carriers; V1.27.B's name-prefix gate completes the V1.22.B/V1.25.A pattern across all three pair-based templates (round-trip + inverse-pair + idempotence).

v1.28 = cycle 25 empirical re-measurement determines whether the loop's aggregate has crossed §19's ≥70% target.
