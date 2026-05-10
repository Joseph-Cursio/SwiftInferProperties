# Cycle-20 Triage Sample Manifest

**Captured:** 2026-05-10 against the v1.22.0 release tag; v1.23 binary-equivalent.
**Source:** post-V1.22.0 surface across the 4 cycle-1+...+14 corpora — 152 suggestions ([`surface-counts.md`](surface-counts.md); v1.22 capture in [`../calibration-cycle-19-data/`](../calibration-cycle-19-data/)).
**Sample size:** 46 decisions stratified by template × corpus per V1.23.A (matching cycle-17's 46-pick sample size for direct comparability).
**Rater:** single-runner (Claude); see [`../cycle-20-triage-rubric.md`](../cycle-20-triage-rubric.md) for the methodology + caveats.

## Why these 46

Stratified to match cycle-17's sample-size for direct rate-comparability. The v1.22 surface (152) is smaller than cycle-17's 335; cycle-20 sampling rate is 30% (vs cycle-17's 14%). Concentrates on:

- **Cycle-17 rate-stability picks** on the surviving CM canonical-inverse anchors (4) + OC codec (1) + lifted internal-CoW (2) + dual-style (5) + identity-element (1) — these are the cycle-17 ACCEPT classes preserved at v1.22.
- **First-measurement picks** on the cycle-19 finding classes — the OC asymmetric round-trip cross-pair class (5 picks) and the OC sort/shuffle/reverse/removeFirst/removeLast idempotence-lifted sub-class (7 picks; cycle-17 sampled the BucketIterator class which V1.22.A subsequently closed).
- **Carry-forward Likely-tier outliers**: the lone CM identity-element survivor + the lone composition-lifted (V1.21.B-demoted from cycle-17's reject).

## Stratification matrix

| Template | v1.22 surface | Sample | OC | CM | Algo | PLK | Cycle-17 sample (for comparison) |
|---|---:|---:|---:|---:|---:|---:|---:|
| round-trip | 18 | **11** | 6 | 5 | 0 | 0 | 15 |
| idempotence (non-lifted) | 23 | **7** | 5 | 0 | 0 | 2 | 6 |
| commutativity | 17 | **3** | 1 | 2 | 0 | 0 | 3 |
| associativity | 17 | **3** | 1 | 2 | 0 | 0 | 3 |
| monotonicity | 29 | **4** | 2 | 0 | 1 | 1 | 4 |
| inverse-pair (non-lifted) | 3 | **2** | 2 | 0 | 0 | 0 | 2 |
| identity-element (non-lifted) | 1 | **1** | 0 | 1 | 0 | 0 | 1 |
| **dual-style-consistency** | 22 | **5** | 5 | 0 | 0 | 0 | 5 |
| **idempotence-lifted** | 21 | **9** | 9 | 0 | 0 | 0 | 6 |
| **composition-lifted** | 1 | **1** | 1 | 0 | 0 | 0 | 1 |
| **Total** | **152** | **46** | **32** | **10** | **1** | **3** | **46** |

**Per-corpus weight shift vs cycle 17:** OC 20 → 32 (+12; OC dominates the v1.22 surface at 75%; sample concentrates on OC asymmetric cross-pair + sort/shuffle/reverse first-measurement classes), CM 18 → 10 (-8; V1.21.C closed CM elementary-functions noise + idempotence non-lifted; the surviving CM round-trip is the canonical-inverse class only), Algo 6 → 1 (-5; V1.22.D Algo `endOfChunk × startOfChunk` closures + V1.21.A Iterator closures shrunk Algo to 10 surface), PLK 2 → 3 (+1; PLK byte-stable; minor sample increment).

## Sample-selection method

Within each (template, corpus) cell:

1. **Rate-stability anchor preservation.** Cycle-17 ACCEPT classes (CM canonical anchors, OC codec, dual-style, idempotence-lifted internal-CoW) sampled at cycle-17 rates for direct rate-comparability.
2. **First-measurement on new sub-classes.** Cycle-19 findings identified two classes that weren't sampled at cycle-17: OC asymmetric round-trip cross-pairs (V1.22.B variance source) and OC sort/shuffle/reverse idempotence-lifted (cycle-17 sampled BucketIterator instead, which V1.22.A subsequently closed). Cycle-20 samples each densely (5 + 7 picks respectively) for tight first-measurement.
3. **Single-candidate cells take the candidate.** CM identity-element (1), composition-lifted (1) are forced picks.
4. **Diversity within a template-corpus cell.** Sample picks across different source files when possible.
5. **Fresh sampling, not cycle-17-picks reuse.** Resolves v1.23 plan §"Open decisions" #4 in favor of (a). Some natural overlap (the lone CM identity-element survivor); per-pick verdict is re-derived.

## Sample listing

Full per-decision detail + rationale lives in [`triage-notes.md`](triage-notes.md); machine-readable decisions in [`triage-decisions.json`](triage-decisions.json). This manifest gives the index.

### round-trip (11)

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 1 | CM | `exp(_:)` × `log(_:)` (Complex+ElementaryFunctions.swift:56/231) | Canonical inverse pair. Cycle-17 #5 (accept) rate-stability. |
| 2 | CM | `cos(_:)` × `acos(_:)` (211/364) | Canonical inverse. Cycle-17 #9 (accept). |
| 3 | CM | `sin(_:)` × `asin(_:)` (217/372) | Canonical inverse. Cycle-17 #10 (accept). |
| 4 | CM | `tan(_:)` × `atan(_:)` (224/381) | Canonical inverse. Cycle-17 #11 (accept). |
| 5 | CM | `expMinusOne(_:)` × `log(onePlus:)` (71/331) | Numerics-extension pair preserved by V1.21.C `canonicalInversePairs` allowlist (NEW v1.22 sample). |
| 6 | OC | `_value(forBucketContents:)` × `_bucketContents(for:)` (_HashTable+UnsafeHandle.swift:201/219) | Codec pair. Cycle-14 #1 / cycle-17 #1 (accept). |
| 7 | OC | `index(after:)` × `_minimumCapacity(forScale:)` (RandomAccessCollection.swift:119 / Testing.swift:39) | Cycle-19 finding asymmetric cross-pair (FIRST cycle-20 measurement). |
| 8 | OC | `index(after:)` × `_maximumCapacity(forScale:)` (119 / 45) | Same asymmetric class as #7. |
| 9 | OC | `index(after:)` × `_scale(forCapacity:)` (119 / 51) | Same asymmetric class. |
| 10 | OC | `index(before:)` × `_minimumCapacity(forScale:)` (133 / 39) | Mirror of #7. |
| 11 | OC | `_minimumCapacity(forScale:)` × `_maximumCapacity(forScale:)` (39 / 45) | Same-name-prefix capacity-from-scale pair (NOT codec; both forward). |

### idempotence (non-lifted) (7)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 12 | OC | `_description(type:) (String) -> String` (CustomStringConvertible.swift:29) | Cycle-17 #16 (reject) rate-stability. |
| 13 | OC | `firstOccupiedBucketInChain(with:) (Bucket) -> Bucket` (UnsafeHandle.swift:325) | Cycle-17 #17 (unknown) rate-stability. |
| 14 | OC | `_minimumCapacity(forScale:) (Int) -> Int` (Testing.swift:39) | NEW pick (capacity-from-scale; same site as round-trip #7's right-hand). |
| 15 | OC | `bucket(after:) (Bucket) -> Bucket` (UnsafeHandle.swift:137) | Direction op idempotence claim. |
| 16 | OC | `wordCount(forScale:) (Int) -> Int` (Constants.swift:97) | Capacity-from-scale variant. |
| 17 | PLK | `nearMissLines(_:) ([String]?) -> [String]?` (ViolationFormatter.swift:58) | Cycle-17 #21 (unknown) rate-stability. |
| 18 | PLK | `format(_:) (CheckResult) -> String` (ViolationFormatter.swift:10) | Formatter (cycle-14 #48 was monotonicity reject; here on idempotence). |

### commutativity (3)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 19 | OC | `index(_:offsetBy:) (Int, Int) -> Int` (OrderedDictionary+Elements.SubSequence.swift:263) | Cycle-17 #22 (reject) rate-stability. |
| 20 | CM | `-(z:w:) (Complex, Complex) -> Complex` (Complex+AdditiveArithmetic.swift:29) | Subtraction; cycle-17 #23 (reject). |
| 21 | CM | `_relaxedAdd(_:_:) (Self, Self) -> Self` (Complex+AlgebraicField.swift:171) | Cycle-17 #24 (accept). |

### associativity (3)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 22 | OC | `index(_:offsetBy:) (Int, Int) -> Int` (OrderedDictionary+Elements.SubSequence.swift:263) | Cycle-17 #25 (accept; same site as commutativity #19). |
| 23 | CM | `/(z:w:) (Complex, Complex) -> Complex` (Complex+AlgebraicField.swift:37) | Division; cycle-17 #26 (reject). |
| 24 | CM | `_relaxedMul(_:_:) (Self, Self) -> Self` (Complex+AlgebraicField.swift:176) | Cycle-17 #27 (accept). |

### monotonicity (4)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 25 | OC | `_minimumCapacity(forScale:) (Int) -> Int` (Testing.swift:39) | Cycle-17 #28 (accept). |
| 26 | OC | `index(after:) (Int) -> Int` (RandomAccessCollection.swift:119) | Cycle-17 #29 (accept). |
| 27 | Algo | `sizeOfChunk(offset:) (Int) -> Int` (Chunked.swift:243) | Cycle-17 #30 (reject). |
| 28 | PLK | `walkCap(for:) (C) -> Int` (BidirectionalCollectionLaws.swift:237) | Cycle-17 #31 (accept). |

### inverse-pair (non-lifted) (2)

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 29 | OC | `bucket(after:) × bucket(before:)` (UnsafeHandle.swift:137/149) | Cycle-17 #33 (reject). |
| 30 | OC | `word(after:) × word(before:)` (UnsafeHandle.swift:160/174) | Same shape as #29 (NEW v1.22 sample on different file). |

### identity-element (non-lifted) (1)

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 31 | CM | `rescaledDivide × Complex.zero` (Complex+AlgebraicField.swift:48 / Complex+AdditiveArithmetic.swift:19) | Cycle-6/14/17 #34 (reject) — the lone identity-element survivor across all 4 cycles. |

### dual-style-consistency (5) — V1.18.C rate-stability

All 5 picks on OC SetAlgebra dual pairs. Cycle-17 measured 5/5 = 100%; cycle-20 re-samples for rate-stability.

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 32 | OC | `OrderedSet.formUnion × union` | Cycle-17 #35 (accept). |
| 33 | OC | `OrderedSet.formIntersection × intersection` | Cycle-17 #36 (accept). |
| 34 | OC | `OrderedSet.formSymmetricDifference × symmetricDifference` | Cycle-17 #37 (accept). |
| 35 | OC | `OrderedSet.subtract × subtracting` | Cycle-17 #38 (accept). |
| 36 | OC | `OrderedDictionary.merge × merging` | Cycle-17 #39 (accept). |

### idempotence-lifted (9)

Concentrates on the two classes the cycle-19 finding identified as "first cycle-20 measurement":

- **Cycle-17 internal-CoW class (rate-stability):** 2 picks.
- **OC sort/shuffle/reverse/removeFirst/removeLast first-measurement:** 7 picks.

| # | Corpus | Lifted shape | Why included |
|---|---|---|---|
| 37 | OC | `OrderedSet._isUnique()` lifted | Cycle-17 #44 (accept) rate-stability. |
| 38 | OC | `OrderedSet._regenerateHashTable()` lifted | Cycle-17 #45 (accept) rate-stability. |
| 39 | OC | `OrderedDictionary.sort()` lifted (Partial MutableCollection.swift:126) | NEW measurement: sort produces fixed point on already-sorted; predicted accept. |
| 40 | OC | `OrderedDictionary.shuffle()` lifted (Partial MutableCollection.swift:142) | NEW measurement: non-deterministic; should be vetoed but surfaces; predicted unknown (rater can't determine why veto missed without source inspection). |
| 41 | OC | `OrderedDictionary.reverse()` lifted (Partial MutableCollection.swift:190) | NEW measurement: reverse twice = original ≠ reverse once; predicted reject. |
| 42 | OC | `OrderedDictionary.removeFirst()` lifted | NEW measurement: state advances; predicted reject. |
| 43 | OC | `OrderedDictionary.removeLast()` lifted | NEW measurement: same shape as #42. |
| 44 | OC | `OrderedSet.sort()` lifted | NEW measurement: same shape as #39. |
| 45 | OC | `OrderedSet.reverse()` lifted | NEW measurement: same shape as #41. |

### composition-lifted (1)

| # | Corpus | Lifted shape | Why included |
|---|---|---|---|
| 46 | OC | `_HashTable.BucketIterator.advance(until: Int) -> Void` lifted | Cycle-17 #46 (reject) rate-stability check on V1.21.B Strong → Likely demotion (same underlying mathematical relation; demotion is calibration response not re-classification). |

## Notes on coverage

- **OrderedCollections (32)** — Dominates the v1.22 surface (114/152 = 75%). 32 picks span 8 distinct source files. New-class concentration: 5 round-trip asymmetric + 1 round-trip codec + 5 dual-style + 7 OC sort/shuffle/reverse-class lifted-idempotence + 2 OC internal-CoW lifted = 20 of 32 OC picks.
- **ComplexModule (10)** — V1.21.C closed elementary-functions surface; surviving CM is canonical-anchor class only. 5 round-trip canonical anchors + 2 commutativity + 2 associativity + 1 identity-element.
- **Algorithms (1)** — V1.21.A + V1.22.A + V1.22.D collectively closed Algo surface from 36 to 10. Lone Algo monotonicity sample.
- **PropertyLawKit (3)** — PLK byte-stable at 7. 2 idempotence + 1 monotonicity.
- **Score-tier mix:** 44 Possible-tier picks + 2 Likely-tier (CM identity-element + composition-lifted; both carry-forwards from cycle-17).
- **Cross-template same-site coverage:** picks #7-#10 share `index(after:)` or `index(before:)` × capacity-from-scale (round-trip 4 picks; first-measurement of cycle-19 finding); picks #14 + #25 share `_minimumCapacity(forScale:)` (idempotence + monotonicity); picks #19 + #22 share `index(_:offsetBy:)` (commutativity + associativity).
- **Predicted-rate framing.** Per cycle-17 → cycle-20 expected rate-shifts:
  - round-trip: cycle-17 60% (9/15) → cycle-20 expected 50-60% (6 anchor accepts + 5 asymmetric rejects = 6/11 = 55%).
  - idempotence non-lifted: cycle-17 0% (0/4) → cycle-20 expected 0% (4-cycle flat).
  - dual-style: cycle-17 100% (5/5) → cycle-20 expected 100% (rate-stability).
  - idempotence-lifted: cycle-17 33% (2/6) → cycle-20 expected ~33% (2 internal-CoW + 1 sort + 0 shuffle (unknown) + 0 of {reverse/removeFirst/removeLast} = 3 accepts, 4 rejects, 1 unknown = 3/7 = 43%).
  - composition-lifted: cycle-17 0% (0/1) → cycle-20 expected 0% (rate-stability on V1.21.B demotion).

Aggregate projection: ~22-25 accepts / 18-21 rejects / 1-3 unknowns = aggregate **48-55%** — touches outcome B / C / D bands.
