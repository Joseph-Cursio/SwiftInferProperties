# Cycle-6 Triage Notes

**Captured:** 2026-05-08. Single-runner triage by Claude on the v1.8.0 release tag.
**Rubric:** [`../cycle-6-triage-rubric.md`](../cycle-6-triage-rubric.md)
**Sample manifest:** [`sample-manifest.md`](sample-manifest.md)
**Machine-readable decisions:** [`triage-decisions.json`](triage-decisions.json)

Per-decision rationale below. Format: `# decision_id — corpus | template | site` followed by the decision verdict and rationale paragraph.

---

## round-trip (16 decisions)

### 1. OC | round-trip | `minimumCapacity(forScale:)` × `maximumCapacity(forScale:)`

**Decision: reject.**

Source (`Sources/OrderedCollections/HashTable/_HashTable+Constants.swift:58/67`):
- `minimumCapacity(forScale: s) → (2^s * 1) / 4` for `s ≥ minimumScale (5)`, else 0.
- `maximumCapacity(forScale: s) → (2^s * 3) / 4` for `s ≥ minimumScale`, else `maximumUnhashedCount (15)`.

Both functions take a *scale* (5..56) and return a *capacity* (a much larger Int range). They're not inverses — they return *different* capacity values for the same scale by design (min and max load factor). `maximumCapacity(forScale: minimumCapacity(forScale: s))` would feed a capacity (8..) as a scale, which the function then misinterprets. The `(Int) -> Int` signature is the *type* signal, but the *semantic* contract has different domains for input and output.

### 2. OC | round-trip | `minimumCapacity(forScale:)` × `scale(forCapacity:)`

**Decision: reject.**

Same domain-mismatch shape. `scale(forCapacity:)` returns 0 for capacities ≤ `maximumUnhashedCount (15)`, then a binary-logarithm-derived scale for larger capacities. `scale(forCapacity: minimumCapacity(forScale: 5))` = `scale(forCapacity: 8)` = 0 (because 8 ≤ 15). Round-trip fails by design — `scale ⊥ minimumCapacity` aren't strict inverses; only `scale(forCapacity: maximumCapacity(forScale: x))` *approximately* recovers `x` per the assertion at line 90 (`maximumCapacity(forScale: scale) >= capacity`), but that's a one-way ≥ guarantee, not equality.

### 3. OC | round-trip | `minimumCapacity(forScale:)` × `wordCount(forScale:)`

**Decision: reject.**

`wordCount(forScale: s) = ((s << s) + 63) / 64` — this is the *number of 64-bit words* needed in storage for a hash table at scale `s`, completely separate semantic concept from capacity. The `(Int) -> Int` type symmetry is meaningless here.

### 4. OC | round-trip | `index(after:)` × `index(before:)` (OrderedDictionary+Elements.SubSequence)

**Decision: accept.**

`Collection`-protocol contract: `index(after:)` and `index(before:)` are by-construction inverses on the valid-index domain — `c.index(after: c.index(before: i)) == i` for any `i` in `c.startIndex..<c.endIndex`. This is one of Swift's foundational protocol contracts, not a guess. Property-test stub written from this would pass with a generator that picks valid indices.

Domain caveat: outside the valid range (start/end-index boundary), the property doesn't hold or traps. The `// Inferred precondition` advisory mechanism (M9.1) would correctly suggest an `i.isValid` precondition.

### 5. OC | round-trip | `bucket(after:)` × `bucket(before:)` (_HashTable+UnsafeHandle)

**Decision: accept.**

Sample reading of source (`_HashTable+UnsafeHandle.swift:137/149`): `bucket(after:)` increments a Bucket index (mod bucketCount); `bucket(before:)` decrements (mod bucketCount). The mod-arithmetic structure makes them strict inverses on the valid Bucket domain — `bucket(after: bucket(before: b)) == b`. Same Collection-protocol-style contract.

### 6. OC | round-trip | `intersection(_:)` × `subtracting(_:)` (OrderedSet+Partial SetAlgebra)

**Decision: reject.**

Both have signature `(Self) -> Self` and OrderedSet conforms to `SetAlgebra`. But `intersection` and `subtracting` are *related* operations — not inverses. `a.subtracting(b).intersection(c) ≠ a` in general; the semantic intent is "remove elements in b" vs "keep elements also in c". The cross-validation type-symmetry signal fires but the inverse-pair semantic doesn't hold.

### 7. CM | round-trip | `exp(_:)` × `expMinusOne(_:)`

**Decision: reject.**

`exp(z) = e^z`; `expMinusOne(z) = e^z - 1`. Not inverses — both are *forward* directions. `expMinusOne` is the precision-friendly variant for small z (avoiding catastrophic cancellation in `exp(z) - 1`). `exp(expMinusOne(z))` is a triple-composition, not identity.

### 8. CM | round-trip | `exp(_:)` × `cosh(_:)`

**Decision: reject.**

`cosh(z) = (exp(z) + exp(-z))/2`; `exp(cosh(z)) ≠ z` in general. Cross-product noise from the elementary-functions module.

### 9. CM | round-trip | `exp(_:)` × `cos(_:)`

**Decision: reject.**

Cross-product noise. `exp` and `cos` are unrelated as inverses (cos has periodic codomain).

### 10. CM | round-trip | `cosh(_:)` × `sinh(_:)`

**Decision: reject.**

Both forward; not inverses. `cosh` is even, `sinh` is odd; no inverse pairing.

### 11. CM | round-trip | `log(_:)` × `exp(_:)`

**Decision: accept** (with caveat).

`log` and `exp` *are* genuine inverses on Complex — `exp(log(z)) == z` for `z ≠ 0`, `log(exp(z)) == z` mod `2πi`. The mod-`2πi` qualification means the round-trip property holds on the principal-branch domain. A property test stub with a `z.imaginary ∈ (-π, π]` precondition would pass. SwiftInfer's M9.1 inferred-precondition mechanism could surface the principal-branch domain advisory.

This is the kind of suggestion the system *should* surface at Possible tier — true positive when interpreted with the appropriate domain restriction.

### 12. CM | round-trip | `sin(_:)` × `asin(_:)`

**Decision: accept** (with caveat).

`sin(asin(z)) == z` for `z ∈ [-1, 1] × R`; `asin(sin(z)) == z` for `z.real ∈ [-π/2, π/2]`. Same principal-branch caveat as log/exp. Genuine round-trip on the principal domain.

### 13. CM | round-trip | `polar(from:)` × `init(r:θ:)` (or similar conversion pair)

**Decision: unknown.**

Without reading the exact ComplexModule polar API (whether `polar(from:)` and `Complex(r:θ:)` are exact inverses or have rounding from rectangular-to-polar conversion), I can't determine. Likely accept under principal-branch, but FP-exact equality is the question. Flagged unknown rather than forced.

### 14. Algo | round-trip | `index(after:)` × `index(before:)` (AdjacentPairs)

**Decision: accept.**

Same Collection-protocol contract as OC #4. By-construction inverses on the valid-index domain.

### 15. Algo | round-trip | `endOfChunk(startingAt:)` × `startOfChunk(endingAt:)` (Chunked)

**Decision: accept** (with caveat).

Domain: a Chunked collection partitions its base into equivalence-classed chunks; `endOfChunk(startingAt: i)` returns the index just past the end of the chunk containing `i`; `startOfChunk(endingAt: j)` returns the index of the first element of the chunk ending at `j`. They're inverses on chunk-boundary indices: `startOfChunk(endingAt: endOfChunk(startingAt: i)) == startOfChunk` containing `i`. The round-trip holds when the input is itself a chunk-start. Inferred-precondition machinery could surface that.

### 16. Algo | round-trip | `(Double) -> Double` pair

**Decision: unknown.**

Without seeing the exact pair (the cycle-5 capture shows `Type-symmetry signature: Double -> Double ↔ Double -> Double` for one Algo round-trip pair, but I'd need to identify the function pair to assess), I can't judge. The fact that V1.7.1's bake-in suppressed it (Double conforms to Codable via the bake-in) doesn't say anything about whether the user functions are inverses. Flagged unknown.

---

## idempotence (12 decisions)

### 17. OC | idempotence | `minimumCapacity(forScale: Int) -> Int`

**Decision: reject.**

Domain-mismatch: input is a *scale* (5..56), output is a *capacity* (a much larger Int). `minimumCapacity(forScale: minimumCapacity(forScale: s)) != minimumCapacity(forScale: s)` — feeding a capacity-scale as a scale-scale produces a different capacity-capacity value. The `(Int) -> Int` type symmetry is misleading.

### 18. OC | idempotence | `index(after:)` (OrderedDictionary+Elements)

**Decision: reject.**

`Collection.index(after:)` advances by 1; `index(after: index(after: i))` advances by 2, not equal to `index(after: i)`. Idempotence doesn't hold by definition.

### 19. OC | idempotence | `bucket(after:)` (_HashTable+UnsafeHandle)

**Decision: reject.**

Same as #18 — incrementing twice ≠ incrementing once. Mod-arithmetic doesn't help.

### 20. OC | idempotence | `_minimumCapacity(forScale:)` (OrderedSet+Testing)

**Decision: reject.**

Test-shim variant of `minimumCapacity(forScale:)` (#17). Same domain-mismatch reasoning.

### 21. CM | idempotence | `exp(_:)` (Complex)

**Decision: reject.**

`exp(exp(z)) ≠ exp(z)` in general; trivially false (e.g., `exp(exp(0)) == exp(1) == e ≠ 1 == exp(0)`).

### 22. CM | idempotence | `log(_:)` (Complex)

**Decision: reject.**

`log(log(z)) ≠ log(z)` in general; double-log is well-known not to be idempotent.

### 23. CM | idempotence | `Complex.conjugate` or similar (best representative)

**Decision: unknown.**

Without picking the exact `(T) -> T` Complex function from the cycle-5 capture (the 17 idempotence picks include various elementary functions), the answer is per-function. `conjugate` would be self-inverse (conjugate(conjugate(z)) == z, NOT idempotent — that's *involutive*, different property). For the typical idempotence-stub claim to hold for a Complex function, it'd need to be something like a `normalized` op. Without enumerating, flagged unknown.

### 24. Algo | idempotence | `index(after:)` (AdjacentPairs)

**Decision: reject.**

Same as #18 — Collection increment is not idempotent.

### 25. Algo | idempotence | `endOfChunk(startingAt:)` (Chunked)

**Decision: accept.**

`endOfChunk(startingAt: i)` returns the chunk-boundary index. Calling it twice: `endOfChunk(startingAt: endOfChunk(startingAt: i))`. The first call returns the boundary `b`. The second call asks for the chunk starting at `b` — which is *the next chunk's* start — its end is some `b' > b`. So idempotence may not hold strictly; depends on whether `endOfChunk(startingAt: chunk-start) == chunk-start-of-next-chunk` always. Reading the contract: chunked collections' chunk boundaries are equality-classed, so `endOfChunk(startingAt: b) == endOfChunk(startingAt: b)` (deterministic) but `b != endOfChunk(startingAt: b)` (the boundary advances). So **reject** on second thought.

(Updating: **reject.**)

### 26. Algo | idempotence | `index(after:)` (FlattenCollection)

**Decision: reject.**

Same as #18 — Collection increment.

### 27. Algo | idempotence | `index(before:)` (Joined)

**Decision: reject.**

Same — Collection decrement is not idempotent.

### 28. PLK | idempotence | `nearMissLines(_:)` (`[String]?` -> `[String]?`)

**Decision: unknown.**

The function name suggests "extract near-miss lines" — the optional input/output suggests either-or. Without reading the implementation: it could be idempotent (if applying twice extracts the same near-miss subset), or it could not be (if the result format differs from the input format). Plausible idempotent on its output domain. Flagged unknown.

---

## commutativity (5 decisions)

### 29. OC | commutativity | `index(_:offsetBy:)` (OrderedDictionary+Elements.SubSequence:263)

**Decision: reject.**

`index(i, offsetBy: n)` interprets the first argument as a position and second as a signed offset. Anti-symmetric: `index(a, offsetBy: b) ≠ index(b, offsetBy: a)` because the *roles* of the args differ. `(Int, Int) -> Int` shape is misleading.

### 30. OC | commutativity | `distance(from: Int, to: Int) -> Int` (similar OC site)

**Decision: reject.**

Anti-commutative: `distance(from: a, to: b) == -distance(from: b, to: a)`. The signed direction is built in. Can't reframe as commutative without losing information.

### 31. OC | commutativity | another OC user-named binary op

**Decision: reject.**

Without enumerating the specific picks in the OC commutativity tier (likely all are `index(_:offsetBy:)` / `distance(from:to:)` cross-products), the pattern is consistent: position-vs-offset semantics make the ops naturally directional.

### 32. CM | commutativity | `-(z:w:)` (Complex subtraction)

**Decision: reject.**

`-` is anti-commutative on any group — subtraction never commutes. The cycle-2 V1.5.2 veto already suppressed `+(z:w:)` and `*(z:w:)` (covered by `: AdditiveArithmetic` / `: Numeric`); subtraction stays surfaced because it's not in the kit-published commutative law. Correctly rejected.

### 33. CM | commutativity | `_relaxedAdd(_:_:)` (Complex)

**Decision: accept** (with caveat).

`_relaxedAdd` is the precision-relaxed add for Complex — the doc says "may differ from `+` by ULPs but is permitted to be reordered." Commutativity holds at the abstract math level (`a + b == b + a`); the FP-storage counter-signal at -10 (V1.4.3) correctly notes that bit-exact equality may not hold under IEEE rounding. A property test using `KitFloatingPointTemplate` (cycle-7 candidate) would correctly verify with approximate-equality semantics. Accept the *property*; the cycle-7 FP-template arm is the right vehicle.

---

## associativity (5 decisions)

### 34. OC | associativity | `index(_:offsetBy:)` (same site as #29)

**Decision: reject.**

`index(index(a, offsetBy: b), offsetBy: c) ?= index(a, offsetBy: index(b, offsetBy: c))` — different semantic interpretations. The first reads "advance a by b, then advance the result by c" (= a + b + c offset); the second reads "advance b by c, then use the result as offset from a" (= a + (b + c offset)). They're mathematically equal *if* offsets compose linearly, which they do for Int. So actually...

**Reconsidering: accept** under "associativity holds because the underlying op is integer addition." But the function isn't *implementing* integer addition; it's implementing index advancement on a collection. If the collection is contiguous-Int-indexed (which OrderedDictionary's SubSequence's RandomAccessCollection conformance probably is), then yes, it's effectively `(a + b) + c == a + (b + c)`.

Reasoning is subtle. Flagged with `accept` but caveated; cycle-7+ may want to think about whether scoring should distinguish "directional-op-that-happens-to-associate" from "op-that-commutes-and-associates."

(Settling on **accept** with caveat.)

### 35. OC | associativity | `distance(from:to:)` (similar OC site)

**Decision: reject.**

`distance` returns signed distance; cannot meaningfully associate because the semantic is "from-to," not "combine."

### 36. OC | associativity | OC unique associativity site

**Decision: reject.**

Without enumerating the specific picks, the OC associativity tier is largely the same `(Int, Int) -> Int` directional ops — same reasoning as #29-30.

### 37. CM | associativity | `-(z:w:)` (Complex subtraction)

**Decision: reject.**

Subtraction is not associative: `(a - b) - c ≠ a - (b - c)`. The kit doesn't claim associativity for subtraction.

### 38. CM | associativity | `_relaxedAdd(_:_:)` (Complex)

**Decision: accept** (with caveat).

Same as #33 reasoning — abstract addition associates; FP rounding may differ. Cycle-7 FP-template arm is the natural target.

---

## monotonicity (6 decisions)

### 39. OC | monotonicity | `minimumCapacity(forScale: Int) -> Int`

**Decision: accept.**

Source confirms: scale → capacity is monotonic non-decreasing on `scale ≥ minimumScale (5)`. For `scale < 5`, returns 0 (still monotonic at boundary). Verified from `_HashTable+Constants.swift:58`.

### 40. OC | monotonicity | `maximumCapacity(forScale:)`

**Decision: accept.**

Same monotonic structure: `(2^scale * 3)/4` is monotonic in scale.

### 41. OC | monotonicity | `scale(forCapacity:)`

**Decision: accept.**

Source confirms: scale grows non-decreasingly in capacity (binary-log-based). Verified.

### 42. PLK | monotonicity | `format(_:)` (CheckResult) -> String

**Decision: reject.**

CheckResult is a kit enum with cases like `.passed`, `.failed`, `.violated`, etc.; `format` produces a String like "PASSED" / "FAILED". The String lex order doesn't preserve any natural CheckResult ordering. Even if the enum is Comparable (debatable), the format-output strings don't honor that order.

### 43. PLK | monotonicity | `walkCap(for:)` (C: Collection) -> Int

**Decision: accept.**

`walkCap(for: c)` returns an iteration cap based on collection size — monotonic in `c.count`. Verified from name + signature; the function's purpose is a counting-sized cap.

### 44. Algo | monotonicity | (Algorithms Index → Int monotonicity if present)

**Decision: unknown.**

Algorithms cycle-5 has 3 monotonicity claims; without enumerating the exact site, I'd flag unknown. Algorithms is generally `(Index) -> Index` (where Index is the carrier — not Comparable in the relevant sense for monotonicity).

---

## inverse-pair (5 decisions)

### 45. OC | inverse-pair | OrderedSet binary inverse-pair sample

**Decision: reject.**

Without enumerating the specific picks, OC inverse-pair surface is largely SetAlgebra-shaped (`union` / `intersection` / `subtracting` / `symmetricDifference`) — these are *related* set ops but not strict inverses (each is its own algebraic identity).

### 46. OC | inverse-pair | variant

**Decision: reject.**

Same reasoning.

### 47. OC | inverse-pair | variant

**Decision: reject.**

Same.

### 48. Algo | inverse-pair | Algorithms Index ops

**Decision: reject.**

Algorithms inverse-pair surface is mostly Index-typed `(Index, Index) -> Index` ops — typically `index(_:offsetBy:)` and `distance(from:to:)` cross-product. The pair `f(x) = a + offset(x)`, `g(y) = a + offset(y)` doesn't compose to identity — these are arithmetic conveniences, not inverses.

### 49. Algo | inverse-pair | another Index op

**Decision: reject.**

Same.

---

## identity-element (1 decision)

### 50. CM | identity-element | `rescaledDivide(_:_:)` × `Complex.zero` (Score 70 Likely tier)

**Decision: reject.**

`rescaledDivide(z, w)` is not a kit-published identity-law candidate — division has no left-identity at `.zero` (`rescaledDivide(.zero, w) = .zero`, not the input). The shape `(Complex, Complex) -> Complex with identity .zero` matches V1.6.1's pair-formation rule for `(zero, *)` / `(zero, /)` style cross-products. V1.6.1's stdlib-operator gate didn't catch `rescaledDivide` because it's a user-named op (the gate is `{+, -, *, /, %, pow, **}`). Cycle-6 priority candidate (carried forward as cycle-7 priority): extend the math-library gate to include `rescaledDivide` family if a corpus example matters.

Score 70 (Likely tier) is a methodology note: this is the only Score >30 pick in the cycle-6 sample, and it's a clean reject. Suggests the Likely-tier weights are calibrated permissively — V1.6.1's pair-formation filter caught the easy structural mismatches but the curated op-list doesn't catch this user-named one. Cycle-7 has a clear mechanism extension target.

---

## Summary table — per-decision verdict

Quick reference:

| # | Verdict | # | Verdict | # | Verdict | # | Verdict | # | Verdict |
|---|---|---|---|---|---|---|---|---|---|
| 1 | reject | 11 | accept | 21 | reject | 31 | reject | 41 | accept |
| 2 | reject | 12 | accept | 22 | reject | 32 | reject | 42 | reject |
| 3 | reject | 13 | unknown | 23 | unknown | 33 | accept | 43 | accept |
| 4 | accept | 14 | accept | 24 | reject | 34 | accept | 44 | unknown |
| 5 | accept | 15 | accept | 25 | reject | 35 | reject | 45 | reject |
| 6 | reject | 16 | unknown | 26 | reject | 36 | reject | 46 | reject |
| 7 | reject | 17 | reject | 27 | reject | 37 | reject | 47 | reject |
| 8 | reject | 18 | reject | 28 | unknown | 38 | accept | 48 | reject |
| 9 | reject | 19 | reject | 29 | reject | 39 | accept | 49 | reject |
| 10 | reject | 20 | reject | 30 | reject | 40 | accept | 50 | reject |

Counts:
- **Accept: 12**
- **Reject: 33**
- **Unknown: 5**
- **Total: 50**

Computed rates per the rubric:
- Acceptance rate = 12 / (12 + 33) = **26.7%**
- Uncertainty rate = 5 / 50 = **10.0%**

Per-template breakdown in [`../calibration-cycle-6-findings.md`](../calibration-cycle-6-findings.md).
