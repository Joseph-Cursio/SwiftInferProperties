# Calibration cycle 25 — triage notes (V1.28.C)

Per-pick rationale for the 36 verdicts in [`triage-decisions.json`](triage-decisions.json). Single-runner triage (Claude). Per-template criteria carry verbatim from `docs/cycle-23-triage-rubric.md` (which carries from cycle-20/17/14/6).

## Round-trip (6 picks — 5 Accept / 1 Reject)

### 1. `0xBC43359C0574816B` [OC] `_value(forBucketContents:) × _bucketContents(for:)` — **Accept**

`UInt64 -> Int?` paired with `Int? -> UInt64`. The two halves are explicit pack/unpack helpers for hash-table bucket encoding (`_HashTable+UnsafeHandle.swift:201,219`). Round-trip on the success domain (non-nil values) is the canonical property the API contract intends. No equivalent already-protocol-covered property; M1.4 surfaces it correctly.

### 2. `0xA5C1F58768F24FBB` [OC] `_minimumCapacity(forScale:) × _maximumCapacity(forScale:)` — **Reject**

Both functions take `forScale:` and return `Int`. They produce a (min, max) bracket at a given scale — they are not a forward/inverse pair. V1.24.A's domain-marker counter correctly applied `-15` (matching `forScale ↔ forScale`); the suggestion survives in Possible tier at score 20 because the base type-symmetry signature still grants +30. This is a known same-marker false-positive class — the counter demotes but does not full-veto.

### 3. `0xB72E7362FA5FB419` [CM] `exp(_:) × log(_:)` — **Accept**

Canonical complex inverse pair on the principal branch. `log(exp(z)) == z` for `Im(z) ∈ (-π, π]`. The property as emitted assumes principal-branch evaluation, which matches the swift-numerics `Complex.log` definition. FP precision is a generator concern (cycle-23 carry-forward: FP approximate-equality template arm).

### 4. `0x56A303C3E0347225` [CM] `cosh(_:) × acosh(_:)` — **Accept**

Canonical complex inverse pair on the principal branch.

### 5. `0x6D310ED906336577` [CM] `cos(_:) × acos(_:)` — **Accept**

Canonical complex inverse pair on the principal branch.

### 6. `0x68D500860718049A` [CM] `sin(_:) × asin(_:)` — **Accept**

Canonical complex inverse pair on the principal branch.

## Idempotence non-lifted (5 picks — 0 Accept / 3 Reject / 2 Unknown)

### 7. `0x3543E69FA981193D` [Algo] `endOfChunk(startingAt:) (Base.Index) -> Base.Index` — **Reject**

Returns the position past the chunk starting at `i`. Calling it on its own result (`endOfChunk(startingAt: endOfChunk(startingAt: i))`) does not return the same value: the second call now starts at the end of the *first* chunk, returning the end of the *second* chunk. Idempotence does not hold by construction. The pick survives V1.25.A's name-prefix gate (`index`/`bucket`/`word`) because `endOfChunk` doesn't match, and V1.22.D's stride-style label demotion appears scoped to round-trip rather than idempotence.

### 8. `0x40C830C81337F0F5` [Algo] `startOfChunk(endingAt:)` — **Reject**

Symmetric to #7 in the opposite direction.

### 9. `0xED77E1F06B342709` [Algo] `sizeOfChunk(offset:) (Int) -> Int` — **Reject**

Returns the size of the chunk whose start-offset is `i`. Calling it on its own result conflates an offset with a size — semantically incoherent. Idempotence does not hold.

### 10. `0xE54F0D92F01DC623` [OC] `firstOccupiedBucketInChain(with:) (Bucket) -> Bucket` — **Unknown**

Returns the first occupied bucket in the probe chain starting at the input bucket. If the input bucket is already occupied, the function returns it unchanged → idempotent on that subdomain. If the input is unoccupied, behavior depends on the chain layout. Property could be defended on the "occupied result" subdomain but the full domain is uncertain without execution. Carry-forward from cycle-17/20/23 Unknown.

### 11. `0x840AA110CEF8E8B5` [PLK] `nearMissLines(_:) ([String]?) -> [String]?` — **Unknown**

A filtering function on optional string arrays. If the second application filters the same predicate over the already-filtered result, idempotence holds. If the filter is context-dependent (e.g., reads a stateful threshold), it may not. Code-level evidence is insufficient without execution. Carry-forward from cycle-17/20/23 Unknown.

## Idempotence-lifted (6 picks — 6 Accept / 0 Reject / 0 Unknown)

### 12-14. `OrderedDictionary.Elements.sort()`, `OrderedDictionary.sort()`, `OrderedSet.sort()` — **Accept × 3**

Canonical sorted-collection idempotence: `var c = a; c.sort(); c.sort(); c == { var d = a; d.sort(); return d }()`. The lift (`var c = a; c.sort()`) requires value-semantic carriers — all three are `struct` value-semantic types in OC. V1.19.D + V1.19.B + V1.18.A + the cycle-15 `Signal.Kind.valueSemanticCarrier` chain corroborate the lift admission.

### 15. `0x5C7D1C8D560E326D` [OC] `OrderedSet._regenerateHashTable()` — **Accept**

Internal helper that rebuilds the hash table from the canonical storage layout. Calling twice on the same value-semantic copy produces the same result the second time (no remaining state divergence after the first regeneration). Property as-emitted is well-defined.

### 16. `0xA275D2385A136BAD` [OC] `OrderedSet._regenerateExistingHashTable()` — **Accept**

Same shape as #15 with a narrower precondition (the existing table is regenerated rather than allocated). Idempotent on the post-regeneration state.

### 17. `0x4CE1969DD55F9FA4` [OC] `OrderedSet._isUnique()` — **Accept**

A uniqueness-check helper marked `mutating` (Swift requires `mutating` to call `isKnownUniquelyReferenced` on stored properties). The function does not modify the value — calling twice on the same `var copy` produces identical state. Idempotent by construction.

## Monotonicity (4 picks — 3 Accept / 0 Reject / 1 Unknown)

### 18. `0xE0626CEF04CEE3AC` [Algo] `log(_:) (Double) -> Double` — **Accept**

Mathematical log is strictly monotone increasing on positive reals. Curated math-forward function (V1.21.C). Property is canonical.

### 19. `0x024EC8BD5F216271` [OC] `wordCount(forScale:) (Int) -> Int` — **Accept**

Higher scale → larger hash-table → more word-sized storage cells required. Monotonic in scale. (Score 35 ≠ baseline 25 indicates a positive signal — likely a curated capacity-name match; the property is correct regardless.)

### 20. `0x4935E0E0B52AAB78` [OC] `index(after:) (Int) -> Int` — **Accept**

The successor function on integers: `index(after: i) > i`. Strictly monotone increasing. (M7.1's ordered-codomain signal catches this for free; the property is trivially true.)

### 21. `0x9352F26E9BA46A33` [PLK] `walkCap(for: C) -> Int` — **Unknown**

A "walk cap" budget computed from a collection. Could be `O(count)`-monotone or could be a fixed constant. Cycle-17/20/23 carry-forward Unknown without execution.

## Commutativity (3 picks — 1 Accept / 2 Reject / 0 Unknown)

### 22. `0xB56C450591E30313` [Algo] `binomial(n:k:) (Int, Int) -> Int` — **Reject**

`C(n, k) ≠ C(k, n)` in general. The signature pattern `(Int, Int) -> Int` matches the commutativity template, but the function semantics violate it.

### 23. `0xA48308B395A07123` [OC] `index(_:offsetBy:) (Int, Int) -> Int` — **Reject**

Arguments are semantically (Index, Distance) not two interchangeable Int values. Commutativity is type-pattern false-positive.

### 24. `0x1C94EE2FCC17B783` [CM] `_relaxedAdd(_:_:) (Self, Self) -> Self` — **Accept**

Floating-point addition is commutative: `a + b == b + a` holds bit-for-bit under IEEE 754 (no rounding ambiguity). "Relaxed" loosens precision constraints, but commutativity is preserved.

## Associativity (3 picks — 1 Accept / 2 Reject / 0 Unknown)

### 25. `0xE574CB2D65C86A66` [Algo] `binomial(n:k:)` — **Reject**

Same reasoning as #22. Binomial is not an associative binary operator.

### 26. `0x2074913DD61C9477` [OC] `index(_:offsetBy:)` — **Reject**

Same type-pattern false-positive as #23.

### 27. `0x26D2FD96A4FB2B01` [CM] `_relaxedAdd(_:_:)` — **Accept**

Algebraically, addition is associative. Strict-equality testing would fail under IEEE 754 due to rounding (`(a + b) + c ≠ a + (b + c)` for some inputs), but the *property suggestion* is canonical — SwiftInfer's job is to surface the property; the FP precision concern is the cycle-23 carry-forward "FP approximate-equality template arm". Accept per the "Accept if the function exhibits the property" criterion in the cycle-6 rubric.

## Inverse-pair (2 picks — 0 Accept / 2 Reject / 0 Unknown)

### 28. `0xD77C1CCCD1CE086A` [OC] `bucket(after:) × firstOccupiedBucketInChain(with:)` — **Reject**

`firstOccupiedBucketInChain(with: bucket(after: b)) == b` does not hold: the forward side advances by one bucket; the reverse side searches forward through the probe chain for the first occupied slot. Their composition is not the identity.

**This is a V1.27.B closure gap.** The cycle-23 finding targeted `bucket(after:) × bucket(before:)` pairs (which V1.27.B did full-veto). But the surviving v1.27 inverse-pair candidates pair the bucket-direction op with `firstOccupiedBucketInChain` (which has no direction-label prefix matching `["index", "bucket", "word"]`). V1.27.B's name-prefix gate requires *both* sides to match the prefix list, so this pair only triggers the V1.11.1 either-side `-10` counter, leaving the suggestion in Possible tier at score 20.

### 29. `0xBCE379651F30DD56` [OC] `bucket(before:) × firstOccupiedBucketInChain(with:)` — **Reject**

Symmetric to #28. Same V1.27.B closure-gap finding.

## Identity-element (1 pick — 0 Accept / 1 Reject / 0 Unknown)

### 30. `0x9964626EA35C4B60` [CM] `rescaledDivide(_:_:)` with identity `Complex.zero` — **Reject**

Suggestion claims `Complex.zero` is the two-sided identity of `rescaledDivide`. Two-sided means `f(z, 0) == z AND f(0, z) == z`. Division by zero is mathematically undefined; even in IEEE 754 it produces `inf`/`nan`, not the input. The reverse side `f(0, z)` produces `0`, not `z`. Neither side holds. This is a curated-constant false-positive — the `+40` "Curated identity-element constant" signal fires on the type-shape match without checking the operator's semantics. (Carry-forward from cycle-23; the identity-element template's curated-constant match is too lax for non-additive binary operators.)

## Dual-style-consistency (5 picks — 5 Accept / 0 Reject / 0 Unknown)

### 31-35. `merge × _ merging`, `formIntersection × intersection`, `formSymmetricDifference × symmetricDifference`, `formUnion × union`, `subtract × subtracting` — **Accept × 5**

All five are canonical `mutating × non-mutating` Swift API pairs over OC's `OrderedSet` and `OrderedDictionary`. The V1.18.C template guarantees `var c = a; c.<mut>(args); return c == a.<nonMut>(args)` — high-precision by construction. Cycle-23 measured 100% acceptance on dual-style-consistency (largest mechanism-class precision contribution in the loop's history); the property is preserved by the kit-provided value-semantic SetAlgebra implementation. Three consecutive measurement-point 100% rate stability (cycle 20 / 23 / 25).

## Composition-lifted (1 pick — 0 Accept / 1 Reject / 0 Unknown)

### 36. `0x8C31B1B9D4D3A76C` [OC] `_HashTable.BucketIterator.advance(until:)` — **Reject**

Lifted composition shape: `advance(advance(s, a), b) == advance(s, a + b)`. The parameter `until:` is a monotone bound, not a delta — `advance(until: 5)` advances until the iterator reaches at-or-past index 5. Composing `advance(until: 5)` then `advance(until: 10)` yields the same state as `advance(until: 10)`, not `advance(until: 15)`. The template's `-25` counter "Monotone-bounded parameter label 'until' — not additive composition" correctly identified the shape mismatch but didn't full-veto, leaving the suggestion in Likely tier at score 60. The property as emitted does not hold.

## Aggregate

- Accept: **21**
- Reject: **12**
- Unknown: **3**
- Total: **36**

**Acceptance rate**: `21 / (21 + 12) = 21 / 33 = 63.64%` — **Outcome B** (60-69% plateau range; §19 ≥70% target NOT reached).

## Per-template acceptance rates

| Template | Accept | Reject | Unknown | Rate |
|---|---:|---:|---:|---:|
| round-trip | 5 | 1 | 0 | 83.3% |
| idempotence (non-lifted) | 0 | 3 | 2 | 0.0% |
| idempotence-lifted | 6 | 0 | 0 | 100.0% |
| monotonicity | 3 | 0 | 1 | 100.0% |
| commutativity | 1 | 2 | 0 | 33.3% |
| associativity | 1 | 2 | 0 | 33.3% |
| inverse-pair | 0 | 2 | 0 | 0.0% |
| identity-element | 0 | 1 | 0 | 0.0% |
| dual-style-consistency | 5 | 0 | 0 | 100.0% |
| composition-lifted | 0 | 1 | 0 | 0.0% |
| **Aggregate** | **21** | **12** | **3** | **63.6%** |

Three mechanism classes carry the rate (idempotence-lifted, monotonicity, dual-style-consistency — all 100%); five mechanism classes have 0% accept (idempotence non-lifted, inverse-pair, identity-element, composition-lifted — all low-tier residuals).
