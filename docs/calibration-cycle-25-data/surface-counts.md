# Calibration cycle 25 — surface re-capture (V1.28.A)

**Captured:** 2026-05-11 against the v1.27.0 release tag (`8a8a9aa`); v1.28 binary-equivalent. Re-uses the V1.27.B discover capture in `docs/calibration-cycle-24-data/post-v1.27-*.discover.txt`.

Cycle 25 is the **sixth empirical-only cycle** in the loop's history (after cycles 6, 14, 17, 20, 23).

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
| 23 (v1.26) | 114 | −90.23% (carry; v1.26 zero Sources/ change) |
| 24 (v1.27) | 113 | −90.32% |
| **25 (v1.28)** | **113** | **−90.32%** (carry; v1.28 zero Sources/ change) |

## Per-template per-corpus composition (post-v1.27)

Recounted from the four `post-v1.27-*.discover.txt` files using `^Template:` line counts and the `Lifted from \`mutating func` marker to split lifted vs non-lifted variants.

| Template | Algo | OC | CM | PLK | Total |
|---|---:|---:|---:|---:|---:|
| round-trip | 0 | 4 | 8 | 0 | **12** |
| idempotence (non-lifted) | 3 | 1 | 0 | 1 | **5** |
| idempotence-lifted | 0 | 7 | 0 | 0 | **7** |
| monotonicity | 3 | 20 | 0 | 6 | **29** |
| commutativity | 1 | 10 | 6 | 0 | **17** |
| associativity | 1 | 10 | 6 | 0 | **17** |
| inverse-pair | 0 | 2 | 0 | 0 | **2** |
| identity-element | 0 | 0 | 1 | 0 | **1** |
| dual-style-consistency | 0 | 22 | 0 | 0 | **22** |
| composition (lifted) | 0 | 1 | 0 | 0 | **1** |
| **Total** | **8** | **77** | **21** | **7** | **113** |

Header-counts cross-check: Algo "8 suggestions" + OC "77 suggestions" + CM "21 suggestions" + PLK "7 suggestions" = 113. ✓

## Drift vs cycle-23's recorded composition

Cycle-23's `surface-counts.md` table (post-v1.25, 114-surface) recorded idempotence-lifted = 9 (Algo 5, OC 4) and idempotence non-lifted = 3 (OC 2, PLK 1). The v1.27 recount above shows idempotence-lifted = 7 (OC only) and idempotence non-lifted = 5 (Algo 3, OC 1, PLK 1). Two contributing factors:

1. **Cycle-23 mislabelled the Algo idempotence picks.** The 3 Algo idempotence survivors (`endOfChunk(startingAt:)`, `startOfChunk(endingAt:)`, `sizeOfChunk(offset:)`) are **non-lifted** `T -> T` shapes, not lifted from mutating methods — cycle-23's surface-counts.md erroneously bucketed them under idempotence-lifted. Reclassified here.
2. **V1.27.A closed -1 OC inverse-pair pick** (cycle-23 plan-vs-actual variance from sample-manifest enumeration error; documented in cycle-24 findings).

Net: 114 → 113 (-1 actual surface delta). All other per-corpus per-template counts unchanged between v1.25 and v1.27.

## Surviving idempotence non-lifted (5 picks)

Post-V1.25.A's index-advance name-prefix gate + V1.24.D's capacity/formatter veto + V1.27.A's Sequence-conformance fallback, the surviving idempotence non-lifted pool:

- 3 Algo chunk-offset picks (`endOfChunk(startingAt:)`, `startOfChunk(endingAt:)`, `sizeOfChunk(offset:)`) — stride-style label demotion (V1.22.D, -15) doesn't fire here; these are `T -> T` over `Base.Index`/`Int`.
- 1 OC `firstOccupiedBucketInChain(with:)` carry-forward (cycle-17/20/23 unknown).
- 1 PLK `nearMissLines(_:)` (cycle-17/20/23 unknown).

Five-pick pool is up from cycle-23's 3-pick claim (which under-reported the Algo chunk methods). Sample at V1.28.C: full coverage (all 5).

## Surviving idempotence-lifted (7 picks; all OC)

All 7 are OC mutating-method lifts on OrderedSet / OrderedDictionary / OrderedDictionary.Elements value-semantic carriers:

- 3 Strong-tier sorts: `OrderedDictionary.Elements.sort()`, `OrderedDictionary.sort()`, `OrderedSet.sort()` (score 85; curated 'sort' verb match +40).
- 4 Likely-tier internal helpers: `OrderedSet._regenerateHashTable()`, `_regenerateExistingHashTable()`, `_isUnique()`, `_ensureUnique()` (score 45; lift bonus +10).

Sample at V1.28.C: 6 of 7 picks per cycle-23 stratification.

## Surviving inverse-pair (2 picks; both OC)

Post-V1.27.B's name-prefix-gated full-veto closed the `bucket(after:) × bucket(before:)` cycle-23 finding (-1). Surviving pairs are the two `index(after:) × index(before:)` OC inverse-pairs (one on OrderedSet, one on OrderedDictionary). V1.27.B's name-prefix gate would full-veto these too — but they're still present, meaning the gate either didn't fire on them or the pre-existing V1.11.1 either-side -20 counter resolves them differently. Verify at V1.28.C triage.

Sample at V1.28.C: full coverage (both picks).

## Stratification for V1.28.C

Sample 40 picks across the 10 template classes (with minor adjustments to match the recounted distribution):

| Template | v1.27 surface | Sample |
|---|---:|---:|
| round-trip | 12 | 6 |
| idempotence (non-lifted) | 5 | 5 (full coverage) |
| idempotence-lifted | 7 | 6 |
| monotonicity | 29 | 4 |
| commutativity | 17 | 3 |
| associativity | 17 | 3 |
| inverse-pair | 2 | 2 (full coverage) |
| identity-element | 1 | 1 (full coverage) |
| dual-style-consistency | 22 | 5 |
| composition (lifted) | 1 | 1 (full coverage) |
| **Total** | **113** | **36** |

Adjustment from v1.28 plan sketch (40 picks): the 4 newly-recovered surface picks went into the non-lifted-idempotence pool (5 vs planned 3, full-coverage absorbs the extra 2) and the lifted-idempotence pool dropped (7 vs planned 9, sample 6 vs 6 unchanged). Net sample size: 36 (vs planned 40) — slightly smaller but still within the cycle-17/20/23 framework (37 / 32 / 37 actual samples after exclusions).

See [`sample-manifest.md`](sample-manifest.md) (committed at V1.28.C).
