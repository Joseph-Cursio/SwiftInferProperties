# Cycle-17 Triage Sample Manifest

**Captured:** 2026-05-10 against the v1.19.0 release tag (`7b50512`).
**Source:** post-V1.19.0 surface across the 4 cycle-1+...+14 corpora — total 335 suggestions ([`surface-counts.md`](surface-counts.md)).
**Sample size:** 46 decisions stratified by template × corpus per V1.20.A's rebased table.
**Rater:** single-runner (Claude); see [`../cycle-17-triage-rubric.md`](../cycle-17-triage-rubric.md) for the methodology + caveats.

## Why these 46

Stratified to ensure each template surface gets enough decisions to compute a per-template acceptance rate. The cumulative v1.18 + v1.19 surface introduces three new candidate classes — `dual-style-consistency` (V1.18.C), `idempotence-lifted` + `composition-lifted` + `identity-element-lifted` + `inverse-pair-lifted` (V1.19.B–D). Sample size is 46, not 50 (cycle-6 + cycle-14): two of the new lifted sub-templates surfaced **zero** candidates on the four corpora (`identity-element-lifted`, `inverse-pair-lifted`) and `composition-lifted` had only 1 candidate (full coverage at 1/1). The freed picks are not redistributed — existing classes are already adequately sampled at cycle-14-comparable weights.

Methodology delta vs cycles 6 + 14 is documented in [`../cycle-17-triage-rubric.md`](../cycle-17-triage-rubric.md) §"Cycle-17 vs cycle-14 vs cycle-6 methodology delta". Per-template criteria for the 7 cycle-14-baseline templates are verbatim from cycle 14; new sections for dual-style + lifted sub-class.

## Stratification matrix

| Template | v1.19 surface | Sample | OC | CM | Algo | PLK | Cycle-14 sample (for comparison) |
|---|---:|---:|---:|---:|---:|---:|---:|
| round-trip | 156 | **15** | 4 | 10 | 1 | 0 | 20 |
| idempotence (non-lifted) | 44 | **6** | 2 | 3 | 0 | 1 | 12 |
| commutativity | 17 | **3** | 1 | 2 | 0 | 0 | 5 |
| associativity | 17 | **3** | 1 | 2 | 0 | 0 | 5 |
| monotonicity | 29 | **4** | 2 | 0 | 1 | 1 | 6 |
| inverse-pair (non-lifted) | 4 | **2** | 1 | 0 | 1 | 0 | 1 |
| identity-element (non-lifted) | 1 | **1** | 0 | 1 | 0 | 0 | 1 |
| **dual-style-consistency** (NEW v1.18.C) | 22 | **5** | 5 | 0 | 0 | 0 | n/a |
| **idempotence-lifted** (NEW v1.19.B) | 44 | **6** | 3 | 0 | 3 | 0 | n/a |
| **composition-lifted** (NEW v1.19.C) | 1 | **1** | 1 | 0 | 0 | 0 | n/a |
| **identity-element-lifted** (NEW v1.19.C) | 0 | 0 | 0 | 0 | 0 | 0 | n/a |
| **inverse-pair-lifted** (NEW v1.19.D) | 0 | 0 | 0 | 0 | 0 | 0 | n/a |
| **Total** | **335** | **46** | **20** | **18** | **6** | **2** | **50** |

The single composition-lifted pick is full coverage of the 1-candidate v1.19 surface — `_HashTable.BucketIterator.advance(until:)`. The single identity-element pick is the carry-forward `rescaledDivide(_:_:) × Complex.zero` survivor (cycle-6 #50, cycle-14 #50).

**Per-corpus weight shift vs cycle 14:** OC 12 → 20 (+8; OC surface jumped 43 → 126 driven by V1.18.C dual-style + V1.19.B idempotence-lifted), CM 28 → 18 (−10; redistribution to make room for new classes; CM surface byte-stable at 166), Algo 7 → 6 (−1; Algo surface up 13 → 36 from lifted-Iterator class), PLK 3 → 2 (−1; minor reduction).

## Sample-selection method

Within each (template, corpus) cell:

1. **Diversity preference.** Pick suggestions that cover different source files when possible.
2. **Cross-corpus rate-stability anchors.** CM round-trip canonical inverse pairs (`exp×log`, `cos×acos`, `sin×asin`, `tan×atan`, `cosh×acosh`, `sinh×asinh`, `tanh×atanh`) carry forward from cycle-6/cycle-14 picks for direct rate-comparison. CM cross-product noise picks (`exp×cosh`, `exp×sqrt`, `log×sqrt`) likewise.
3. **Single-candidate cells take the candidate.** CM identity-element (1), composition-lifted (1), Algo inverse-pair (1) are forced picks.
4. **Idempotence-lifted sub-corpus split.** 3 Algo (Iterator-class, predicted high-rejection) + 3 OC (variety: BucketIterator, internal CoW helper, hash-table regenerator) deliberately samples both predicted-reject and predicted-accept lifted sub-classes so the per-construction precision can be measured.
5. **Dual-style sample diversity.** All 5 picks on OC; one each from the four canonical SetAlgebra dual-pair operations (`formUnion`/`union`, `formIntersection`/`intersection`, `formSymmetricDifference`/`symmetricDifference`, `subtract`/`subtracting`) plus one OrderedDictionary `merge`/`merging` to span both new naming-rule sub-families (form-prefix on OS + active/-ing on OD).
6. **First-N from sorted output where multiple are equally diverse.** Sort by `(file, line)` ordering of the V1.20.A capture.
7. **Fresh sampling, not cycle-14-picks reuse.** Resolves v1.20 plan §"Open decisions" #4 in favor of (a). Some natural overlap occurs (e.g., the lone Algo inverse-pair survivor and the lone CM identity-element are the same survivors as cycle-14 picks #49 + #50 — the only candidates available); the per-pick verdict is re-derived freshly here.

## Sample listing

Full per-decision detail + rationale lives in [`triage-notes.md`](triage-notes.md); machine-readable decisions in [`triage-decisions.json`](triage-decisions.json). This manifest gives the index.

### round-trip (15)

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 1 | OC | `_value(forBucketContents:)` ↔ `_bucketContents(for:)` (_HashTable+UnsafeHandle.swift:201/219) | Codec pair — cycle-14 #1 (accept) rate-stability. |
| 2 | OC | `bucket(after:)` ↔ `bucket(before:)` (_HashTable+UnsafeHandle.swift:137/149) | Direction-pair on Bucket — cycle-9 V1.12.1 direction-counter applied at -15; pair surfaces at score 25; not a true inverse pair (both forward index ops). |
| 3 | OC | `index(after:)` ↔ `index(before:)` (OrderedDictionary+Elements.SubSequence.swift:206/220) | Direction-pair on Int — same shape as #2 across the OD namespace. |
| 4 | OC | `index(after:)` ↔ `_minimumCapacity(forScale:)` (RandomAccessCollection.swift:119 / OS+Testing.swift:39) | Cross-file confused pair — cross-product of unrelated functions. Predicted reject. |
| 5 | CM | `exp(_:)` ↔ `log(_:)` (Complex+ElementaryFunctions.swift:56/231) | Genuine canonical inverse pair (principal branch). Cycle-14 #5 (accept). |
| 6 | CM | `cosh(_:)` ↔ `acosh(_:)` (141/387) | Genuine inverse pair (principal branch). Cycle-14 #9 (accept). |
| 7 | CM | `sinh(_:)` ↔ `asinh(_:)` (171/396) | Genuine inverse pair. Cycle-14 #10 (accept). |
| 8 | CM | `tanh(_:)` ↔ `atanh(_:)` (187/402) | Genuine inverse pair. Cycle-14 #11 (accept). |
| 9 | CM | `cos(_:)` ↔ `acos(_:)` (211/364) | Genuine inverse pair. Cycle-14 #12 (accept). |
| 10 | CM | `sin(_:)` ↔ `asin(_:)` (217/372) | Genuine inverse pair. Cycle-14 #13 (accept). |
| 11 | CM | `tan(_:)` ↔ `atan(_:)` (224/381) | Genuine inverse pair. Cycle-14 #14 (accept). |
| 12 | CM | `exp(_:)` ↔ `cosh(_:)` (56/141) | Cross-product (forward-forward exponential-family). Cycle-14 #3 (reject). |
| 13 | CM | `exp(_:)` ↔ `sqrt(_:)` (56/442) | Cross-product. Cycle-14 #6 (reject). |
| 14 | CM | `log(_:)` ↔ `sqrt(_:)` (231/442) | Cross-product. Cycle-14 #16 (reject). |
| 15 | Algo | `endOfChunk(startingAt:)` ↔ `startOfChunk(endingAt:)` (Chunked.swift:79/122) | Lone surviving Algo round-trip. Stride-style label pair. Same site as inverse-pair #32. Cycle-14 #19 (accept). |

### idempotence (non-lifted) (6)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 16 | OC | `_description(type:) (String) -> String` (_HashTable+CustomStringConvertible.swift:29) | Cycle-14 #21 (reject) — formatter wraps input. |
| 17 | OC | `firstOccupiedBucketInChain(with:) (Bucket) -> Bucket` (_HashTable+UnsafeHandle.swift:325) | Cycle-14 #22 (unknown) — bucket-chain seek; rate-stability check on the unknown verdict. |
| 18 | CM | `exp(_:) (Complex) -> Complex` (Complex+ElementaryFunctions.swift:56) | Cycle-14 #23 (reject). |
| 19 | CM | `log(_:) (Complex) -> Complex` (Complex+ElementaryFunctions.swift:231) | Cycle-14 #24 (reject). |
| 20 | CM | `sqrt(_:) (Complex) -> Complex` (Complex+ElementaryFunctions.swift:442) | Cycle-14 #28 (reject) — fixed-point only. |
| 21 | PLK | `nearMissLines(_:) ([String]?) -> [String]?` (ViolationFormatter.swift:58) | Cycle-14 #32 (unknown). |

### commutativity (3)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 22 | OC | `index(_:offsetBy:) (Int, Int) -> Int` (OrderedDictionary+Elements.SubSequence.swift:263) | Cycle-14 #33 (reject). |
| 23 | CM | `-(z:w:) (Complex, Complex) -> Complex` (Complex+AdditiveArithmetic.swift:29) | Subtraction — anti-commutative. Cycle-14 #36 (reject). |
| 24 | CM | `_relaxedAdd(_:_:) (Self, Self) -> Self` (Complex+AlgebraicField.swift:171) | Internal relaxed-precision addition — abstractly commutative. Cycle-14 #37 (accept). |

### associativity (3)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 25 | OC | `index(_:offsetBy:) (Int, Int) -> Int` (OrderedDictionary+Elements.SubSequence.swift:263) | Same site as #22 — measure cross-template (commutativity-no / associativity-yes) rater consistency. Cycle-14 #38 (accept). |
| 26 | CM | `/(z:w:) (Complex, Complex) -> Complex` (Complex+AlgebraicField.swift:37) | Division — non-associative. Cycle-14 #41 (reject). |
| 27 | CM | `_relaxedMul(_:_:) (Self, Self) -> Self` (Complex+AlgebraicField.swift:176) | Cycle-14 #42 (accept). |

### monotonicity (4)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 28 | OC | `_minimumCapacity(forScale:) (Int) -> Int` (OrderedSet+Testing.swift:39) | Capacity-from-scale — genuinely monotonic. Cycle-14 #43 (accept) on the same name in `_HashTable+Constants.swift`. |
| 29 | OC | `index(after:) (Int) -> Int` (OrderedSet+RandomAccessCollection.swift:119) | Index increment — strictly monotonic on Int. |
| 30 | Algo | `sizeOfChunk(offset:) (Int) -> Int` (Chunked.swift:243) | Cycle-14 #46 (reject) — query-based size lookup, non-linear. |
| 31 | PLK | `walkCap(for:) (C) -> Int` (BidirectionalCollectionLaws.swift:237) | Cycle-14 #47 (accept) — collection-bounded count. |

### inverse-pair (non-lifted) (2)

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 32 | Algo | `endOfChunk(startingAt:)` ↔ `startOfChunk(endingAt:)` (Chunked.swift:79/122) | Same pair as round-trip #15. Cycle-14 #49 (accept). |
| 33 | OC | `bucket(after:)` ↔ `bucket(before:)` (_HashTable+UnsafeHandle.swift:137/149) | NEW v1.19 pick — direction-pair surfaces on inverse-pair template (V1.18.A carrier-kind +5 on `_HashTable.UnsafeHandle` value-semantic struct). Cycle-9 V1.11.1 direction-counter applied at -10; surfaces at score 25. Predicted reject (same shape as round-trip #2). |

### identity-element (non-lifted) (1)

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 34 | CM | `rescaledDivide(_:_:) × Complex.zero` (Complex+AlgebraicField.swift:48 / Complex+AdditiveArithmetic.swift:19) | Carry-forward Score 70 Likely-tier survivor (cycle-6 #50, cycle-14 #50; both reject). Rate-stability check on this lone identity-element across all cycles. |

### dual-style-consistency (5) — NEW v1.18.C

All 5 picks on OC (the only corpus with surface). Cycle-17 first measurement of the new template family; no prior baseline.

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 35 | OC | `OrderedSet.formUnion(_: __owned Self)` ↔ `OrderedSet.union(_: __owned Self) -> Self` (OS+Partial SetAlgebra formUnion.swift:44 / union.swift:38) | Canonical SetAlgebra form-prefix dual pair. By-construction Strong (75 with carrier signal); per-construction precision predicted high. |
| 36 | OC | `OrderedSet.formIntersection(_: Self)` ↔ `OrderedSet.intersection(_: Self) -> Self` (formIntersection.swift:40 / intersection.swift:46) | SetAlgebra dual. |
| 37 | OC | `OrderedSet.formSymmetricDifference(_: __owned Self)` ↔ `OrderedSet.symmetricDifference(_: __owned Self) -> Self` (formSymmetricDifference.swift:40 / symmetricDifference.swift:45) | SetAlgebra dual. |
| 38 | OC | `OrderedSet.subtract(_: Self)` ↔ `OrderedSet.subtracting(_: Self) -> Self` (subtract.swift:37 / subtracting.swift:45) | SetAlgebra dual (subtract is the form-less variant). |
| 39 | OC | `OrderedDictionary.merge(_:uniquingKeysWith:)` ↔ `OrderedDictionary.merging(_:uniquingKeysWith:) -> Self` (OrderedDictionary.swift:826/922) | Active/-ing dual pair (different naming rule from the four SetAlgebra picks above; `merge`/`merging` is canonical Swift dict merging convention). |

### idempotence-lifted (6) — NEW v1.19.B

Sub-corpus split: 3 Algo + 3 OC. The two sub-corpora have very different precision priors per the V1.20.A surface analysis (Algo Iterator-shape predicted high-reject; OC mix of Iterator + internal terminal mutators predicted mixed).

| # | Corpus | Lifted shape | Why included |
|---|---|---|---|
| 40 | Algo | `mutating func AdjacentPairsSequence.Iterator.next()` lifted to `(Iterator) -> Iterator` (AdjacentPairsSequence.swift, Iterator.next site) | First Algo Iterator pick — the per-construction prediction class (next() advances state). |
| 41 | Algo | `mutating func CombinationsIterator.next()` lifted (Combinations.swift) | Second Algo Iterator pick — different Iterator type, same shape; coverage check. |
| 42 | Algo | `mutating func ChunkedIterator.advance()` lifted (Chunked.swift) | Algo `advance()` rather than `next()` — name variant of the Iterator-shape class. |
| 43 | OC | `mutating func _HashTable.BucketIterator.advance()` lifted (_HashTable+BucketIterator.swift) | OC Iterator-shape pick — parallel to Algo Iterator picks; predicted reject. |
| 44 | OC | `mutating func OrderedSet._isUnique()` lifted (OrderedSet.swift internal CoW) | Internal copy-on-write uniqueness helper. Predicted accept (calling twice = once on already-unique storage). |
| 45 | OC | `mutating func OrderedSet._regenerateHashTable()` lifted (OrderedSet.swift internal hash-rebuild) | Hash-table rebuild from scratch. Predicted accept (regenerating twice produces identical state). |

### composition-lifted (1) — NEW v1.19.C

Full coverage of the 1-candidate v1.19 surface.

| # | Corpus | Lifted shape | Why included |
|---|---|---|---|
| 46 | OC | `mutating func _HashTable.BucketIterator.advance(until: Int) -> Void` lifted to `(BucketIterator, Int) -> BucketIterator` (_HashTable+BucketIterator.swift:252) | Sole composition-lifted pick on the v1.19 surface. Curated additive-action verb 'advance' (+40); type-shape (BucketIterator, Int) -> BucketIterator (+30); carrier value-semantic (+5); lift admission (+10) = Strong. Predicted reject — `advance(until:)` is monotone-bounded, not additive. |

## Notes on coverage

- **OrderedCollections (20)** — Dominates the v1.19 surface (126/335 = 37.6%). 20 picks span 9 distinct source files across OrderedSet + OrderedDictionary + _HashTable. New-class concentration: 5 dual-style + 4 lifted-idempotence-or-composition.
- **ComplexModule (18)** — CM surface byte-stable at 166. 10 round-trip + 3 idempotence + 2 commutativity + 2 associativity + 1 identity-element. CM contributed zero new-class picks (no lifted candidates surfaced; no dual-style candidates).
- **Algorithms (6)** — Algo surface jumped 13 → 36 mostly from lifted-Iterator class. 3 idempotence-lifted + 1 round-trip + 1 inverse-pair + 1 monotonicity. The 3 lifted-Iterator picks measure the predicted V1.19.B over-broad-admission class.
- **PropertyLawKit (2)** — minor sample reduction (3 → 2) reflects PLK surface stability at 7 candidates.
- **Score-tier mix:** 45 Possible-tier picks + 1 Likely-tier pick (the identity-element survivor; carry-forward).
- **Cross-template same-site coverage:** picks #15 + #32 share `endOfChunk(startingAt:)` (round-trip + inverse-pair); picks #2 + #33 share `bucket(after:)`/`bucket(before:)` (round-trip + inverse-pair); picks #22 + #25 share `index(_:offsetBy:)` (commutativity + associativity); picks #43 + #46 share `BucketIterator` (idempotence-lifted + composition-lifted). These are 4 site-pairs producing 8 distinct decisions.
- **Predicted-rate framing.** Per the rubric's per-construction precision analysis: dual-style 5/5 = 100% (canonical SetAlgebra structural dualities); composition-lifted 0/1 = 0% (over-broad on monotone-bounded mutators); idempotence-lifted Algo 0/3 = 0% (Iterator-shape over-broad); idempotence-lifted OC 2/3 = 67% (mix of Iterator + internal-CoW); existing 7-template carry-forwards roughly aligned with cycle-14 rates.
