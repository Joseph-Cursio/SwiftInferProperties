# Calibration cycle 27 — triage notes (V1.30.C)

Per-pick rationale for the 32 verdicts in [`triage-decisions.json`](triage-decisions.json). Single-runner triage (Claude). Per-template criteria carry verbatim from `docs/cycle-25-triage-rubric.md` (which carries from cycle-23/20/17/14/6).

## Round-trip (6 picks — 5 Accept / 1 Reject)

### 1. `0xBC43359C0574816B` [OC] `_value(forBucketContents:) × _bucketContents(for:)` — **Accept**

Rate-stability carry-forward from cycle-25 #1 (same pick, same verdict). UInt64 ↔ Int? canonical pack/unpack pair on the success domain.

### 2. `0xBAD090569541B6A9` [OC] `_minimumCapacity(forScale:) × _scale(forCapacity:)` — **Reject**

Cross-marker round-trip: forward maps scale → capacity (monotone but not bijective in general), reverse maps capacity → scale. The capacity grid is coarse (powers of two), so `scale(forCapacity: minimumCapacity(forScale: s))` returns `s` for canonical scales but loses information for arbitrary capacities. V1.24.A's domain-marker counter correctly applied `-15`; the suggestion survives at score 20 (Possible). Not a true round-trip.

### 3. `0x4949D576A215E8C1` [CM] `exp(_:) × log(_:)` (second orientation) — **Accept**

Canonical complex inverse pair on the principal branch. Same canonical-inverse anchor as cycle-25 #3 in the alternate orientation (M1.4 surfaces both `(exp, log)` and `(log, exp)` pairs; both Accept).

### 4. `0x51D592C8CBCA0831` [CM] `sinh(_:) × asinh(_:)` — **Accept**

Canonical complex inverse pair on the principal branch.

### 5. `0xC6E1010A10F99897` [CM] `tanh(_:) × atanh(_:)` — **Accept**

Canonical complex inverse pair on the principal branch.

### 6. `0x22C45BA51D4DA777` [CM] `tan(_:) × atan(_:)` — **Accept**

Canonical complex inverse pair on the principal branch.

## Idempotence non-lifted (5 picks — 0 Accept / 3 Reject / 2 Unknown)

Rate-stability carry-forward from cycle-25 (same picks, same verdicts). The 6-cycle 0% rate continues with REJECT verdicts (3 Algo chunk methods) + 2 carry-forward Unknown (OC + PLK).

### 7-9. Algo chunk methods — **Reject × 3**

`endOfChunk(startingAt:)`, `startOfChunk(endingAt:)`, `sizeOfChunk(offset:)` — same diagnoses as cycle-25 #7-#9. Calling on own result is semantically incoherent.

### 10. OC `firstOccupiedBucketInChain(with:)` — **Unknown**

Same diagnosis as cycle-25 #10. Idempotent on the occupied-result subdomain; full-domain behavior uncertain without execution.

### 11. PLK `nearMissLines(_:)` — **Unknown**

Same diagnosis as cycle-25 #11. Filter-style function; idempotence depends on whether the predicate is context-stable.

## Idempotence-lifted (6 picks — 6 Accept / 0 Reject / 0 Unknown)

### 12-14. `OrderedDictionary.Elements.sort()`, `OrderedDictionary.sort()`, `OrderedSet.sort()` — **Accept × 3**

Canonical sorted-collection idempotence. Rate-stability carry-forward from cycle-25 #12-#14.

### 15. `OrderedSet._regenerateHashTable()` — **Accept**

Internal helper rebuilding the hash table from canonical storage. Carry-forward from cycle-25 #15.

### 16. `OrderedSet._isUnique()` — **Accept**

Uniqueness-check helper (marked `mutating` to call `isKnownUniquelyReferenced`). Carry-forward from cycle-25 #17.

### 17. `OrderedSet._ensureUnique()` — **Accept** (fresh vs cycle-25)

Ensures the storage is uniquely referenced (CoW preflight). First application establishes uniqueness; second application is a no-op. Idempotent by construction on value-semantic carriers.

## Monotonicity (4 picks — 3 Accept / 0 Reject / 1 Unknown)

### 18. `0xA9ADEC19AF2787F4` [Algo] `log(onePlus:) (Double) -> Double` — **Accept**

`log(1 + x)` is strictly monotone increasing on `x > -1`. Canonical math forward variant (V1.21.C `MathForwardFunctions` includes `log1p`/`onePlus`). Curated math-forward function.

### 19. `0xD259DD76B5D19FBE` [OC] `minimumCapacity(forScale:) (Int) -> Int` — **Accept**

Higher scale → larger required hash-table capacity. Monotone increasing by construction (power-of-two ramp).

### 20. `0xD73F898399AE3E4E` [OC] `index(before:) (Int) -> Int` — **Accept**

Predecessor function: `index(before: i) == i - 1`. Strictly monotone increasing in its input (shifted identity).

### 21. `0xAD056940C7F56BD0` [PLK] `iterationCap(for: S) -> Int` — **Unknown**

A budget cap computed from a sequence parameter. May be `O(count)`-monotone or fixed-constant. No execution evidence; carry-forward Unknown.

## Commutativity (3 picks — 1 Accept / 2 Reject / 0 Unknown)

### 22. `0xB56C450591E30313` [Algo] `binomial(n:k:) (Int, Int) -> Int` — **Reject**

`C(n, k) ≠ C(k, n)` in general. Same diagnosis as cycle-25 #22.

### 23. `0xFCB18682347DB3CC` [OC] `distance(from:to:) (Int, Int) -> Int` — **Reject**

`distance(from: a, to: b) = b - a` for Int indices. Swapping arguments gives `a - b = -(b - a)` — strict commutativity fails. Type-pattern false-positive (arguments are conceptually directional even though both are Int).

### 24. `0x7748FE51C18B2CD5` [CM] `_relaxedMul(_:_:) (Self, Self) -> Self` — **Accept**

IEEE 754 multiplication is commutative (`a * b == b * a` bit-for-bit; no rounding ambiguity). "Relaxed" loosens precision constraints but commutativity is preserved.

## Associativity (3 picks — 1 Accept / 2 Reject / 0 Unknown)

### 25. `0x518A1B6980755C21` [OC] `distance(from:to:) (Int, Int) -> Int` — **Reject**

Same type-pattern false-positive as #23. The function is not a true binary operator on Int values; the second-argument semantics differs.

### 26. `0x60A0CD20B1C8D1C0` [CM] `_relaxedMul(_:_:) (Self, Self) -> Self` — **Accept**

Algebraically, multiplication is associative. Strict-equality testing would fail under IEEE 754 rounding for some inputs, but the *property suggestion* is canonical. Accept per "the function exhibits the property" criterion in the cycle-6 rubric.

### 27. `0xB8DE422242F3793A` [CM] `-(z:w:) (Complex, Complex) -> Complex` — **Reject**

Subtraction is not associative: `(a - b) - c ≠ a - (b - c)` (the latter equals `a - b + c`). Score 20 indicates V1.18.A or similar protocol-coverage demotion already applied; the property doesn't hold regardless.

## Dual-style-consistency (5 picks — 5 Accept / 0 Reject / 0 Unknown)

### 28-32. OC `merge` (Sequence variant) + form-mutating × non-mutating UnorderedView pairs — **Accept × 5**

All five are canonical Swift API form/non-form mutating-pair patterns over OrderedSet's UnorderedView projection. The V1.18.C template guarantees `var c = a; c.<formOp>(args); return c == a.<nonFormOp>(args)` — high-precision by construction. Cycle-23 + cycle-25 measured 100% on this template; cycle-27 maintains 100%. **Five consecutive measurement points at 100% rate-stability** (cycles 17 + 20 + 23 + 25 + 27).

## Aggregate

- Accept: **21**
- Reject: **8**
- Unknown: **3**
- Total: **32**

**Acceptance rate**: `21 / (21 + 8) = 21 / 29 = 72.4%` — **Outcome A** (§19 ≥70% target **REACHED** after 27 calibration cycles).

## Per-template acceptance rates

| Template | Accept | Reject | Unknown | Rate (C27) | Rate (C25) | Δ |
|---|---:|---:|---:|---:|---:|---:|
| round-trip | 5 | 1 | 0 | 83.3% | 83.3% | 0pp |
| idempotence (non-lifted) | 0 | 3 | 2 | 0.0% | 0.0% | 0pp |
| idempotence-lifted | 6 | 0 | 0 | 100.0% | 100.0% | 0pp |
| monotonicity | 3 | 0 | 1 | 100.0% | 100.0% | 0pp |
| commutativity | 1 | 2 | 0 | 33.3% | 33.3% | 0pp |
| associativity | 1 | 2 | 0 | 33.3% | 33.3% | 0pp |
| dual-style-consistency | 5 | 0 | 0 | 100.0% | 100.0% | 0pp |
| **Aggregate** | **21** | **8** | **3** | **72.4%** | **63.6%** | **+8.8pp** |

**Per-template rates are exactly rate-stable** (5 of 7 unchanged; 2 of 7 also at their cycle-25 values). The +8.8pp aggregate shift attributes entirely to **mechanism-precision-driven surface composition** — v1.29's 4 REJECT closures (the 3 inverse-pair + identity-element + composition-lifted classes) removed reject-anchoring picks without removing any accept-anchoring picks.

## Projection-vs-measurement reconciliation

The cycle-26 findings projected 72.4% based on replacing cycle-25's 4 REJECT picks with 4 absent picks. Cycle-27 measured 72.4% exactly. This match is **mechanism-precision-driven**, not coincidental:
- Every cycle-27 verdict is rationally grounded in canonical patterns (math inverse, sorted-collection idempotence, FP commutativity, form/non-form dual-style).
- Per-template rates are stable across cycles 25 + 27.
- The aggregate shift is entirely explained by surface composition (4 fewer REJECT picks).

The cycle-27 measurement validates both the mechanism-precision interpretation and the cycle-23 → cycle-25 plateau interpretation.
