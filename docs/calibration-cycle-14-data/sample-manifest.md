# Cycle-14 Triage Sample Manifest

**Captured:** 2026-05-09 against the v1.16.0 release tag (`9e36efd`).
**Source:** post-V1.16.1 surface across the 4 cycle-1+...+12 corpora — total 229 suggestions ([`../calibration-cycle-13-data/`](../calibration-cycle-13-data/)). v1.17 is binary-equivalent to v1.16.0.
**Sample size:** 50 decisions stratified by template × corpus.
**Rater:** single-runner (Claude); see [`../cycle-14-triage-rubric.md`](../cycle-14-triage-rubric.md) for the methodology + caveats.

## Why these 50

Stratified to ensure each template surface gets enough decisions to compute a per-template acceptance rate while keeping the rater fatigue at a single-session level. Per-cell minimum 1 (where the surface allows), per-template minimum 5 except the two single-candidate templates (inverse-pair, identity-element). Stratification mirrors cycle 6's per-template sample sizes verbatim where the v1.16 surface allows; the only deviation is **inverse-pair 5 → 1** (forced by the v1.16 surface dropping from 15 to 1 candidate post-v1.14), with the **freed 4 picks redistributed to round-trip** (where ComplexModule's 136 round-trip surface dominates the v1.16 view).

Methodology delta vs cycle 6 is documented in [`../cycle-14-triage-rubric.md`](../cycle-14-triage-rubric.md) §"Cycle-14 vs cycle-6 methodology delta". Per-template criteria are verbatim from cycle 6.

## Stratification matrix

| Template | v1.16 surface | Sample | OC | CM | Algo | PLK | Cycle-6 sample (for comparison) |
|---|---:|---:|---:|---:|---:|---:|---:|
| round-trip | 139 | **20** | 1 | 17 | 2 | 0 | 16 |
| idempotence | 25 | **12** | 2 | 6 | 3 | 1 | 12 |
| commutativity | 17 | **5** | 3 | 2 | 0 | 0 | 5 |
| associativity | 17 | **5** | 3 | 2 | 0 | 0 | 5 |
| monotonicity | 29 | **6** | 3 | 0 | 1 | 2 | 6 |
| inverse-pair | 1 | **1** | 0 | 0 | 1 | 0 | 5 |
| identity-element | 1 | **1** | 0 | 1 | 0 | 0 | 1 |
| **Total** | **229** | **50** | **12** | **28** | **7** | **3** | **50** |

The single inverse-pair pick is the post-V1.14 Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor (cycle-15 priority #1 target — stride-style label extension). The single identity-element pick is the Score 70 (Likely-tier) `rescaledDivide(_:_:)` × `Complex.zero` survivor — included because it's the only identity-element suggestion across the entire 229-surface and worth a triage call despite being at Likely tier rather than the Possible-tier focus (resolves v1.17 plan §"Open decisions" #6 in favor of (a)).

**Per-corpus weight shift vs cycle 6:** OC 22 → 12 (−10; OC surface dropped 101 → 43 across cycles 7-13), CM 15 → 28 (+13; CM surface unchanged at 166 but now dominates), Algo 10 → 7 (−3; surface dropped 75 → 13), PLK 3 → 3 (unchanged; PLK surface stable at 7).

## Sample-selection method

Within each (template, corpus) cell:

1. **Diversity preference.** Pick suggestions that cover different source files when possible, not the same file's cross-product.
2. **Cross-product representation on CM round-trip.** CM's 136-pair round-trip surface is dominated by the cross-product of elementary functions. Sample picks intentionally span the spectrum — true-inverse pairs (`log ↔ exp`, `sin ↔ asin`, etc.), numerical-variant pairs (`expMinusOne ↔ log`, the accurate-near-zero variant), and pure cross-product noise (`exp ↔ cosh`, `log ↔ sqrt`, etc.) — so the CM round-trip rate is calibrated against a representative slice rather than skewed toward one verdict class.
3. **Single-candidate cells take the candidate.** OC round-trip (1 candidate), Algo inverse-pair (1), CM identity-element (1), PLK idempotence (1) are forced picks.
4. **First-N from sorted output where multiple are equally diverse.** Sort by `(file, line)` ordering of the cycle-13 capture.
5. **Fresh sampling, not cycle-6-picks reuse.** Resolves v1.17 plan §"Open decisions" #4 in favor of (a). Some natural overlap occurs (e.g., the lone Algo inverse-pair survivor IS cycle-6 pick #15, and the lone CM identity-element IS cycle-6 pick #50 — the only candidates available); the per-pick verdict is re-derived freshly here, not copied from cycle 6's notes.

## Sample listing

Full per-decision detail + rationale lives in [`triage-notes.md`](triage-notes.md); machine-readable decisions in [`triage-decisions.json`](triage-decisions.json). This manifest gives the index.

### round-trip (20)

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 1 | OC | `_value(forBucketContents:)` ↔ `_bucketContents(for:)` (_HashTable+UnsafeHandle.swift:201/219) | Lone OC round-trip survivor at v1.16. Underscore-prefixed internal codec pair on a non-Equatable carrier (Bucket-contents UInt64). |
| 2 | CM | `exp(_:)` ↔ `expMinusOne(_:)` (Complex+ElementaryFunctions.swift:56/71) | Forward-forward exponential variants. Cycle-6 pick #7 (reject); included to measure rate stability on this canonical noise shape. |
| 3 | CM | `exp(_:)` ↔ `cosh(_:)` (56/141) | Cross-product (exponential × hyperbolic). Cycle-6 pick #8 (reject). |
| 4 | CM | `exp(_:)` ↔ `sinh(_:)` (56/171) | Cross-product (exponential × hyperbolic). |
| 5 | CM | `exp(_:)` ↔ `log(_:)` (56/231) | **Genuine canonical inverse pair on the principal branch.** Cycle-6 pick #11 (accept). |
| 6 | CM | `exp(_:)` ↔ `sqrt(_:)` (56/442) | Cross-product (exponential × root). |
| 7 | CM | `expMinusOne(_:)` ↔ `log(_:)` (71/231) | Approximate inverse on small-magnitude inputs (numerical-variant pair). |
| 8 | CM | `cosh(_:)` ↔ `sinh(_:)` (141/171) | Forward-forward hyperbolic. Cycle-6 pick #10 (reject). |
| 9 | CM | `cosh(_:)` ↔ `acosh(_:)` (141/387) | **Genuine inverse pair on principal branch.** |
| 10 | CM | `sinh(_:)` ↔ `asinh(_:)` (171/396) | **Genuine inverse pair on principal branch.** |
| 11 | CM | `tanh(_:)` ↔ `atanh(_:)` (187/402) | **Genuine inverse pair on principal branch.** |
| 12 | CM | `cos(_:)` ↔ `acos(_:)` (211/364) | **Genuine inverse pair on principal branch.** |
| 13 | CM | `sin(_:)` ↔ `asin(_:)` (217/372) | **Genuine inverse pair on principal branch.** Cycle-6 pick #12 (accept). |
| 14 | CM | `tan(_:)` ↔ `atan(_:)` (224/381) | **Genuine inverse pair on principal branch.** |
| 15 | CM | `log(_:)` ↔ `log(onePlus:)` (231/331) | Two log overloads — not inverses, both forward. |
| 16 | CM | `log(_:)` ↔ `sqrt(_:)` (231/442) | Cross-product (log × root). |
| 17 | CM | `expMinusOne(_:)` ↔ `sqrt(_:)` (71/442) | Cross-product involving accurate-variant exp. |
| 18 | CM | `atan(_:)` ↔ `atanh(_:)` (381/402) | Inverse-trig × inverse-hyperbolic — same `(Complex) -> Complex` shape, related by analytic continuation but not inverses. |
| 19 | Algo | `endOfChunk(startingAt:)` ↔ `startOfChunk(endingAt:)` (Chunked.swift:79/122) | Lone surviving Algo round-trip. Stride-style label pair (cycle-15 priority #1 target). Same site as inverse-pair pick #49 — round-trip + inverse-pair both fire. |
| 20 | Algo | `log(_:)` ↔ `log(onePlus:)` (RandomSample.swift:25/30) | Algo's only Double round-trip. Two-overload pair (parallel to CM pick #15). |

### idempotence (12)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 21 | OC | `_description(type:) (String) -> String` (_HashTable+CustomStringConvertible.swift:29) | Internal description-formatter. Output domain is human-readable string, not a normalisable input. |
| 22 | OC | `firstOccupiedBucketInChain(with:) (Bucket) -> Bucket` (_HashTable+UnsafeHandle.swift:325) | Bucket-chain seek operator — likely idempotent on already-occupied bucket input. |
| 23 | CM | `exp(_:) (Complex) -> Complex` (Complex+ElementaryFunctions.swift:56) | Exponential family. `exp(exp(z)) ≠ exp(z)`. Cycle-6 pick #21 (reject). |
| 24 | CM | `log(_:) (Complex) -> Complex` (Complex+ElementaryFunctions.swift:231) | Logarithm family. Cycle-6 pick #22 (reject). |
| 25 | CM | `sin(_:) (Complex) -> Complex` (Complex+ElementaryFunctions.swift:217) | Forward-trig family. |
| 26 | CM | `asin(_:) (Complex) -> Complex` (Complex+ElementaryFunctions.swift:372) | Inverse-trig family — measure whether the rater treats the inverse-trig consistently. |
| 27 | CM | `tanh(_:) (Complex) -> Complex` (Complex+ElementaryFunctions.swift:187) | Forward-hyperbolic family. |
| 28 | CM | `sqrt(_:) (Complex) -> Complex` (Complex+ElementaryFunctions.swift:442) | Root family. `sqrt(sqrt(z)) ≠ sqrt(z)` except at fixed points. |
| 29 | Algo | `endOfChunk(startingAt:) (Base.Index) -> Base.Index` (Chunked.swift:79) | Stride-style chunk-boundary advance. Surviving v1.16 candidate post-direction-counter (V1.10.1). |
| 30 | Algo | `sizeOfChunk(offset:) (Int) -> Int` (Chunked.swift:243) | Different shape from #29 — query-based size lookup. |
| 31 | Algo | `log(_:) (Double) -> Double` (RandomSample.swift:25) | Internal `Double -> Double` natural-log used in random sampling. |
| 32 | PLK | `nearMissLines(_:) ([String]?) -> [String]?` (ViolationFormatter.swift:58) | Optional-arg formatter. Cycle-6 pick #28 (unknown — only the rater's source-read could decide). |

### commutativity (5)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 33 | OC | `index(_:offsetBy:) (Int, Int) -> Int` (OrderedDictionary+Elements.SubSequence.swift:263) | Directional first-arg vs second-arg semantics. Cycle-6 pick #29 (reject). |
| 34 | OC | `distance(from:to:) (Int, Int) -> Int` (OrderedDictionary+Elements.swift:272) | Anti-commutative by definition — `distance(b, a) = -distance(a, b)`. Different-file variant of cycle-6 pick #30. |
| 35 | OC | `index(_:offsetBy:) (Int, Int) -> Int` (OrderedSet+RandomAccessCollection.swift:176) | OrderedSet variant — measure same-shape rate stability across the namespace. |
| 36 | CM | `-(z:w:) (Complex, Complex) -> Complex` (Complex+AdditiveArithmetic.swift:29) | Subtraction — anti-commutative. Cycle-6 pick #32 (reject). |
| 37 | CM | `_relaxedAdd(_:_:) (Self, Self) -> Self` (Complex+AlgebraicField.swift:171) | Internal relaxed-precision addition — abstractly commutative; FP rounding caveat. Cycle-6 pick #33 (accept). |

### associativity (5)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 38 | OC | `index(_:offsetBy:) (Int, Int) -> Int` (OrderedDictionary+Elements.SubSequence.swift:263) | Same op as commutativity #33 — measure whether the rater verdicts associativity-yes / commutativity-no consistently. Cycle-6 pick #34 (accept). |
| 39 | OC | `distance(from:to:) (Int, Int) -> Int` (OrderedSet+RandomAccessCollection.swift:222) | Distance is not a combine op — no associativity. Cycle-6 pick #35 (reject). |
| 40 | OC | `index(_:offsetBy:) (Int, Int) -> Int` (OrderedDictionary+Values.swift:228) | Different-file variant of #38 — coverage. |
| 41 | CM | `/(z:w:) (Complex, Complex) -> Complex` (Complex+AlgebraicField.swift:37) | Division — non-associative by definition. |
| 42 | CM | `_relaxedMul(_:_:) (Self, Self) -> Self` (Complex+AlgebraicField.swift:176) | Internal relaxed-precision multiplication — abstractly associative; FP rounding caveat. |

### monotonicity (6)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 43 | OC | `minimumCapacity(forScale:) (Int) -> Int` (_HashTable+Constants.swift:58) | Genuinely monotonic capacity-from-scale function. Cycle-6 pick #39 (accept). |
| 44 | OC | `_description(type:) (String) -> String` (_HashTable+CustomStringConvertible.swift:29) | Same site as idempotence #21 — measure same-site cross-template verdicts. String lex order ≠ semantic order. |
| 45 | OC | `index(after:) (Int) -> Int` (OrderedDictionary+Elements.SubSequence.swift:206) | Index increment — strictly monotonic on Int. |
| 46 | Algo | `sizeOfChunk(offset:) (Int) -> Int` (Chunked.swift:243) | Same site as idempotence #30 — query-based size lookup. Likely not monotonic (size depends on chunk boundary, not offset linearly). |
| 47 | PLK | `walkCap(for:) (C) -> Int` (BidirectionalCollectionLaws.swift:237) | Collection-bounded count. Cycle-6 pick #43 — generic on `C: BidirectionalCollection`. |
| 48 | PLK | `format(_:) (CheckResult) -> String` (ViolationFormatter.swift:10) | String formatting of an enum — string lex order ≠ enum semantic order. Cycle-6 pick #42 (reject). |

### inverse-pair (1)

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 49 | Algo | `endOfChunk(startingAt:)` ↔ `startOfChunk(endingAt:)` (Chunked.swift:79/122) | Lone v1.16 inverse-pair candidate. Same pair as round-trip #19. Cycle-6 pick #15 was the round-trip arm of this same site (accept on chunk-start domain); cycle-14 measures whether the inverse-pair arm gets the same verdict. **This is the cycle-15 stride-style label extension target** — its triage verdict directly informs whether v1.18 priority #1 ships. |

### identity-element (1)

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 50 | CM | `rescaledDivide(_:_:) × Complex.zero` (Complex+AlgebraicField.swift:48 / Complex+AdditiveArithmetic.swift:19) | The lone Score 70 Likely-tier survivor. Same pick as cycle-6 pick #50. Important: not a Possible-tier pick but the only identity-element across all 4 corpora. The cycle-6 verdict was reject (`rescaledDivide` is division — `x / 0` is undefined, not `x`). |

## Notes on coverage

- **OrderedCollections (12)** — OC's surface dropped 101 → 43 across cycles 7-13 (direction-counter cleared the high-volume Index ops; domain-marker + SetAlgebra-shape cleared the capacity/scale + SetAlgebra survivors). The 12 picks span 5 distinct source files.
- **ComplexModule (28)** — CM dominates the v1.16 surface at 166/229 = 72.5%. Round-trip is the entire bulk (136/166); 17 picks span the cross-product breadth (true inverses + numerical variants + cross-pairs).
- **Algorithms (7)** — Algo's surface dropped 75 → 13 across cycles 7-13 (mostly direction-counter + SetAlgebra-shape suppressions). The 7 picks span all 4 source files in the post-suppression surface.
- **PropertyLawKit (3)** — Picks 2 of 6 monotonicity + 1 of 1 idempotence — full per-template coverage despite tiny corpus. Same posture as cycle 6.
- **Score-tier mix:** 49 Possible-tier picks + 1 Likely-tier pick (the identity-element survivor); the Likely outlier is flagged. Resolves v1.17 plan §"Open decisions" #6 in favor of (a).
- **Cross-template same-site coverage:** picks #19 + #29 + #49 share the same `endOfChunk(startingAt:)` site (round-trip + idempotence + inverse-pair fire on the same Algo function); picks #21 + #44 share `_description(type:)`; picks #30 + #46 share `sizeOfChunk(offset:)`; picks #33 + #38 + #35 share `index(_:offsetBy:)`. These are not quirks of selection; they're properties of the v1.16 surface where one site can fire on multiple templates. The triage rate is computed per-template, so these are 7 distinct decisions, not 4.
