# Calibration cycle 23 — surface re-capture (V1.26.A)

**Captured:** 2026-05-10 against the v1.25.0 release tag (`061d9f8`); v1.26 binary-equivalent. Re-uses the V1.25.B discover capture in `docs/calibration-cycle-22-data/post-v1.25-*.discover.txt`.

Cycle 23 is the **fifth empirical-only cycle** in the loop's history.

## Aggregate surface trajectory

| Cycle | Surface | Cumulative Δ vs cycle-1 (1167) |
|---|---:|---:|
| 1 (pre-tune) | 1167 | — |
| 6 (v1.9) | 349 | −70.1% |
| 13 (v1.16) | 229 | −80.4% |
| 17 (v1.20) | 335 | −71.3% (first reversal) |
| 18-19 (v1.21-v1.22) | 152 | −86.97% |
| 20 (v1.23) | 152 | −86.97% (carry) |
| 21 (v1.24) | 130 | −88.86% |
| 22 (v1.25) | 114 | −90.23% (first past −90%) |
| **23 (v1.26)** | **114** | **−90.23%** (carry; v1.26 zero Sources/ change) |

## Per-template per-corpus composition (post-v1.25)

| Template | Algo | OC | CM | PLK | Total |
|---|---:|---:|---:|---:|---:|
| round-trip | 0 | 4 | 8 | 0 | **12** |
| idempotence (non-lifted) | 0 | 2 | 0 | 1 | **3** |
| idempotence-lifted | 5 | 4 | 0 | 0 | **9** |
| monotonicity | 3 | 20 | 0 | 6 | **29** |
| commutativity | 0 | 10 | 6 | 1 | **17** |
| associativity | 0 | 10 | 6 | 1 | **17** |
| inverse-pair | 0 | 3 | 0 | 0 | **3** |
| identity-element | 0 | 0 | 1 | 0 | **1** |
| dual-style-consistency | 0 | 22 | 0 | 0 | **22** |
| composition (lifted) | 0 | 1 | 0 | 0 | **1** |
| **Total** | **8** | **76** | **21** | **9** | **114** |

(OC count 76 vs 78 reported in V1.25.B summary — minor discrepancy attributable to recount; corpus discover output unchanged.)

## Surviving idempotence non-lifted (3 picks)

Post-V1.25.A's index-advance veto + V1.24.D's capacity/formatter veto, only 3 idempotence non-lifted picks survive:

- 2 OC picks (likely `firstOccupiedBucketInChain(with:)` cycle-17/20 unknown + 1 residual carry-forward).
- 1 PLK `nearMissLines(_:)` cycle-17/20 unknown.

This is the smallest idempotence non-lifted pool in the loop's history.

## Stratification for V1.26.C

Sample 40 picks across the 10 template classes. See [`sample-manifest.md`](sample-manifest.md) (committed at V1.26.C).
