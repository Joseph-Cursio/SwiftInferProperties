# Calibration cycle 27 — surface re-capture (V1.30.A)

**Captured:** 2026-05-11 against the v1.29.0 release tag (`4eebd43`); v1.30 binary-equivalent. Re-uses the V1.29.D discover capture in `docs/calibration-cycle-26-data/post-v1.29-*.discover.txt`.

Cycle 27 is the **seventh empirical-only cycle** in the loop's history (after cycles 6, 14, 17, 20, 23, 25).

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
| 22 (v1.25) | 114 | −90.23% |
| 23 (v1.26) | 114 | −90.23% (carry) |
| 24 (v1.27) | 113 | −90.32% |
| 25 (v1.28) | 113 | −90.32% (carry) |
| 26 (v1.29) | 109 | −90.66% |
| **27 (v1.30)** | **109** | **−90.66%** (carry; v1.30 zero Sources/ change) |

## Per-template per-corpus composition (post-v1.29)

Recounted from the four `post-v1.29-*.discover.txt` files.

| Template | Algo | OC | CM | PLK | Total |
|---|---:|---:|---:|---:|---:|
| round-trip | 0 | 4 | 8 | 0 | **12** |
| idempotence (non-lifted) | 3 | 1 | 0 | 1 | **5** |
| idempotence-lifted | 0 | 7 | 0 | 0 | **7** |
| monotonicity | 3 | 20 | 0 | 6 | **29** |
| commutativity | 1 | 10 | 6 | 0 | **17** |
| associativity | 1 | 10 | 6 | 0 | **17** |
| inverse-pair | 0 | 0 | 0 | 0 | **0** |
| identity-element | 0 | 0 | 0 | 0 | **0** |
| dual-style-consistency | 0 | 22 | 0 | 0 | **22** |
| composition (lifted) | 0 | 0 | 0 | 0 | **0** |
| **Total** | **8** | **74** | **20** | **7** | **109** |

Header-counts cross-check: Algo 8 + OC 74 + CM 20 + PLK 7 = 109. ✓

## Drift vs cycle-25's recorded composition (113 surface)

v1.29 closed -4 picks across 3 mechanism classes (V1.29.A inverse-pair, V1.29.B identity-element, V1.29.C composition-lifted). All other per-corpus per-template counts unchanged.

| Template | C25 | C27 | Δ |
|---|---:|---:|---:|
| inverse-pair (OC) | 2 | 0 | -2 (V1.29.A) |
| identity-element (CM) | 1 | 0 | -1 (V1.29.B) |
| composition-lifted (OC) | 1 | 0 | -1 (V1.29.C) |
| All other templates | 109 | 109 | 0 |

**Three mechanism classes are now empty on the cycle-1..14 corpora** — first time in the loop's history.

## Stratification for V1.30.C

Sample 32 picks across the 7 non-empty template classes (with full coverage on idempotence non-lifted; near-full on idempotence-lifted):

| Template | v1.29 surface | Sample |
|---|---:|---:|
| round-trip | 12 | 6 |
| idempotence (non-lifted) | 5 | 5 (full coverage) |
| idempotence-lifted | 7 | 6 |
| monotonicity | 29 | 4 |
| commutativity | 17 | 3 |
| associativity | 17 | 3 |
| dual-style-consistency | 22 | 5 |
| **Total** | **109** | **32** |

Sampling rate 29.4% — comparable to cycle 23 (35.1%) and cycle 20 (30.3%); higher density than cycles 6 (14%), 14 (22%), 17 (14%).

See [`sample-manifest.md`](sample-manifest.md) (committed at V1.30.C).
