# Cycle-6 Triage Sample Manifest

**Captured:** 2026-05-08 against the v1.8.0 release tag (`d006deb`).
**Source:** post-V1.8.1 surface across the 4 cycle-1+2+3+4+5 corpora — total 349 suggestions ([`../calibration-cycle-5-data/`](../calibration-cycle-5-data/)).
**Sample size:** 50 decisions stratified by template × corpus.
**Rater:** single-runner (Claude); see [`../cycle-6-triage-rubric.md`](../cycle-6-triage-rubric.md) for the methodology + caveats.

## Why these 50

Stratified to ensure each template surface gets enough decisions to compute a per-template acceptance rate while keeping the rater fatigue at a single-session level. Per-cell minimum 1, per-template minimum 5 (where 5 are available in the surface).

## Stratification matrix

| Template | Surface | Sample | OC | CM | Algo | PLK |
|---|---:|---:|---:|---:|---:|---:|
| round-trip | 181 | 16 | 6 | 7 | 3 | 0 |
| idempotence | 89 | 12 | 4 | 3 | 4 | 1 |
| commutativity | 17 | 5 | 3 | 2 | 0 | 0 |
| associativity | 17 | 5 | 3 | 2 | 0 | 0 |
| monotonicity | 29 | 6 | 3 | 0 | 1 | 2 |
| inverse-pair | 15 | 5 | 3 | 0 | 2 | 0 |
| identity-element | 1 | 1 | 0 | 1 | 0 | 0 |
| **Total** | **349** | **50** | **22** | **15** | **10** | **3** |

The single identity-element pick is the Score 70 (Likely-tier) `rescaledDivide(_:_:)` × `Complex.zero` survivor — included because it's the only identity-element suggestion across the entire 349-surface and worth a triage call despite being at Likely tier rather than the Possible-tier focus.

## Sample-selection method

Within each (template, corpus) cell:

1. **Diversity preference.** Pick suggestions that cover different source files when possible, not the same file's cross-product.
2. **V1.8.1 re-emergence priority.** For round-trip on OrderedCollections / Algorithms, prioritize the cycle-5 V1.7.1-suppressed-then-re-emerged pairs — they're the most cycle-context-rich subjects.
3. **First-N from sorted output.** Where multiple suggestions are equally diverse, pick the first by `(file, line)` ordering of the cycle-5 capture.

## Sample listing

Full per-decision detail + rationale lives in [`triage-notes.md`](triage-notes.md); machine-readable decisions in [`triage-decisions.json`](triage-decisions.json). This manifest gives the index.

### round-trip (16)

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 1 | OC | `minimumCapacity(forScale:)` ↔ `maximumCapacity(forScale:)` | V1.7.1 re-emergence — flagship cycle-5 case. |
| 2 | OC | `minimumCapacity(forScale:)` ↔ `scale(forCapacity:)` | V1.7.1 re-emergence — partial-inverse candidate. |
| 3 | OC | `minimumCapacity(forScale:)` ↔ `wordCount(forScale:)` | V1.7.1 re-emergence — semantically unrelated. |
| 4 | OC | `index(after:)` ↔ `index(before:)` (OrderedDictionary+Elements.SubSequence) | V1.7.1 re-emergence — true Collection-protocol inverse pair. |
| 5 | OC | `bucket(after:)` ↔ `bucket(before:)` (_HashTable+UnsafeHandle) | Cycle-5 surviving user-type round-trip. |
| 6 | OC | `intersection(_:)` ↔ `subtracting(_:)` (OrderedSet) | Cycle-5 surviving Self-type round-trip. |
| 7 | CM | `exp(_:)` ↔ `expMinusOne(_:)` | Cross-product elementary-functions noise. |
| 8 | CM | `exp(_:)` ↔ `cosh(_:)` | Cross-product. |
| 9 | CM | `exp(_:)` ↔ `cos(_:)` | Cross-product. |
| 10 | CM | `cosh(_:)` ↔ `sinh(_:)` | Cross-product. |
| 11 | CM | `log(_:)` ↔ `exp(_:)` | Genuine inverse pair candidate. |
| 12 | CM | `sin(_:)` ↔ `asin(_:)` | Genuine inverse pair candidate. |
| 13 | CM | `polar(from:)` ↔ `init(r:θ:)` | Conversion pair candidate. |
| 14 | Algo | `index(after:)` ↔ `index(before:)` (AdjacentPairs) | Collection-protocol inverse pair. |
| 15 | Algo | `endOfChunk(startingAt:)` ↔ `startOfChunk(endingAt:)` (Chunked) | Domain-meaningful pair. |
| 16 | Algo | (Double) -> Double pair | V1.7.1 re-emergence — only Double round-trip on Algo. |

### idempotence (12)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 17 | OC | `minimumCapacity(forScale:)` | Domain-mismatch case (scale → capacity). |
| 18 | OC | `index(after:)` (OrderedDictionary+Elements) | Index-as-pseudo-Int — likely not idempotent on valid domain. |
| 19 | OC | `bucket(after:)` (_HashTable+UnsafeHandle) | Bucket index increment. |
| 20 | OC | `_minimumCapacity(forScale:)` (OrderedSet+Testing) | Test-shim variant. |
| 21 | CM | `exp(_:)` | Elementary function — exp(exp(x)) ≠ exp(x). |
| 22 | CM | `log(_:)` | log(log(x)) ≠ log(x). |
| 23 | CM | `conjugate` (or similar self-pair) | Truly idempotent? |
| 24 | Algo | `index(after:)` (AdjacentPairs) | Collection-protocol increment. |
| 25 | Algo | `endOfChunk(startingAt:)` (Chunked) | Chunk-boundary advance. |
| 26 | Algo | `index(after:)` (FlattenCollection) | Nested collection increment. |
| 27 | Algo | `index(before:)` (Joined) | Decrement. |
| 28 | PLK | `nearMissLines(_:)` ([String]?) -> [String]? | Optional-arg formatter — possibly idempotent. |

### commutativity (5)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 29 | OC | OC user-named binary `(Int, Int) -> Int` op | Cycle-5 baseline of user-named ops. |
| 30 | OC | OC binary set op | SetAlgebra-shaped. |
| 31 | OC | OC binary collection op | Collection-shaped. |
| 32 | CM | Complex `(Complex, Complex) -> Complex` op | Op on user type. |
| 33 | CM | Another Complex op | Variant. |

### associativity (5)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 34 | OC | Same as commutativity #29 (associativity arm) | Per-template comparison. |
| 35 | OC | Same as commutativity #30 (associativity arm) | |
| 36 | OC | OC unique associativity | Diversity. |
| 37 | CM | Same as commutativity #32 (associativity arm) | |
| 38 | CM | Same as commutativity #33 (associativity arm) | |

### monotonicity (6)

| # | Corpus | Function | Why included |
|---|---|---|---|
| 39 | OC | `minimumCapacity(forScale:)` | Genuinely monotonic (verified from source). |
| 40 | OC | `maximumCapacity(forScale:)` | Same. |
| 41 | OC | `scale(forCapacity:)` | Same. |
| 42 | PLK | `format(_:)` (CheckResult) -> String | NOT monotonic (string lex order ≠ enum semantic order). |
| 43 | PLK | `walkCap(for:)` (C) -> Int | C is generic — collection-bounded count. |
| 44 | Algo | An Algorithms Index → Int monotonicity claim | If present. |

### inverse-pair (5)

| # | Corpus | Function-pair | Why included |
|---|---|---|---|
| 45 | OC | OrderedSet binary inverse-pair | SetAlgebra-shaped. |
| 46 | OC | Variant. | |
| 47 | OC | Variant. | |
| 48 | Algo | An Algorithms inverse-pair | Index ops. |
| 49 | Algo | Another. | |

### identity-element (1)

| # | Corpus | Pair | Why included |
|---|---|---|---|
| 50 | CM | `rescaledDivide(_:_:)` × `Complex.zero` | The lone Score 70 survivor. Important: not a Possible-tier pick but the only identity-element across all 4 corpora. |

## Notes on coverage

- **OrderedCollections (22)** is the highest-sample corpus because its surface (101) is most diverse and includes the V1.7.1 re-emergences — cycle-5's headline.
- **ComplexModule (15)** is sampled across its 136 round-trips at ~5%, plus its 17 idempotence at ~18%, plus 4 ops in commutativity/associativity.
- **Algorithms (10)** is dominated by `(Index) -> Index` shapes; sample picks distinct source-file pairs to avoid same-pattern repetition.
- **PropertyLawKit (3)** picks 2 of 6 monotonicity + 1 of 1 idempotence — full per-template coverage despite tiny corpus.
- **Score-tier mix:** 49 Possible-tier picks + 1 Likely-tier pick (the identity-element survivor); the Likely outlier is flagged.
