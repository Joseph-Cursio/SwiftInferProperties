# Cycle-23 Triage Sample Manifest

**Captured:** 2026-05-10 against the v1.25.0 release tag.
**Source:** post-V1.25.0 surface across the 4 cycle-1..14 corpora — 114 suggestions ([`surface-counts.md`](surface-counts.md); v1.25 capture in [`../calibration-cycle-22-data/`](../calibration-cycle-22-data/)).
**Sample size:** 40 (vs cycle-20's 46; reflects v1.25's smaller surface).
**Rater:** single-runner (Claude); see [`../cycle-23-triage-rubric.md`](../cycle-23-triage-rubric.md).

## Stratification matrix

| Template | v1.25 surface | Sample | OC | CM | Algo | PLK |
|---|---:|---:|---:|---:|---:|---:|
| round-trip | 12 | **6** | 2 | 4 | 0 | 0 |
| idempotence (non-lifted) | 3 | **3** | 2 | 0 | 0 | 1 |
| idempotence-lifted | 9 | **6** | 4 | 0 | 2 | 0 |
| commutativity | 17 | **3** | 1 | 2 | 0 | 0 |
| associativity | 17 | **3** | 1 | 2 | 0 | 0 |
| monotonicity | 29 | **4** | 2 | 0 | 1 | 1 |
| inverse-pair | 3 | **2** | 2 | 0 | 0 | 0 |
| identity-element | 1 | **1** | 0 | 1 | 0 | 0 |
| dual-style-consistency | 22 | **5** | 5 | 0 | 0 | 0 |
| composition (lifted) | 1 | **1** | 1 | 0 | 0 | 0 |
| **Total** | **114** | **40** | **20** | **9** | **3** | **2** |

## Sample listing

### round-trip (6)

| # | Corpus | Pair | Why |
|---|---|---|---|
| 1 | CM | `exp × log` | Canonical inverse anchor (cycles 14/17/20 accept) |
| 2 | CM | `cos × acos` | Canonical inverse |
| 3 | CM | `sin × asin` | Canonical inverse |
| 4 | CM | `tan × atan` | Canonical inverse |
| 5 | OC | `_value(forBucketContents:) × _bucketContents(for:)` codec | Codec (cycles 14/17/20 accept) |
| 6 | OC | `bucket(after:) × bucket(before:)` | Direction-pair survivor (cycle-17/20 reject rate-stability) |

### idempotence (non-lifted) (3) — full coverage

| # | Corpus | Function | Why |
|---|---|---|---|
| 7 | OC | `firstOccupiedBucketInChain(with:)` | Cycle-17/20 unknown rate-stability |
| 8 | OC | (residual carry-forward) | Survivor post-V1.25.A |
| 9 | PLK | `nearMissLines(_:)` | Cycle-17/20 unknown rate-stability |

### idempotence-lifted (6)

| # | Corpus | Lifted shape | Why |
|---|---|---|---|
| 10 | OC | `OrderedSet._isUnique()` | Cycle-17/20 accept rate-stability |
| 11 | OC | `OrderedSet._regenerateHashTable()` | Cycle-17/20 accept rate-stability |
| 12 | OC | `OrderedDictionary.sort()` | Cycle-20 accept rate-stability |
| 13 | OC | `OrderedSet.sort()` | Cycle-20 accept rate-stability |
| 14 | Algo | Algo Iterator-like survivor #1 | Survivor post-V1.21.A/V1.22.A |
| 15 | Algo | Algo Iterator-like survivor #2 | Same |

### commutativity (3)

| # | Corpus | Function | Why |
|---|---|---|---|
| 16 | OC | `index(_:offsetBy:)` | Cycle-17/20 reject rate-stability |
| 17 | CM | `-(z:w:)` | Cycle-17/20 reject rate-stability |
| 18 | CM | `_relaxedAdd(_:_:)` | Cycle-17/20 accept rate-stability |

### associativity (3)

| # | Corpus | Function | Why |
|---|---|---|---|
| 19 | OC | `index(_:offsetBy:)` | Cycle-17/20 accept rate-stability |
| 20 | CM | `/(z:w:)` | Cycle-17/20 reject rate-stability |
| 21 | CM | `_relaxedMul(_:_:)` | Cycle-17/20 accept rate-stability |

### monotonicity (4)

| # | Corpus | Function | Why |
|---|---|---|---|
| 22 | OC | `_minimumCapacity(forScale:)` | Cycle-17/20 accept rate-stability |
| 23 | OC | `index(after:)` | Cycle-17/20 accept rate-stability |
| 24 | Algo | `sizeOfChunk(offset:)` | Cycle-17/20 reject rate-stability |
| 25 | PLK | `walkCap(for:)` | Cycle-17/20 accept rate-stability |

### inverse-pair (2)

| # | Corpus | Pair | Why |
|---|---|---|---|
| 26 | OC | `bucket(after:) × bucket(before:)` | Cycle-17/20 reject rate-stability |
| 27 | OC | `word(after:) × word(before:)` | Cycle-20 reject rate-stability |

### identity-element (1)

| # | Corpus | Pair | Why |
|---|---|---|---|
| 28 | CM | `rescaledDivide × Complex.zero` | Cycles 6/14/17/20 reject rate-stability (lone outlier across all cycles) |

### dual-style-consistency (5)

| # | Corpus | Pair | Why |
|---|---|---|---|
| 29 | OC | `OrderedSet.formUnion × union` | Cycle-17/20 accept rate-stability |
| 30 | OC | `OrderedSet.formIntersection × intersection` | Cycle-17/20 accept |
| 31 | OC | `OrderedSet.formSymmetricDifference × symmetricDifference` | Cycle-17/20 accept |
| 32 | OC | `OrderedSet.subtract × subtracting` | Cycle-17/20 accept |
| 33 | OC | `OrderedDictionary.merge × merging` | Cycle-17/20 accept |

### composition-lifted (1)

| # | Corpus | Lifted shape | Why |
|---|---|---|---|
| 34 | OC | `BucketIterator.advance(until:)` | Cycle-17/20 reject rate-stability (V1.21.B Strong → Likely demote) |

### Remaining picks (35-40) — additional rate-stability + coverage

| # | Corpus | Template / Function | Why |
|---|---|---|---|
| 35 | OC | round-trip (asymmetric survivor if any) | Coverage |
| 36 | OC | idempotence-lifted (4th OC pick: ~_ensureUnique / regenerateExistingHashTable) | Coverage of remaining lifted survivors |
| 37 | OC | monotonicity (2nd OC: `index(after:)` other namespace) | Coverage |
| 38 | OC | dual-style 6th (UnorderedView variant if present) | Coverage |
| 39 | CM | round-trip (canonical 5th or numerics-extension) | Canonical anchor coverage |
| 40 | PLK | monotonicity 2nd PLK pick | Coverage |

40 picks total. Sampling rate 35% of v1.25's 114 surface.
