# Calibration cycle 27 — sample manifest (V1.30.C)

32-pick stratified sample on the post-v1.29 109-surface. Per the V1.30.A recount in [`surface-counts.md`](surface-counts.md), the v1.29 surface is 109 (8 Algo + 74 OC + 20 CM + 7 PLK).

Single-runner triage (Claude) per [`../cycle-27-triage-rubric.md`](../cycle-27-triage-rubric.md) — verbatim cycle-25 per-template criteria carry-forward (which carries from cycle-23/20/17/14/6). Three mechanism classes are empty on the v1.29 surface (inverse-pair / identity-element / composition-lifted); the sample distributes across the seven non-empty classes.

## Sample distribution

| Template | Surface | Sampled | Sample basis |
|---|---:|---:|---|
| round-trip | 12 | 6 | 2 OC + 4 CM (fresh CM math anchors vs cycle-25) |
| idempotence (non-lifted) | 5 | 5 | full coverage (same picks as cycle-25; carry-forward verdicts) |
| idempotence-lifted | 7 | 6 | 3 Strong sorts + 3 Likely (different mix vs cycle-25: regen + isUnique + ensureUnique) |
| monotonicity | 29 | 4 | 1 Algo + 2 OC + 1 PLK (fresh vs cycle-25) |
| commutativity | 17 | 3 | 1 Algo + 1 OC + 1 CM (fresh OC pick: distance) |
| associativity | 17 | 3 | 1 OC + 2 CM (fresh OC pick: distance; fresh CM: relaxedMul + minus) |
| dual-style-consistency | 22 | 5 | OC UnorderedView variants (fresh vs cycle-25's Self variants) |
| **Total** | **109** | **32** | |

Sampling rate 29.4% (cf. cycle-25 31.9%, cycle-23 35.1%, cycle-20 30.3%, cycle-17 14%).

## The 32 picks (in stratified order)

### Round-trip (6)

1. `0xBC43359C0574816B` [OC] `_value(forBucketContents:) × _bucketContents(for:)` — UInt64 ↔ Int? pack/unpack pair (score 35; rate-stability carry from C25).
2. `0xBAD090569541B6A9` [OC] `_minimumCapacity(forScale:) × _scale(forCapacity:)` — score 20; cross-marker pair.
3. `0x4949D576A215E8C1` [CM] `exp(_:) × log(_:)` (second orientation) — canonical (score 30).
4. `0x51D592C8CBCA0831` [CM] `sinh(_:) × asinh(_:)` — canonical (score 30).
5. `0xC6E1010A10F99897` [CM] `tanh(_:) × atanh(_:)` — canonical (score 30).
6. `0x22C45BA51D4DA777` [CM] `tan(_:) × atan(_:)` — canonical (score 30).

### Idempotence non-lifted (5; full coverage)

7. `0x3543E69FA981193D` [Algo] `endOfChunk(startingAt:)` (score 30).
8. `0x40C830C81337F0F5` [Algo] `startOfChunk(endingAt:)` (score 30).
9. `0xED77E1F06B342709` [Algo] `sizeOfChunk(offset:)` (score 30).
10. `0xE54F0D92F01DC623` [OC] `firstOccupiedBucketInChain(with:)` (score 35).
11. `0x840AA110CEF8E8B5` [PLK] `nearMissLines(_:)` (score 35).

### Idempotence-lifted (6 of 7)

12. `0xE750C48C0E345E19` [OC] `OrderedDictionary.Elements.sort()` (score 85 Strong).
13. `0xDBB22A3D3D3549C0` [OC] `OrderedDictionary.sort()` (score 85 Strong).
14. `0xDA90F9E6856741DC` [OC] `OrderedSet.sort()` (score 85 Strong).
15. `0x5C7D1C8D560E326D` [OC] `OrderedSet._regenerateHashTable()` (score 45 Likely).
16. `0x4CE1969DD55F9FA4` [OC] `OrderedSet._isUnique()` (score 45 Likely).
17. `0x0ADF4CC755508749` [OC] `OrderedSet._ensureUnique()` (score 45 Likely; fresh vs C25).

(Excluded: `0xA275D2385A136BAD` `_regenerateExistingHashTable()` — same shape as `_regenerateHashTable()` already sampled.)

### Monotonicity (4)

18. `0xA9ADEC19AF2787F4` [Algo] `log(onePlus:) (Double) -> Double` (score 25; fresh).
19. `0xD259DD76B5D19FBE` [OC] `minimumCapacity(forScale:) (Int) -> Int` (score 25; fresh).
20. `0xD73F898399AE3E4E` [OC] `index(before:) (Int) -> Int` (score 25; fresh).
21. `0xAD056940C7F56BD0` [PLK] `iterationCap(for:) (S) -> Int` (score 25; fresh).

### Commutativity (3)

22. `0xB56C450591E30313` [Algo] `binomial(n:k:) (Int, Int) -> Int` (score 30; rate-stability).
23. `0xFCB18682347DB3CC` [OC] `distance(from:to:) (Int, Int) -> Int` (score 30; fresh vs C25's `index(_:offsetBy:)`).
24. `0x7748FE51C18B2CD5` [CM] `_relaxedMul(_:_:) (Self, Self) -> Self` (score 30; fresh vs C25's `_relaxedAdd`).

### Associativity (3)

25. `0x518A1B6980755C21` [OC] `distance(from:to:) (Int, Int) -> Int` (score 30; fresh).
26. `0x60A0CD20B1C8D1C0` [CM] `_relaxedMul(_:_:) (Self, Self) -> Self` (score 30; fresh).
27. `0xB8DE422242F3793A` [CM] `-(z:w:) (Complex, Complex) -> Complex` (score 20; fresh).

### Dual-style-consistency (5)

28. `0xAC399387FD5E9E28` [OC] `OrderedDictionary.merge(_:uniquingKeysWith:)` (Sequence<(Key, Value)>) (score 75 Strong).
29. `0xED146732CB38DCDF` [OC] `OrderedSet.formIntersection(UnorderedView)` (score 75 Strong).
30. `0xE32D06B86F4ECFCD` [OC] `OrderedSet.formSymmetricDifference(UnorderedView)` (score 75 Strong).
31. `0x57B82FC46EA980A9` [OC] `OrderedSet.formUnion(UnorderedView)` (score 75 Strong).
32. `0x45D61B79277AD072` [OC] `OrderedSet.subtract(UnorderedView)` (score 75 Strong).

See [`triage-decisions.json`](triage-decisions.json) for verdicts and [`triage-notes.md`](triage-notes.md) for rationale.
