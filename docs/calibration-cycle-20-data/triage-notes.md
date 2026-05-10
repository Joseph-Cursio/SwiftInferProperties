# Cycle-20 Triage Notes

**Captured:** 2026-05-10. Single-runner triage by Claude on the v1.22.0 release tag (`78ef8d5`). Triage on the post-v1.22 152-surface as captured in [`../calibration-cycle-19-data/post-v1.22-*.discover.txt`](../calibration-cycle-19-data/) (v1.23 binary-equivalent to v1.22).
**Rubric:** [`../cycle-20-triage-rubric.md`](../cycle-20-triage-rubric.md) — per-template criteria for the 10 template classes are verbatim from cycle 17.
**Sample manifest:** [`sample-manifest.md`](sample-manifest.md)
**Machine-readable decisions:** [`triage-decisions.json`](triage-decisions.json)

Per-decision rationale below.

---

## round-trip (11 decisions)

### 1-4. CM | round-trip | canonical-inverse anchors

`exp × log`, `cos × acos`, `sin × asin`, `tan × atan` — all **accept**. Cycle-17 #5/#9/#10/#11 rate-stability. Genuine principal-branch inverse pairs preserved by V1.21.C `MathForwardFunctions.canonicalInversePairs` allowlist.

### 5. CM | round-trip | `expMinusOne(_:)` × `log(onePlus:)` (Complex+ElementaryFunctions.swift:71/331)

**Decision: accept.**

Numerics-extension numerical-variant pair. `expMinusOne(z) = exp(z) - 1` is the accurate-near-zero variant; `log(onePlus: x) = log(1 + x)` is the corresponding accurate-near-zero `log` variant. The pair is by-design accurate-near-zero inverses (cycle-17 #7 originally rejected the `expMinusOne × log` pairing because `log(_:)` isn't its accurate counterpart; the `log(onePlus:)` variant IS, and V1.21.C's `canonicalInversePairs` allowlist preserves it).

### 6. OC | round-trip | `_value(forBucketContents:)` × `_bucketContents(for:)` (UnsafeHandle.swift:201/219)

**Decision: accept.**

Codec pair. Asymmetric `(UInt64) -> Int?` ↔ `(Int?) -> UInt64` typing. Cycle-14 #1 / cycle-17 #1 rate-stability accept.

### 7-10. OC | round-trip | `index(after/before:)` × `_minimumCapacity/_maximumCapacity/_scale(forCapacity:)` cross-pairs

All **reject**. Cycle-19 finding asymmetric class FIRST cycle-20 measurement.

`index(after:)` advances an integer index by 1; `_minimumCapacity(forScale:)` computes hash-table capacity from a scale parameter. Both `(Int) -> Int` shape but operating on entirely different domains. Round-trip property `g(f(x)) == x` doesn't hold — the functions aren't inverses, they're unrelated computations on coincidentally-shaped types. Rubric §"Round-trip Reject" applies: "the pair is *related* but semantically not inverses (e.g., `minimumCapacity(forScale:)` and `maximumCapacity(forScale:)` both take `scale` and return capacity but yield *different* capacities — `min(scale(c)) == c` doesn't hold across the cross-product)."

V1.22.B's both-sides direction-counter (-25) doesn't fire on these because `forScale:` is in `DomainMarkerLabels.curated`, not `DirectionLabels.curated`. V1.15.1's domain-marker counter requires both sides domain-marker-labeled, but `after:` is direction not domain-marker. Hence the asymmetric class survives at score 20 (Possible). The cycle-19 finding identifies this as the next mechanism target.

### 11. OC | round-trip | `_minimumCapacity(forScale:)` × `_maximumCapacity(forScale:)` (Testing.swift:39/45)

**Decision: reject.**

Both forward capacity-from-scale; not codec. Both functions have the same `forScale:` domain-marker label but they aren't inverses — they compute MIN vs MAX capacities for the same scale. V1.15.1's domain-marker counter does fire (both sides domain-marker-labeled), reducing the score; it surfaces because the score lands at exactly the Possible boundary post-V1.18.A carrier signal.

---

## idempotence (non-lifted) (7 decisions)

### 12. OC | idempotence | `_description(type:)` (CustomStringConvertible.swift:29)

**Decision: reject.** Cycle-17 #16 rate-stability. Formatter wraps input.

### 13. OC | idempotence | `firstOccupiedBucketInChain(with:)` (UnsafeHandle.swift:325)

**Decision: unknown.** Cycle-17 #17 rate-stability. Bucket-chain seek; idempotence dependent on internal hash-table state.

### 14. OC | idempotence | `_minimumCapacity(forScale:)` (Testing.swift:39)

**Decision: reject.**

`_minimumCapacity(forScale:)` is a function that computes capacity FROM scale. The idempotence claim would be `_minimumCapacity(_minimumCapacity(scale))` — feeding capacity back as scale, which is a type-shape coincidence (both are Int) but semantically meaningless. Rubric §"Idempotence Reject" applies: "the function is *partially* idempotent (idempotent on some subdomain but not all of T)" — capacity-of-capacity is not the claim's intended property.

### 15. OC | idempotence | `bucket(after:)` (UnsafeHandle.swift:137)

**Decision: reject.**

`bucket(after:)` advances an index. `bucket(after(b)) ≠ b` (advances to next position); not idempotent. Direction-op, parallels cycle-14/17 reject pattern.

### 16. OC | idempotence | `wordCount(forScale:)` (Constants.swift:97)

**Decision: reject.** Same shape as #14 — function computes word-count FROM scale; type-shape coincidence; not idempotent.

### 17. PLK | idempotence | `nearMissLines(_:)` (ViolationFormatter.swift:58)

**Decision: unknown.** Cycle-17 #21 rate-stability. Optional-arg formatter; rater can't determine without source inspection.

### 18. PLK | idempotence | `format(_:)` (ViolationFormatter.swift:10)

**Decision: reject.**

Formatter wraps `CheckResult` enum into String. The claim `format(format(s)) == format(s)` doesn't make type-sense (`format(s)` is `String`, `format(format(s))` would require `format` to accept `String` — type mismatch with the original `CheckResult` parameter). Suggestion fires on type-shape coincidence; not actually idempotent.

---

## commutativity (3 decisions)

### 19. OC | commutativity | `index(_:offsetBy:)` (Elements.SubSequence.swift:263)

**Decision: reject.** Cycle-17 #22 rate-stability. Directional first-arg vs second-arg.

### 20. CM | commutativity | `-(z:w:)` (AdditiveArithmetic.swift:29)

**Decision: reject.** Cycle-17 #23 rate-stability. Subtraction, anti-commutative.

### 21. CM | commutativity | `_relaxedAdd(_:_:)` (AlgebraicField.swift:171)

**Decision: accept.** Cycle-17 #24 rate-stability. Relaxed-precision addition is abstractly commutative.

---

## associativity (3 decisions)

### 22. OC | associativity | `index(_:offsetBy:)` (Elements.SubSequence.swift:263)

**Decision: accept.** Cycle-17 #25 rate-stability. Int offset addition is associative.

### 23. CM | associativity | `/(z:w:)` (AlgebraicField.swift:37)

**Decision: reject.** Cycle-17 #26 rate-stability. Division, non-associative.

### 24. CM | associativity | `_relaxedMul(_:_:)` (AlgebraicField.swift:176)

**Decision: accept.** Cycle-17 #27 rate-stability. Relaxed-precision multiplication is abstractly associative.

---

## monotonicity (4 decisions)

### 25. OC | monotonicity | `_minimumCapacity(forScale:)` (Testing.swift:39)

**Decision: accept.** Cycle-17 #28 rate-stability. Capacity-from-scale is monotonic in scale.

### 26. OC | monotonicity | `index(after:)` (RandomAccessCollection.swift:119)

**Decision: accept.** Cycle-17 #29 rate-stability. Strictly monotonic Int+1.

### 27. Algo | monotonicity | `sizeOfChunk(offset:)` (Chunked.swift:243)

**Decision: reject.** Cycle-17 #30 rate-stability. Size depends on chunk boundary, not linearly on offset.

### 28. PLK | monotonicity | `walkCap(for:)` (BidirectionalCollectionLaws.swift:237)

**Decision: accept.** Cycle-17 #31 rate-stability. Collection-bounded count, monotonic in collection size.

---

## inverse-pair (non-lifted) (2 decisions)

### 29. OC | inverse-pair | `bucket(after:) × bucket(before:)` (UnsafeHandle.swift:137/149)

**Decision: reject.** Cycle-17 #33 rate-stability. Direction-pair on `Bucket`, not inverses.

### 30. OC | inverse-pair | `word(after:) × word(before:)` (UnsafeHandle.swift:160/174)

**Decision: reject.**

Same shape as #29 — direction-pair on `Int`, not inverses (both forward index ops). NEW v1.22 sample on different file; rate-stability check on the cycle-17 #33 framework.

---

## identity-element (non-lifted) (1 decision)

### 31. CM | identity-element | `rescaledDivide × Complex.zero`

**Decision: reject.** Cycle-6/14/17 #34 rate-stability across all 4 measurement points. Division by zero is undefined.

---

## dual-style-consistency (5 decisions) — V1.18.C rate-stability check

### 32-36. OC dual-style picks

All **accept.** Cycle-17 #35-#39 rate-stability. By-construction precision via curated naming-rule pairing constraint:
- `OrderedSet.formUnion × union` — SetAlgebra form-prefix dual.
- `OrderedSet.formIntersection × intersection` — SetAlgebra dual.
- `OrderedSet.formSymmetricDifference × symmetricDifference` — SetAlgebra dual.
- `OrderedSet.subtract × subtracting` — SetAlgebra dual (active/-ing rule).
- `OrderedDictionary.merge × merging` — Swift dict merging convention.

V1.18.C's 100% by-construction precision continues to hold at cycle-20.

---

## idempotence-lifted (9 decisions) — split: 2 internal-CoW + 7 sort/shuffle/reverse first measurement

### 37. OC | idempotence (lifted) | `OrderedSet._isUnique()`

**Decision: accept.** Cycle-17 #44 rate-stability. Internal CoW uniqueness check; calling twice on already-unique storage is no-op.

### 38. OC | idempotence (lifted) | `OrderedSet._regenerateHashTable()`

**Decision: accept.** Cycle-17 #45 rate-stability. Rebuild from scratch; idempotent.

### 39. OC | idempotence (lifted) | `OrderedDictionary.sort()` (Partial MutableCollection.swift:126)

**Decision: accept.**

`sort()` lifted to `(OrderedDictionary) -> OrderedDictionary`. Sorting an already-sorted collection produces the same sorted output (under the default Comparable comparator). `sort(sort(s)) = sort(s)` because sorted is the fixed point of the sort operation. **NEW first-measurement of OC sort/shuffle/reverse class**: sort is the accept-class within this class.

### 40. OC | idempotence (lifted) | `OrderedDictionary.shuffle()` (Partial MutableCollection.swift:142)

**Decision: unknown.**

`shuffle()` is non-deterministic — calling twice produces different orderings. SwiftInfer's `nonDeterministicVeto` (V1.4.x) should have caught this via `bodySignals.hasNonDeterministicCall` detecting the RNG call inside `shuffle()`. The fact that this suggestion surfaces means either: (a) the body-signal detector missed the RNG call (e.g., `shuffle()` uses a non-curated RNG API), or (b) the lifted-path's `nonDeterministicVeto` reused a different code path. Rater can't determine without source inspection of `OrderedDictionary.shuffle()` internals + the lifted-template signal pipeline. **UNKNOWN flagged for cycle-21 mechanism investigation** — either the RNG-detection set needs extension or the lifted-path veto needs explicit non-determinism check.

### 41. OC | idempotence (lifted) | `OrderedDictionary.reverse()` (Partial MutableCollection.swift:190)

**Decision: reject.**

`reverse()` lifted: `reverse(reverse(s)) = s ≠ reverse(s)` for non-palindromic input. Not idempotent.

### 42. OC | idempotence (lifted) | `OrderedDictionary.removeFirst()` (Partial RangeReplaceableCollection.swift:111)

**Decision: reject.**

State advances per call (removes one element each time). Not idempotent. Same class as cycle-17 Iterator.next() rejects.

### 43. OC | idempotence (lifted) | `OrderedDictionary.removeLast()` (Partial RangeReplaceableCollection.swift:140)

**Decision: reject.** Same shape as #42.

### 44. OC | idempotence (lifted) | `OrderedSet.sort()`

**Decision: accept.** Same shape as #39.

### 45. OC | idempotence (lifted) | `OrderedSet.reverse()`

**Decision: reject.** Same shape as #41.

---

## composition-lifted (1 decision) — V1.21.B demote rate-stability

### 46. OC | composition (lifted) | `_HashTable.BucketIterator.advance(until: Int)`

**Decision: reject.** Cycle-17 #46 rate-stability. V1.21.B Strong → Likely demotion didn't change the underlying mathematical relation: `advance(until: a).advance(until: b) = max(a, b)`-bounded state, not `advance(until: a + b)` additive. The demotion is a calibration response to the cycle-17 reject verdict; cycle-20 confirms the verdict still holds.

---

## Summary

**Per-template results:**

| Template | Picks | Accept | Reject | Unknown | Acceptance rate (excl unknown) |
|---|---:|---:|---:|---:|---:|
| round-trip | 11 | 6 | 5 | 0 | 6/11 = **54.5%** |
| idempotence (non-lifted) | 7 | 0 | 5 | 2 | 0/5 = **0.0%** |
| commutativity | 3 | 1 | 2 | 0 | 1/3 = **33.3%** |
| associativity | 3 | 2 | 1 | 0 | 2/3 = **66.7%** |
| monotonicity | 4 | 3 | 1 | 0 | 3/4 = **75.0%** |
| inverse-pair (non-lifted) | 2 | 0 | 2 | 0 | 0/2 = **0.0%** |
| identity-element (non-lifted) | 1 | 0 | 1 | 0 | 0/1 = **0.0%** |
| **dual-style-consistency** | 5 | 5 | 0 | 0 | 5/5 = **100.0%** |
| **idempotence-lifted** | 9 | 4 | 4 | 1 | 4/8 = **50.0%** |
| **composition-lifted** | 1 | 0 | 1 | 0 | 0/1 = **0.0%** |
| **All** | **46** | **21** | **22** | **3** | **21/43 = 48.8%** |

**Per-corpus results:**

| Corpus | Picks | Accept | Reject | Unknown | Acceptance rate |
|---|---:|---:|---:|---:|---:|
| OC | 32 | 13 | 16 | 1 | 13/29 = **44.8%** |
| CM | 10 | 7 | 3 | 0 | 7/10 = **70.0%** |
| Algo | 1 | 0 | 1 | 0 | 0/1 = **0.0%** |
| PLK | 3 | 1 | 0 | 2 | 1/1 = **100.0%** |
| **All** | **46** | **21** | **22** | **3** | **21/43 = 48.8%** |

**Aggregate trajectory (4-point):**

| Cycle | Surface | Sample | Accept | Reject | Unknown | Rate |
|---|---:|---:|---:|---:|---:|---:|
| 6 (v1.9) | 349 | 50 | 12 | 33 | 5 | 12/45 = **26.7%** |
| 14 (v1.17) | 229 | 50 | 16 | 30 | 4 | 16/46 = **34.8%** (+8.1pp) |
| 17 (v1.20) | 335 | 46 | 23 | 21 | 2 | 23/44 = **52.3%** (+17.5pp) |
| **20 (v1.23)** | **152** | **46** | **21** | **22** | **3** | **21/43 = 48.8% (-3.5pp)** |

**Outcome D** under the v1.23 plan §"Trajectory framing" thresholds (Aggregate < 52% — counter-intuitive: v1.21 + v1.22 swept some accepts).

**Why the rate dropped from cycle-17:**

1. **V1.22.D suppressed cycle-17 ACCEPT class.** The Algo `endOfChunk(startingAt:) × startOfChunk(endingAt:)` triple was cycle-14/17 ACCEPT (3 picks); V1.22.D's stride-style label both-sides veto closes round-trip + inverse-pair on this site (calibration trade-off documented per v1.22 plan §"Risks"). Cycle-20 doesn't sample these (suppressed from `--include-possible`); the cycle-17→cycle-20 sample loses 2-3 ACCEPT picks.

2. **Cycle-20 sample concentrates on first-measurement reject classes.** The OC asymmetric round-trip cross-pair class (5 picks; all reject) and the OC sort/shuffle/reverse/removeFirst/removeLast lifted-idempotence sub-class (7 picks; 2 accept + 4 reject + 1 unknown) weren't sampled at cycle-17. Cycle-20 deliberately samples these for first-measurement; the resulting 4 accepts + 9 rejects + 1 unknown shifts the aggregate down.

3. **Cycle-20 round-trip sample weighting differs from cycle-17.** Cycle-17 had 7/15 round-trip picks on CM canonical anchors (47% of round-trip sample = ACCEPT class). Cycle-20 has 4/11 = 36% on CM canonical anchors; the rest (5 OC asymmetric + 1 OC codec + 1 CM numerics-extension) is denser on the cycle-19-finding REJECT class.

**Mechanism-class effectiveness ranking (cycle-20):**

| Mechanism | Cycle | Cycle-20 sample contribution |
|---|---|---|
| Workstream C (V1.18.C dual-style) | 15 | 5/5 = **100% rate-stability** (continued by-construction precision) |
| V1.21.A IteratorProtocol veto | 18 | 0 sample picks (carrier-class fully closed) |
| V1.22.A BucketIterator extension | 19 | 0 sample picks (carrier-class fully closed) |
| V1.21.C Math-forward function veto | 18 | 5/5 CM canonical anchors preserved by allowlist (rate-stability) |
| V1.22.B both-sides direction-counter | 19 | -8 closures from sample pool; but exposed asymmetric cross-pair class (5/5 reject — first measurement) |
| V1.22.D stride-style label veto | 19 | -3 sample picks suppressed (Algo `endOfChunk` triple ACCEPT class — calibration trade-off) |
| **V1.22.C fixed-point-name positive signal (NEW class 14)** | 19 | **0 sample picks** (recall-positive infrastructure ready; no functions in `FixedPointNames.curated` surface on cycle-1..14 corpora) |

**The mechanism-attributable rate impact** can be decomposed:
- V1.18.C dual-style: rate-stability (no change).
- V1.21.A + V1.22.A Iterator-shape closures: removed 22 + 3 = 25 reject-class candidates from the pool — precision-positive on the surface but cycle-20 sample doesn't include any (they're not surfacing).
- V1.22.B direction-counter: precision-positive (-7 OC + -1 Algo); revealed asymmetric cross-pair class that wasn't sampled at cycle-17.
- V1.22.D stride-style: precision-positive on surface (-2 candidates); but suppressed cycle-17 ACCEPT class — calibration trade-off cost the cycle-20 aggregate ~2-3 percentage points.
- V1.21.C Math-forward function: precision-positive (-148 candidates); allowlist preserved cycle-17 anchor class.

**Net cycle-20 verdict:** cycle-18 + cycle-19 mechanism work was **precision-positive on the surface** (-183 candidates closed) but **rate-positive only when measured on a sample that preserves the cycle-17 sampling distribution**. The cycle-20 sample's first-measurement of the asymmetric-pair + sort/shuffle/reverse classes shifts the aggregate down because those classes have low per-template acceptance rates that weren't visible at cycle-17.

**Cycle-21 priority list (rotated post-v1.23, in expected impact order):**

1. **Asymmetric label class mismatch counter** on round-trip (cycle-19 finding; reconfirmed by cycle-20 5/5 reject on this class). When forward has direction-label and reverse has domain-marker (or vice versa), fire at -25 (full veto). Magnitude: closes ~5-10 OC candidates.
2. **Reverse / removeFirst / removeLast veto on idempotence-lifted** (cycle-20 finding — NEW). 4 of 7 OC sort/shuffle/reverse-class picks reject because reverse/removeFirst/removeLast aren't idempotent. Mechanism: extend V1.21.A's `iteratorMethodNames` curated set with `reverse`, `removeFirst`, `removeLast` — but V1.21.A only fires when carrier conforms to IteratorProtocol; OrderedDictionary doesn't. Need a new mechanism: detect `mutating func reverse() -> Void` / `mutating func removeFirst() -> Void` shape on RangeReplaceableCollection / MutableCollection-conforming carriers. Magnitude: closes ~6 OC candidates (4 reverse + 2 removeFirst/removeLast variants).
3. **Non-deterministic shuffle veto extension** (cycle-20 finding — NEW). The 1 OC `shuffle()` lifted-idempotence pick surfaced despite being non-deterministic. Mechanism: extend `nonDeterministicVeto`'s body-signal detection to catch the OC stdlib RNG call patterns OR add a name-fallback (`shuffle` is canonical Swift non-deterministic mutator name).
4. **FP approximate-equality template arm** (6-cycle carry-forward; cycle-14 priority #4 → cycle-15/16/17/18/19/20 carry-forward).
5. **Math-library op-name extension to `rescaledDivide` / `_relaxed*`** (4-cycle carry-forward; cycle-20 measures `_relaxedAdd` + `_relaxedMul` at ACCEPT — the curated set extension would not suppress these; the priority is more about adding the family for future-cycle stability).

**v1.23 records the cycle-20 measurement**; v1.24+ ships the rotated cycle-21 priority list. The §19 ≥70% target is +21pp from cycle-20's 48.8% — three more mechanism cycles at the cycle-18 magnitude (each + ~7pp on average) get there.
