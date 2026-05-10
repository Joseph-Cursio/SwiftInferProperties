# Cycle-17 Triage Notes

**Captured:** 2026-05-10. Single-runner triage by Claude on the v1.19.0 release tag (`7b50512`). Triage on the post-v1.19 335-surface as captured in [`surface-counts.md`](surface-counts.md).
**Rubric:** [`../cycle-17-triage-rubric.md`](../cycle-17-triage-rubric.md) — per-template criteria for the 7 cycle-14-baseline templates are verbatim from cycle 14; new sections for dual-style + lifted sub-class.
**Sample manifest:** [`sample-manifest.md`](sample-manifest.md)
**Machine-readable decisions:** [`triage-decisions.json`](triage-decisions.json)

Per-decision rationale below. Format: `### N. Corpus | template | site` followed by the decision verdict and rationale paragraph.

---

## round-trip (15 decisions)

### 1. OC | round-trip | `_value(forBucketContents:)` × `_bucketContents(for:)` (_HashTable+UnsafeHandle.swift:201/219)

**Decision: accept.**

Codec pair on a non-Equatable internal storage word. Asymmetric `(UInt64) -> Int?` ↔ `(Int?) -> UInt64` typing is the rubric's quoted "type signatures align" criterion. Underscore-prefixed names indicate an internal codec. Cycle-14 #1 rate-stability accept (same site, same verdict).

### 2. OC | round-trip | `bucket(after:)` × `bucket(before:)` (_HashTable+UnsafeHandle.swift:137/149)

**Decision: reject.**

Direction-pair on `Bucket`, not an inverse pair. Both functions advance an index by one position; `bucket(before(b))` ≠ b in general (advances back-then-forward, OK on contiguous buckets but undefined at storage boundaries). The cycle-9 V1.12.1 direction-counter applied -15; the pair surfaces post-v1.18.A carrier-kind +5 boost. Rubric §"Round-trip Reject" applies — directional ops aren't inverses, they're cycle members.

### 3. OC | round-trip | `index(after:)` × `index(before:)` (OrderedDictionary+Elements.SubSequence.swift:206/220)

**Decision: reject.**

Same shape as #2 across the OD namespace — direction-pair on `Int` index. Cycle-13 had this pair suppressed below visibility; v1.18.A carrier-kind +5 lifts it above the 25-Possible threshold. Pair is not inverses (both advance/retreat the same index by one), it's a `Comparable.Stride`-style ordering pair.

### 4. OC | round-trip | `index(after:)` × `_minimumCapacity(forScale:)` (RandomAccessCollection.swift:119 / OS+Testing.swift:39)

**Decision: reject.**

Cross-file confused pair — `index(after:): (Int) -> Int` and `_minimumCapacity(forScale:): (Int) -> Int` share `(Int) -> Int` shape but operate on entirely unrelated domains (collection index advance vs hash-table capacity computation). Cross-product noise; the rubric's quoted "Functions have asymmetric domains" criterion applies.

### 5. CM | round-trip | `exp(_:)` × `log(_:)` (Complex+ElementaryFunctions.swift:56/231)

**Decision: accept.**

Genuine canonical inverse pair on the principal branch. `log(exp(z)) = z` mod `2πi`; `exp(log(w)) = w` for nonzero `w`. Cycle-14 #5 rate-stability accept; same verdict as cycle-6 #11.

### 6. CM | round-trip | `cosh(_:)` × `acosh(_:)` (141/387)

**Decision: accept.**

Genuine principal-branch inverse pair. Cycle-14 #9.

### 7. CM | round-trip | `sinh(_:)` × `asinh(_:)` (171/396)

**Decision: accept.**

Genuine principal-branch inverse pair. Cycle-14 #10.

### 8. CM | round-trip | `tanh(_:)` × `atanh(_:)` (187/402)

**Decision: accept.**

Genuine principal-branch inverse pair. Cycle-14 #11.

### 9. CM | round-trip | `cos(_:)` × `acos(_:)` (211/364)

**Decision: accept.**

Genuine principal-branch inverse pair. Cycle-14 #12.

### 10. CM | round-trip | `sin(_:)` × `asin(_:)` (217/372)

**Decision: accept.**

Genuine principal-branch inverse pair. Cycle-14 #13; cycle-6 #12.

### 11. CM | round-trip | `tan(_:)` × `atan(_:)` (224/381)

**Decision: accept.**

Genuine principal-branch inverse pair. Cycle-14 #14.

### 12. CM | round-trip | `exp(_:)` × `cosh(_:)` (56/141)

**Decision: reject.**

Cross-product. `cosh(z) = (exp(z) + exp(-z))/2` is forward, not inverse of `exp`. Cycle-14 #3 rate-stability reject.

### 13. CM | round-trip | `exp(_:)` × `sqrt(_:)` (56/442)

**Decision: reject.**

Forward-forward cross-product. `sqrt(exp(z)) = exp(z/2) ≠ z`. Cycle-14 #6.

### 14. CM | round-trip | `log(_:)` × `sqrt(_:)` (231/442)

**Decision: reject.**

Forward-forward cross-product. Cycle-14 #16.

### 15. Algo | round-trip | `endOfChunk(startingAt:)` × `startOfChunk(endingAt:)` (Chunked.swift:79/122)

**Decision: accept.**

Genuine functional-inverse pair on the chunk-boundary domain (`Base.Index` restricted to chunk-start/end positions). The rubric's "clear convention for the legitimate domain" criterion applies — round-trip holds on any well-formed chunk-start input. Cycle-14 #19; cycle-6 #15. Note: this pick continues to surface despite being slated for cycle-15 / v1.18 stride-style suppression — the suppression target is usability (auto-emitted property tests need chunk-boundary generators), not correctness.

---

## idempotence (non-lifted) (6 decisions)

### 16. OC | idempotence | `_description(type:)` (_HashTable+CustomStringConvertible.swift:29)

**Decision: reject.**

Formatter wraps input in structural format (e.g., `"OrderedSet<X>"`); applying twice prepends the wrapper twice, so `f(f(x)) ≠ f(x)`. Cycle-14 #21 rate-stability reject.

### 17. OC | idempotence | `firstOccupiedBucketInChain(with:)` (_HashTable+UnsafeHandle.swift:325)

**Decision: unknown.**

Bucket-chain seek operator. Likely idempotent on already-occupied bucket input (the seek is structural — first occupied bucket starting from `b` doesn't change if `b` is already occupied), but the function operates on `_HashTable.UnsafeHandle` (a stateful view); whether bucket-chain content is invariant between calls is internal-state dependent and read-only-via-source-code per rubric. Cycle-14 #22 unknown rate-stability.

### 18. CM | idempotence | `exp(_:)` (Complex+ElementaryFunctions.swift:56)

**Decision: reject.**

`exp(exp(z)) = e^(e^z) ≠ exp(z)`. Cycle-14 #23.

### 19. CM | idempotence | `log(_:)` (Complex+ElementaryFunctions.swift:231)

**Decision: reject.**

`log(log(z)) ≠ log(z)`. Cycle-14 #24.

### 20. CM | idempotence | `sqrt(_:)` (Complex+ElementaryFunctions.swift:442)

**Decision: reject.**

`sqrt(sqrt(z)) = z^(1/4) ≠ z^(1/2)` generally; idempotent only at fixed points 0 and 1. Cycle-14 #28.

### 21. PLK | idempotence | `nearMissLines(_:)` (ViolationFormatter.swift:58)

**Decision: unknown.**

Optional-arg formatter. Whether re-applying produces the same `[String]?` is internal-state and string-formatting-detail dependent. Rubric §"Single-runner triage caveat" — only the rater's source-read could decide. Cycle-14 #32 unknown rate-stability.

---

## commutativity (3 decisions)

### 22. OC | commutativity | `index(_:offsetBy:)` (OrderedDictionary+Elements.SubSequence.swift:263)

**Decision: reject.**

Directional first-arg vs second-arg semantics — `index(_: i, offsetBy: n)` doesn't commute with `index(_: n, offsetBy: i)` even at the type level (both are `(Int, Int) -> Int` but the first arg is an index, the second a stride). Cycle-14 #33 rate-stability reject.

### 23. CM | commutativity | `-(z:w:)` (Complex+AdditiveArithmetic.swift:29)

**Decision: reject.**

Subtraction — anti-commutative by definition: `z - w = -(w - z)`. Cycle-14 #36.

### 24. CM | commutativity | `_relaxedAdd(_:_:)` (Complex+AlgebraicField.swift:171)

**Decision: accept.**

Internal relaxed-precision addition — abstractly commutative; `a + b = b + a` modulo FP rounding error in the relaxed-precision domain. The relaxation flag affects associativity / determinism, not commutativity. Cycle-14 #37.

---

## associativity (3 decisions)

### 25. OC | associativity | `index(_:offsetBy:)` (OrderedDictionary+Elements.SubSequence.swift:263)

**Decision: accept.**

Same site as commutativity #22 — measure cross-template (commutativity-no / associativity-yes) consistency. Int offset addition is associative: `index(index(i, n), m) = index(i, n + m)` (the offset stride composes additively even though the index/offset asymmetry breaks commutativity). Cycle-14 #38 accept.

### 26. CM | associativity | `/(z:w:)` (Complex+AlgebraicField.swift:37)

**Decision: reject.**

Division — non-associative by definition: `(a/b)/c ≠ a/(b/c)`. Cycle-14 #41.

### 27. CM | associativity | `_relaxedMul(_:_:)` (Complex+AlgebraicField.swift:176)

**Decision: accept.**

Internal relaxed-precision multiplication — abstractly associative; FP rounding caveat. The relaxation flag explicitly trades determinism (and thus strict bit-level associativity) for performance; the abstract algebraic property still holds. Cycle-14 #42.

---

## monotonicity (4 decisions)

### 28. OC | monotonicity | `_minimumCapacity(forScale:)` (OrderedSet+Testing.swift:39)

**Decision: accept.**

Capacity-from-scale function — larger scale produces at-least-as-large minimum capacity by construction. Cycle-14 #43 (`minimumCapacity(forScale:)` on `_HashTable+Constants.swift:58`) was accept on the same name in a different file; this is the testing-namespace mirror. Same verdict.

### 29. OC | monotonicity | `index(after:)` (OrderedSet+RandomAccessCollection.swift:119)

**Decision: accept.**

Index increment on `Int` — strictly monotonic by definition (`index(after: i) > i`). The rubric's quoted "Function takes a single Comparable input and returns Comparable; doc / name suggests order-preservation" criterion applies directly.

### 30. Algo | monotonicity | `sizeOfChunk(offset:)` (Chunked.swift:243)

**Decision: reject.**

Query-based size lookup — size depends on chunk boundary, not linearly on offset. `sizeOfChunk(offset: 0)` could return 5 (chunk 0 has 5 elements); `sizeOfChunk(offset: 5)` could return 3 (chunk 1 has 3 elements). Not monotonic. Cycle-14 #46.

### 31. PLK | monotonicity | `walkCap(for:)` (BidirectionalCollectionLaws.swift:237)

**Decision: accept.**

Collection-bounded count — walks the collection up to a cap, returns the smaller of `count(c)` or the cap. Monotonic in collection size: a larger collection produces at-least-as-large walkCap. Cycle-14 #47.

---

## inverse-pair (non-lifted) (2 decisions)

### 32. Algo | inverse-pair | `endOfChunk(startingAt:)` × `startOfChunk(endingAt:)` (Chunked.swift:79/122)

**Decision: accept.**

Same site as round-trip #15 — round-trip + inverse-pair both fire on this Algo function pair. Functional inverse on the chunk-boundary domain. Cycle-14 #49 accept (same site, same verdict).

### 33. OC | inverse-pair | `bucket(after:)` × `bucket(before:)` (_HashTable+UnsafeHandle.swift:137/149)

**Decision: reject.**

NEW v1.19 visibility — V1.18.A carrier-kind +5 on `_HashTable.UnsafeHandle` (value-semantic struct) lifts this pair from sub-Possible to Possible (score 25). Direction-pair on `Bucket`, not a true functional inverse. Cycle-9 V1.11.1 direction-counter applied -10 but pair surfaces post-v1.18.A. Same shape and same reject verdict as round-trip pick #2.

---

## identity-element (non-lifted) (1 decision)

### 34. CM | identity-element | `rescaledDivide(_:_:) × Complex.zero` (Complex+AlgebraicField.swift:48 / Complex+AdditiveArithmetic.swift:19)

**Decision: reject.**

`rescaledDivide` is division — `x / 0` is undefined (NaN/infinity), not `x`. The rubric's quoted "the op-name + element doesn't match any kit-published law" criterion applies. Same Score 70 Likely-tier survivor as cycles 6 + 14; same reject verdict.

---

## dual-style-consistency (5 decisions) — NEW v1.18.C

### 35. OC | dual-style-consistency | `OrderedSet.formUnion(_: __owned Self)` × `OrderedSet.union(_: __owned Self) -> Self` (formUnion.swift:44 / union.swift:38)

**Decision: accept.**

Canonical SetAlgebra form-prefix dual pair. Both methods compute set union; the mutating version applies it in-place to `self`, the non-mutating returns a new `Self`. Semantically equivalent by SetAlgebra protocol spec — `a.formUnion(b)` and `c = a.union(b)` produce identical resulting sets. Rubric §"Dual-style-consistency Accept" applies — curated pair name describes a real dual-style sibling.

### 36. OC | dual-style-consistency | `OrderedSet.formIntersection(_: Self)` × `OrderedSet.intersection(_: Self) -> Self` (formIntersection.swift:40 / intersection.swift:46)

**Decision: accept.**

Same posture as #35 — canonical SetAlgebra dual on the intersection operation.

### 37. OC | dual-style-consistency | `OrderedSet.formSymmetricDifference(_: __owned Self)` × `OrderedSet.symmetricDifference(_: __owned Self) -> Self` (formSymmetricDifference.swift:40 / symmetricDifference.swift:45)

**Decision: accept.**

Same posture — canonical SetAlgebra dual on the symmetric-difference operation.

### 38. OC | dual-style-consistency | `OrderedSet.subtract(_: Self)` × `OrderedSet.subtracting(_: Self) -> Self` (subtract.swift:37 / subtracting.swift:45)

**Decision: accept.**

SetAlgebra dual via the **active/-ing rule** (not form-prefix — `subtract` doesn't have a `formSubtract` variant in SetAlgebra; the form-less variant `subtract` is mutating, `subtracting` is non-mutating). Both compute `self \ other` semantically.

### 39. OC | dual-style-consistency | `OrderedDictionary.merge(_:uniquingKeysWith:)` × `OrderedDictionary.merging(_:uniquingKeysWith:) -> Self` (OrderedDictionary.swift:826/922)

**Decision: accept.**

Canonical Swift dictionary merging convention; both methods apply the `uniquingKeysWith` combiner over the same input sequence and produce the same merged dictionary. The active/-ing naming rule is unambiguous here — the only difference is in-place mutation vs return-by-value. Spans the second new naming rule sub-family beyond the four SetAlgebra picks (#35–#38).

---

## idempotence-lifted (6 decisions) — NEW v1.19.B

### 40. Algo | idempotence (lifted) | `AdjacentPairsSequence.Iterator.next()` (AdjacentPairsSequence.swift)

**Decision: reject.**

`Iterator.next()` is the canonical stateful-incremental mutator: each call advances the iterator's internal cursor by one position and returns the corresponding element. Calling `iter.next()` twice and comparing the iterator state is NOT idempotent — the cursor advances by 2, not 1. The lifted shadow `(Iterator) -> Iterator` is NOT idempotent. Rubric §"Idempotence-lifted Reject" — stateful-incremental mutator class.

### 41. Algo | idempotence (lifted) | `Combinations.Iterator.next()` (Combinations.swift)

**Decision: reject.**

Same shape as #40 — Iterator.next() advances combinatorial state per call. Not idempotent.

### 42. Algo | idempotence (lifted) | `ChunkedIterator.advance()` (Chunked.swift)

**Decision: reject.**

Name variant of `next()` — same stateful-incremental class. `advance()` steps the chunked iterator forward by one chunk per call. Not idempotent.

### 43. OC | idempotence (lifted) | `_HashTable.BucketIterator.advance()` (_HashTable+BucketIterator.swift)

**Decision: reject.**

OC's bucket-chain Iterator-shape — `advance()` steps to the next bucket per call. Same Iterator-class reject as Algo picks #40–#42. Demonstrates the V1.19.B no-param admission is over-broad on the Iterator class regardless of corpus.

### 44. OC | idempotence (lifted) | `OrderedSet._isUnique()` (OrderedSet.swift internal CoW helper)

**Decision: accept.**

Internal copy-on-write uniqueness check + side-effect (typically pattern: `if !isKnownUniquelyReferenced(&_storage) { _storage = _storage.copy() }`). Calling `_isUnique()` twice on already-unique storage is a no-op the second time — the check fires positive, no copy, identical state. Lifted shadow is idempotent.

### 45. OC | idempotence (lifted) | `OrderedSet._regenerateHashTable()` (OrderedSet.swift internal hash-rebuild)

**Decision: accept.**

Hash-table rebuild from scratch. Regenerating twice produces identical state (the input element array is unchanged between calls; the hash table is purely a function of the array's hashes). Terminal mutator — fixed-point reached after one call. Lifted shadow is idempotent.

---

## composition-lifted (1 decision) — NEW v1.19.C

### 46. OC | composition (lifted) | `_HashTable.BucketIterator.advance(until: Int) -> Void` (_HashTable+BucketIterator.swift:252)

**Decision: reject.**

`advance(until: Int)` is **monotone-bounded**, not additive. The semantics are typically: "advance the bucket iterator forward until its position reaches at least `until`, or stop if already past." Calling `advance(until: a)` then `advance(until: b)` produces a final iterator at position `max(a, b)` (or whichever the iterator already passed first), NOT at position `a + b`. The composition property `op(op(s, a), b) == op(s, a + b)` fails. Per-construction rejection — the curated additive-action verb gate ('advance' ∈ `compositionVerbs`) is over-broad on monotone-bounded mutators. Rubric §"Composition-lifted Reject" — the parameter contributes monotonically, not additively.

---

## Summary

**Per-template results:**

| Template | Picks | Accept | Reject | Unknown | Acceptance rate (excl unknown) |
|---|---:|---:|---:|---:|---:|
| round-trip | 15 | 9 | 6 | 0 | 9/15 = **60.0%** |
| idempotence (non-lifted) | 6 | 0 | 4 | 2 | 0/4 = **0.0%** |
| commutativity | 3 | 1 | 2 | 0 | 1/3 = **33.3%** |
| associativity | 3 | 2 | 1 | 0 | 2/3 = **66.7%** |
| monotonicity | 4 | 3 | 1 | 0 | 3/4 = **75.0%** |
| inverse-pair (non-lifted) | 2 | 1 | 1 | 0 | 1/2 = **50.0%** |
| identity-element (non-lifted) | 1 | 0 | 1 | 0 | 0/1 = **0.0%** |
| **dual-style-consistency** (NEW) | 5 | 5 | 0 | 0 | 5/5 = **100.0%** |
| **idempotence-lifted** (NEW) | 6 | 2 | 4 | 0 | 2/6 = **33.3%** |
| **composition-lifted** (NEW) | 1 | 0 | 1 | 0 | 0/1 = **0.0%** |
| **All** | **46** | **23** | **21** | **2** | **23/44 = 52.3%** |

**Per-corpus results:**

| Corpus | Picks | Accept | Reject | Unknown | Acceptance rate |
|---|---:|---:|---:|---:|---:|
| OC | 20 | 11 | 8 | 1 | 11/19 = **57.9%** |
| CM | 18 | 9 | 9 | 0 | 9/18 = **50.0%** |
| Algo | 6 | 2 | 4 | 0 | 2/6 = **33.3%** |
| PLK | 2 | 1 | 0 | 1 | 1/1 = **100.0%** |
| **All** | **46** | **23** | **21** | **2** | **23/44 = 52.3%** |

**Aggregate trajectory:**

| Cycle | Surface | Sample | Accept | Reject | Unknown | Rate |
|---|---:|---:|---:|---:|---:|---:|
| 6 (v1.9) | 349 | 50 | 12 | 33 | 5 | 12/45 = **26.7%** |
| 14 (v1.17) | 229 | 50 | 16 | 30 | 4 | 16/46 = **34.8%** (+8.1pp) |
| **17 (v1.20)** | **335** | **46** | **23** | **21** | **2** | **23/44 = 52.3%** (+17.5pp; +25.6pp from cycle 6) |

**Outcome A** under the v1.20 plan §"Trajectory framing" thresholds (Aggregate ≥ 50% — suppression + new-class introduction is paying off; the loop is on trajectory toward §19's ≥70% target).

**Mechanism-class effectiveness (cycle-15 + cycle-16 contributions):**

- **Workstream A (V1.18.A) carrier-kind signal:** Score-only effect — no surface-count contribution; precision-positive on value-semantic carriers. Expected to lift several cycle-14 Possible-tier picks toward Likely (round-trip Likely → Strong shifts in test-suite calibration). The cycle-17 sample's existing-template rate-shift partially attributes here (e.g., round-trip 47% → 60% on the cycle-14 anchor picks reflects rate stability on the genuine inverse pairs, not new Workstream A accepts; new visibility on direction-pair OC inverse-pair pick #33 contributes 1 reject).
- **Workstream C (V1.18.C) dual-style consistency:** **5/5 = 100%** acceptance — by-construction precision via the curated naming-rule pairing constraint. 22 candidates introduced; 5 sampled; all accept. Net contribution to cycle-17 aggregate: +5 accepts, 0 rejects, 0 unknowns.
- **Workstream B (V1.19.B–D) lifted-mutation admission:** **2/7 = 28.6%** acceptance across the 6 idempotence-lifted + 1 composition-lifted picks. Net contribution: +2 accepts, +5 rejects. The over-broad-admission concern flagged in V1.20.A (Iterator-shape over-rejection on idempotence-lifted; monotone-bounded over-rejection on composition-lifted) is **confirmed** — 4/6 idempotence-lifted picks reject because the lift admits Iterator state-mutators, and 1/1 composition-lifted picks reject because the lift admits monotone-bounded mutators alongside additive ones.

**Cycle-18 priority list rotated post-v1.20:**

1. **NEW (V1.20.D / cycle-17 finding): Iterator-shape suppression on idempotence-lifted.** All 4 Algo/OC Iterator-class picks (#40-#43) reject; the V1.19.B no-param admission on `IteratorProtocol`-conforming carriers is over-broad. Mechanism: detect `mutating func next()` / `mutating func advance()` shapes where the carrier conforms to `IteratorProtocol` (textual conformance match) and veto from the lifted-idempotence path. Magnitude estimate: closes 20 Algorithms + 4 OC = ~24 v1.19 candidates, lifts the lifted-idempotence acceptance rate from 33% (2/6) to ~67% (2/2 surviving picks) on the v1.19 corpora.
2. **NEW (V1.20.D / cycle-17 finding): `composition-lifted` monotone-bounded suppression.** The lone composition-lifted pick (`advance(until: Int)`) rejects because the parameter contributes monotonically, not additively. Mechanism: extend `CompositionTemplate.curatedVerbs` rejection to include `advance(until:)` / `seek(to:)` / `bound(at:)` patterns, OR add an `until:` / `to:` / `at:` parameter-label counter-signal. Magnitude estimate: closes the 1 v1.19 composition-lifted candidate.
3. **Math-library forward-function counter on idempotence + round-trip** (carried forward from v1.18 / cycle-15 / cycle-16). Cycle-17 confirms `exp` / `log` / `sqrt` non-lifted idempotence is a 0% rate; the counter would suppress these on idempotence (CM picks #18-#20). **Cycle-17 measurement justifies this priority.**
4. **Fixed-point-name positive signal on idempotence (non-lifted path)** (carried forward from cycle-15 / cycle-16). Lifted path already covers it via curated verbs.
5. **FP approximate-equality template arm** (carried forward).
6. **Lift admission relaxation from strict to permissive** (carried forward from v1.19 plan; cycle-17 measurement does not yet motivate; revisit at cycle-18).
7. **`Signal.Kind.liftedFromMutation` magnitude re-baselining** (carried forward; cycle-17 lifted-rate 33% does not yet motivate +10 → +5 demotion; revisit at cycle-18).

The **#1 + #2 priorities are direct cycle-17 findings** — they target specific reject classes the cycle-17 triage measured. The cycle-15 / cycle-16 carry-forwards (#3 onwards) are confirmed by cycle-17 data but were already in the rotation.
