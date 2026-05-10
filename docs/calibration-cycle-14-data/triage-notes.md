# Cycle-14 Triage Notes

**Captured:** 2026-05-09. Single-runner triage by Claude on the v1.16.0 release tag (`9e36efd`). v1.17 is binary-equivalent to v1.16.0; this triage is on the v1.16 229-surface as captured in [`../calibration-cycle-13-data/`](../calibration-cycle-13-data/).
**Rubric:** [`../cycle-14-triage-rubric.md`](../cycle-14-triage-rubric.md) — per-template criteria are verbatim from cycle 6.
**Sample manifest:** [`sample-manifest.md`](sample-manifest.md)
**Machine-readable decisions:** [`triage-decisions.json`](triage-decisions.json)

Per-decision rationale below. Format: `### N. Corpus | template | site` followed by the decision verdict and rationale paragraph.

---

## round-trip (20 decisions)

### 1. OC | round-trip | `_value(forBucketContents:)` × `_bucketContents(for:)` (_HashTable+UnsafeHandle.swift:201/219)

**Decision: accept.**

Signatures `(UInt64) -> Int?` ↔ `(Int?) -> UInt64` form the canonical asymmetric codec shape — encoding an `Int?` bucket index into a `UInt64` storage word and decoding back. The underscore-prefixed names indicate an internal codec, not a public API; rubric §"Single-runner triage caveat" calls this exact `_HashTable._bucketContents(for:)` example out as "read-only-via-source-code", but cycle-6 pick #5 (`bucket(after:)` × `bucket(before:)` in the same file) was accepted on the type-shape pattern alone, and the codec shape here is even stronger evidence (the asymmetric `(T) -> U`/`(U) -> T` typing is the rubric's quoted "type signatures align" criterion). The legitimate domain restriction (a well-formed bucket-contents word vs an arbitrary UInt64) is acceptable per rubric ("clear convention for the legitimate domain").

### 2. CM | round-trip | `exp(_:)` × `expMinusOne(_:)` (Complex+ElementaryFunctions.swift:56/71)

**Decision: reject.**

Both forward exponential variants. `expMinusOne(z) = exp(z) - 1` is the accurate-near-zero variant; not the inverse of `exp`. Rate-stability check against cycle-6 pick #7 (also reject).

### 3. CM | round-trip | `exp(_:)` × `cosh(_:)` (56/141)

**Decision: reject.**

Cross-product. `cosh(z) = (exp(z) + exp(-z))/2` is forward, not inverse. Rate-stability check against cycle-6 pick #8.

### 4. CM | round-trip | `exp(_:)` × `sinh(_:)` (56/171)

**Decision: reject.**

Cross-product. Both forward exponential-family functions.

### 5. CM | round-trip | `exp(_:)` × `log(_:)` (56/231)

**Decision: accept.**

Genuine canonical inverse pair on the principal branch. `log(exp(z)) = z` mod `2πi`; `exp(log(w)) = w` for nonzero `w`. The legitimate-domain restriction (principal branch) is exactly the rubric's quoted "URL.init(string:) succeeds on a documented subset" pattern. Rate-stability check against cycle-6 pick #11.

### 6. CM | round-trip | `exp(_:)` × `sqrt(_:)` (56/442)

**Decision: reject.**

Forward-forward. `sqrt(exp(z)) = exp(z/2) ≠ z`.

### 7. CM | round-trip | `expMinusOne(_:)` × `log(_:)` (71/231)

**Decision: reject.**

Structural near-miss. `expMinusOne`'s by-design inverse is `log(onePlus:)` (the accurate-near-zero variant of `log(1+x)`), not `log(_:)`. The numerical-variant pair was deliberately split into two functions to avoid loss-of-precision near zero; pairing the accurate variant of one direction with the standard variant of the other gives `log(expMinusOne(z)) = log(exp(z) - 1)`, which is neither identity nor a numerically-meaningful approximation. Rejection here is consistent with the rubric's "asymmetric postconditions" criterion — `expMinusOne` has a precision-positive subdomain (small `|z|`) that doesn't align with `log`'s domain.

### 8. CM | round-trip | `cosh(_:)` × `sinh(_:)` (141/171)

**Decision: reject.**

Both forward hyperbolic. Cycle-6 pick #10 rate-stability.

### 9. CM | round-trip | `cosh(_:)` × `acosh(_:)` (141/387)

**Decision: accept.**

Genuine inverse pair on the principal branch. `acosh(cosh(z)) = z` for `z` in the appropriate strip; `cosh(acosh(w)) = w` for `w` in the appropriate domain. Same principal-branch-domain caveat as pick #5.

### 10. CM | round-trip | `sinh(_:)` × `asinh(_:)` (171/396)

**Decision: accept.**

Genuine principal-branch inverse pair. Same logic as pick #9.

### 11. CM | round-trip | `tanh(_:)` × `atanh(_:)` (187/402)

**Decision: accept.**

Genuine principal-branch inverse pair. Same logic.

### 12. CM | round-trip | `cos(_:)` × `acos(_:)` (211/364)

**Decision: accept.**

Genuine principal-branch inverse pair. Same logic.

### 13. CM | round-trip | `sin(_:)` × `asin(_:)` (217/372)

**Decision: accept.**

Genuine principal-branch inverse pair. Rate-stability check against cycle-6 pick #12.

### 14. CM | round-trip | `tan(_:)` × `atan(_:)` (224/381)

**Decision: accept.**

Genuine principal-branch inverse pair. Same logic.

### 15. CM | round-trip | `log(_:)` × `log(onePlus:)` (231/331)

**Decision: reject.**

Two-overload forward pair. Both compute logarithms of related arguments; not inverses of each other. The function-name match (both named `log`) creates a type-symmetry signal that the engine fires on, but the semantic relationship is `log(onePlus: x) = log(1 + x)` — both are forward maps from `Complex → Complex`.

### 16. CM | round-trip | `log(_:)` × `sqrt(_:)` (231/442)

**Decision: reject.**

Forward-forward cross-product. `log(sqrt(z)) = log(z)/2 ≠ z`.

### 17. CM | round-trip | `expMinusOne(_:)` × `sqrt(_:)` (71/442)

**Decision: reject.**

Forward-forward cross-product involving the accurate-variant exp. Same noise class as pick #16.

### 18. CM | round-trip | `atan(_:)` × `atanh(_:)` (381/402)

**Decision: reject.**

Same `(Complex) -> Complex` shape; related by the analytic-continuation identity `atanh(z) = -i·atan(iz)` but **not** functional inverses. Both are inverse functions of their respective forward maps (tan, tanh) — pairing them yields `atan(atanh(z)) ≠ z` in general. The sample-manifest flag for this pick was specifically to test whether the rater treats analytic-continuation-related pairs as round-trips; the answer is no, the rubric requires functional-inverse semantics.

### 19. Algo | round-trip | `endOfChunk(startingAt:)` × `startOfChunk(endingAt:)` (Chunked.swift:79/122)

**Decision: accept.**

Genuine inverse pair on the chunk-boundary domain (Base.Index restricted to chunk-start/end positions). Both are `(Base.Index) -> Base.Index`; the legitimate-domain restriction is the rubric-permitted pattern. Rate-stability check against cycle-6 pick #15.

**Suppression-vs-correctness note.** This pair is the cycle-15 v1.18 priority #1 suppression target (stride-style label extension). Cycle-14's accept verdict is **not** a vote against suppression — the rubric measures whether the property *holds*, not whether the auto-emitted property test would be *useful*. The pair holds on chunk-boundary domain (correctness ≥); suppression is justified separately on usability grounds (auto-emitted tests need chunk-boundary generators that v1's TestLifter doesn't synthesise yet, so the candidate is noise from a maintainer-output perspective). Cycle-14 records this nuance to surface it in the cycle-15 priority decision.

### 20. Algo | round-trip | `log(_:)` × `log(onePlus:)` (RandomSample.swift:25/30)

**Decision: reject.**

Two-overload forward pair on Double. Same shape + verdict as CM pick #15.

---

## idempotence (12 decisions)

### 21. OC | idempotence | `_description(type:)` (_HashTable+CustomStringConvertible.swift:29)

**Decision: reject.**

`(String) -> String` formatter that wraps the input in a structural format string (e.g., `"OrderedSet<X>"` or `"_HashTable<X>"`). Applying twice yields `"_HashTable<_HashTable<X>>"` ≠ `"_HashTable<X>"`. The function's purpose is to wrap, not to canonicalise.

### 22. OC | idempotence | `firstOccupiedBucketInChain(with:)` (_HashTable+UnsafeHandle.swift:325)

**Decision: unknown.**

The function name suggests "given a Bucket position, return the first occupied Bucket along the probe chain starting here." If the input is already occupied the function should return it; if not, it advances. Either way, applying twice should yield the same result — *if* the probe chain is unchanged between calls. The function is a method on `_HashTable.UnsafeHandle`, fundamentally a stateful view over the table. Whether bucket-chain content is invariant between two consecutive calls is internal-state-dependent; rubric mandates `unknown` on internal-state ambiguity (it explicitly excludes "Internal state determines the answer" cases from binary verdicts).

### 23. CM | idempotence | `exp(_:)` (Complex+ElementaryFunctions.swift:56)

**Decision: reject.**

`exp(exp(z)) = e^(e^z) ≠ exp(z)`. Rate-stability check against cycle-6 pick #21.

### 24. CM | idempotence | `log(_:)` (231)

**Decision: reject.**

`log(log(z)) ≠ log(z)`. Rate-stability check against cycle-6 pick #22.

### 25. CM | idempotence | `sin(_:)` (217)

**Decision: reject.**

`sin(sin(z)) ≠ sin(z)`; non-trivial composition.

### 26. CM | idempotence | `asin(_:)` (372)

**Decision: reject.**

`asin(asin(z)) ≠ asin(z)`; same logic as forward-trig.

### 27. CM | idempotence | `tanh(_:)` (187)

**Decision: reject.**

`tanh(tanh(z))` is contractive (approaches 0 under iteration); ≠ `tanh(z)`.

### 28. CM | idempotence | `sqrt(_:)` (442)

**Decision: reject.**

`sqrt(sqrt(z)) = z^(1/4) ≠ z^(1/2)` generally; idempotent only at fixed points 0 and 1.

### 29. Algo | idempotence | `endOfChunk(startingAt:)` (Chunked.swift:79)

**Decision: reject.**

The function advances the index by chunk size. `endOfChunk(endOfChunk(x))` is the next chunk's end, not `endOfChunk(x)`. Rate-stability check against cycle-6 pick #25.

### 30. Algo | idempotence | `sizeOfChunk(offset:)` (Chunked.swift:243)

**Decision: reject.**

The `offset` argument is a chunk-position index; the return is a chunk-size. `sizeOfChunk(sizeOfChunk(0))` treats a size-value as a position-index — type-correct but semantically nonsensical, and even if interpreted, the result depends on the table layout in a way that doesn't match `sizeOfChunk(0)` except by coincidence.

### 31. Algo | idempotence | `log(_:)` (RandomSample.swift:25)

**Decision: reject.**

Internal `(Double) -> Double` natural-log used in random sampling. `log(log(x)) ≠ log(x)`; same logic as CM pick #24.

### 32. PLK | idempotence | `nearMissLines(_:)` (ViolationFormatter.swift:58)

**Decision: unknown.**

`([String]?) -> [String]?` extraction/filtering function. Without source-read, the rater cannot determine whether applying twice (`nearMissLines(nearMissLines(input))`) yields the same as one call. The function name suggests an extraction pass that might be naturally idempotent (extract-near-misses-from-already-extracted-near-misses returns the same list); equally plausibly, the function applies a transform that doesn't fixed-point on its own output. Rate-stability check against cycle-6 pick #28 (also unknown).

---

## commutativity (5 decisions)

### 33. OC | commutativity | `index(_:offsetBy:)` (OrderedDictionary+Elements.SubSequence.swift:263)

**Decision: reject.**

`(Int, Int) -> Int` shape with first-arg-position, second-arg-offset semantics. Rubric mandates reject when "Function name suggests directionality" — the labels `(_:offsetBy:)` are exactly the directional pattern. Underlying integer addition does commute, but the rubric scores by name + signature, not abstract-op semantics. Rate-stability check against cycle-6 pick #29.

### 34. OC | commutativity | `distance(from:to:)` (OrderedDictionary+Elements.swift:272)

**Decision: reject.**

`distance(from: a, to: b) = b - a`; `distance(from: b, to: a) = a - b = -(b - a)`. Anti-commutative. Cycle-6 pick #30 rate-stability (different file in OC, same shape).

### 35. OC | commutativity | `index(_:offsetBy:)` (OrderedSet+RandomAccessCollection.swift:176)

**Decision: reject.**

Same shape and verdict as pick #33; OrderedSet vs OrderedDictionary namespace.

### 36. CM | commutativity | `-(z:w:)` (Complex+AdditiveArithmetic.swift:29)

**Decision: reject.**

Subtraction. `z - w ≠ w - z` (anti-commutative). Rate-stability check against cycle-6 pick #32.

### 37. CM | commutativity | `_relaxedAdd(_:_:)` (Complex+AlgebraicField.swift:171)

**Decision: accept.**

Internal relaxed-precision addition. Abstract addition commutes. The FP-rounding caveat from the discover output (`-10` weight) is the standard concern that approximate-equality property tests address; that's a v1.18+ trajectory item (FP approximate-equality template arm, carried forward in the v1.17 plan §"Out of scope"). Rate-stability check against cycle-6 pick #33.

---

## associativity (5 decisions)

### 38. OC | associativity | `index(_:offsetBy:)` (OrderedDictionary+Elements.SubSequence.swift:263)

**Decision: accept.**

Integer-offset addition associates: `(i + n) + m = i + (n + m)`. Same site as commutativity pick #33 — interesting cross-template consistency check (commutativity-reject + associativity-accept on the same op, mirroring cycle-6's pattern for the same site). The accept here is not in conflict with the commutativity reject: the operation is **non-commutative** under the labels-suggest-directionality argument but **associative** under the integer-arithmetic argument. Rate-stability check against cycle-6 pick #34.

### 39. OC | associativity | `distance(from:to:)` (OrderedSet+RandomAccessCollection.swift:222)

**Decision: reject.**

`distance(distance(a, b), c) = distance(b - a, c) = c - (b - a) = c - b + a`; `distance(a, distance(b, c)) = distance(a, c - b) = (c - b) - a = c - b - a`. The two associations differ by a sign on `a` (or equivalently, on the embedded distance result). Rate-stability check against cycle-6 pick #35 (different reasoning path — cycle-6's was "not a combine op; no associativity"; cycle-14's is the explicit anti-associativity calculation. Same conclusion).

### 40. OC | associativity | `index(_:offsetBy:)` (OrderedDictionary+Values.swift:228)

**Decision: accept.**

Same shape and verdict as pick #38 (different file).

### 41. CM | associativity | `/(z:w:)` (Complex+AlgebraicField.swift:37)

**Decision: reject.**

Division. `(a / b) / c = a / (b·c)` ≠ `a / (b / c) = (a · c) / b`. Non-associative.

### 42. CM | associativity | `_relaxedMul(_:_:)` (Complex+AlgebraicField.swift:176)

**Decision: accept.**

Internal relaxed-precision multiplication. Multiplication associates. Same FP-rounding caveat as pick #37 (`_relaxedAdd`); same v1.18+ approximate-equality trajectory.

---

## monotonicity (6 decisions)

### 43. OC | monotonicity | `minimumCapacity(forScale:)` (_HashTable+Constants.swift:58)

**Decision: accept.**

Capacity-from-scale function — as scale increases, minimum capacity increases monotonically. Rate-stability check against cycle-6 pick #39.

### 44. OC | monotonicity | `_description(type:)` (_HashTable+CustomStringConvertible.swift:29)

**Decision: unknown.**

Same site as idempotence pick #21. The monotonicity claim is `a ≤ b ⟹ f(a) ≤ f(b)` for string lex order on input and output. If the function is a pure-wrap (`f(x) = "OrderedSet<" + x + ">"`), lex monotonicity holds because the shared prefix `"OrderedSet<"` is constant and lex comparison is character-by-character. If the function applies any input-altering transformation (case normalisation, escape sequences, length truncation), lex monotonicity can break. Without source-read, the rater cannot verify the pure-wrap assumption; rubric mandates `unknown` on genuine ambiguity.

### 45. OC | monotonicity | `index(after:)` (OrderedDictionary+Elements.SubSequence.swift:206)

**Decision: accept.**

Collection-protocol increment, strictly monotonic on Int (increment-by-1).

### 46. Algo | monotonicity | `sizeOfChunk(offset:)` (Chunked.swift:243)

**Decision: reject.**

Chunk sizes vary by chunk position (chunks at boundaries can be smaller than interior chunks); not monotonic in offset. Same site as idempotence pick #30.

### 47. PLK | monotonicity | `walkCap(for:)` (BidirectionalCollectionLaws.swift:237)

**Decision: unknown.**

The function is generic on `C: BidirectionalCollection` returning `Int`. The Comparable codomain (`Int`) is well-defined but `BidirectionalCollection` has no canonical Comparable conformance — the input has no canonical ≤ to compare against. The engine appears to have flagged this on a "compare-by-count" assumption (count is the natural ordered measure on collections), but whether `walkCap` scales monotonically with count is implementation-dependent and read-only-via-source-code per rubric. Rate-stability check against cycle-6 pick #43 (same posture).

### 48. PLK | monotonicity | `format(_:)` (ViolationFormatter.swift:10)

**Decision: reject.**

`(CheckResult) -> String`. Enum-input has a semantic order (e.g., `.success < .failure` semantically), but the format function destroys the input's semantic ordering by mapping each enum case to a non-related string. The rubric's reject criterion ("output type is not comparable in a way that aligns with the input ordering") fits exactly. Rate-stability check against cycle-6 pick #42.

---

## inverse-pair (1 decision)

### 49. Algo | inverse-pair | `endOfChunk(startingAt:)` × `startOfChunk(endingAt:)` (Chunked.swift:79/122)

**Decision: accept.**

Same site as round-trip pick #19. The inverse-pair template requires both `f(g(x)) == x` and `g(f(y)) == y`. On the chunk-boundary domain (chunk-start indices for one direction, chunk-end indices for the other), both directions hold by construction. Same suppression-vs-correctness note as pick #19: cycle-14's accept is correctness-positive; cycle-15's planned suppression is usability-positive. The two are not in conflict.

This is the lone inverse-pair candidate at v1.16, and its acceptance produces a per-template rate of 1/1 = 100% — but with n=1 the rate is uninterpretable as a population statistic. The cycle-14 finding is "the lone surviving pre-cycle-15 inverse-pair candidate is correctness-positive", not "inverse-pair has a 100% acceptance rate at v1.16".

---

## identity-element (1 decision)

### 50. CM | identity-element | `rescaledDivide(_:_:)` × `Complex.zero` (Complex+AlgebraicField.swift:48 / Complex+AdditiveArithmetic.swift:19)

**Decision: reject.**

The identity-element claim is `rescaledDivide(z, Complex.zero) == z` and/or `rescaledDivide(Complex.zero, z) == z`. The first direction fails because division by zero is undefined (NaN/Inf in FP), not the input `z`. The second direction fails because `0 / z = 0`, not `z`. Identity-element property does not hold on either direction. Rate-stability check against cycle-6 pick #50.

This is the lone identity-element candidate at v1.16 and the only Likely-tier (Score 70) pick in the cycle-14 sample; the Possible-tier focus rules don't apply. The rate of 0/1 = 0% mirrors cycle-6's 0/1.
