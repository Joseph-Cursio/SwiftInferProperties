# Calibration cycle 25 — sample manifest (V1.28.C)

36-pick stratified sample on the post-v1.27 113-surface. Per the V1.28.A recount in [`surface-counts.md`](surface-counts.md), the v1.27 surface is 113 (8 Algo + 77 OC + 21 CM + 7 PLK).

Single-runner triage (Claude) per [`../cycle-25-triage-rubric.md`](../cycle-25-triage-rubric.md) — verbatim cycle-23 per-template criteria carry-forward (which carries from cycle-20/17/14/6).

## Sample distribution

| Template | Surface | Sampled | Sample basis |
|---|---:|---:|---|
| round-trip | 12 | 6 | 2 OC + 4 CM (cross-corpus mix; CM math forwards dominate) |
| idempotence (non-lifted) | 5 | 5 | full coverage |
| idempotence-lifted | 7 | 6 | 3 Strong (all sort lifts) + 3 of 4 Likely (regen/isUnique) |
| monotonicity | 29 | 4 | 1 Algo + 2 OC + 1 PLK |
| commutativity | 17 | 3 | 1 Algo + 1 OC + 1 CM |
| associativity | 17 | 3 | 1 Algo + 1 OC + 1 CM |
| inverse-pair | 2 | 2 | full coverage |
| identity-element | 1 | 1 | full coverage |
| dual-style-consistency | 22 | 5 | OC form/non-form representatives |
| composition (lifted) | 1 | 1 | full coverage |
| **Total** | **113** | **36** | |

Sampling rate 31.9% (cf. cycle-23 35.1%, cycle-20 30.3%, cycle-17 14%).

## The 36 picks (in stratified order)

### Round-trip (6)

1. `0xBC43359C0574816B` [OC] `_value(forBucketContents:) × _bucketContents(for:)` — UInt64 ↔ Int? pack/unpack pair (score 35).
2. `0xA5C1F58768F24FBB` [OC] `_minimumCapacity(forScale:) × _maximumCapacity(forScale:)` — both `forScale` (score 20; -15 domain-marker counter applied).
3. `0xB72E7362FA5FB419` [CM] `exp(_:) × log(_:)` — canonical complex inverse pair (score 30).
4. `0x56A303C3E0347225` [CM] `cosh(_:) × acosh(_:)` — canonical (score 30).
5. `0x6D310ED906336577` [CM] `cos(_:) × acos(_:)` — canonical (score 30).
6. `0x68D500860718049A` [CM] `sin(_:) × asin(_:)` — canonical (score 30).

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
16. `0xA275D2385A136BAD` [OC] `OrderedSet._regenerateExistingHashTable()` (score 45 Likely).
17. `0x4CE1969DD55F9FA4` [OC] `OrderedSet._isUnique()` (score 45 Likely).

(Excluded: `0x0ADF4CC755508749` `_ensureUnique()` — same shape as `_isUnique()`; representative coverage already achieved.)

### Monotonicity (4)

18. `0xE0626CEF04CEE3AC` [Algo] `log(_:) (Double) -> Double` (score 25).
19. `0x024EC8BD5F216271` [OC] `wordCount(forScale:) (Int) -> Int` (score 35).
20. `0x4935E0E0B52AAB78` [OC] `index(after:) (Int) -> Int` (score 25).
21. `0x9352F26E9BA46A33` [PLK] `walkCap(for:) (C) -> Int` (score 25).

### Commutativity (3)

22. `0xB56C450591E30313` [Algo] `binomial(n:k:) (Int, Int) -> Int` (score 30).
23. `0xA48308B395A07123` [OC] `index(_:offsetBy:) (Int, Int) -> Int` (score 30).
24. `0x1C94EE2FCC17B783` [CM] `_relaxedAdd(_:_:) (Self, Self) -> Self` (score 30).

### Associativity (3)

25. `0xE574CB2D65C86A66` [Algo] `binomial(n:k:) (Int, Int) -> Int` (score 30).
26. `0x2074913DD61C9477` [OC] `index(_:offsetBy:) (Int, Int) -> Int` (score 30).
27. `0x26D2FD96A4FB2B01` [CM] `_relaxedAdd(_:_:) (Self, Self) -> Self` (score 30).

### Inverse-pair (2; full coverage)

28. `0xD77C1CCCD1CE086A` [OC] `bucket(after:) × firstOccupiedBucketInChain(with:)` (score 20).
29. `0xBCE379651F30DD56` [OC] `bucket(before:) × firstOccupiedBucketInChain(with:)` (score 20).

### Identity-element (1; full coverage)

30. `0x9964626EA35C4B60` [CM] `rescaledDivide(_:_:)` with identity `Complex.zero` (score 70 Likely).

### Dual-style-consistency (5)

31. `0x44079B3ADA944F72` [OC] `OrderedDictionary.merge(_:uniquingKeysWith:)` (score 75 Strong).
32. `0xCCCD9EBCA611BD7A` [OC] `OrderedSet.formIntersection(_:)` (score 75 Strong).
33. `0xEC357857FD9090EA` [OC] `OrderedSet.formSymmetricDifference(_:)` (score 75 Strong).
34. `0xD81E952EBCD8CA1F` [OC] `OrderedSet.formUnion(_:)` (score 75 Strong).
35. `0xC0B0A68F141A3C6D` [OC] `OrderedSet.subtract(_:)` (score 75 Strong).

### Composition-lifted (1; full coverage)

36. `0x8C31B1B9D4D3A76C` [OC] `_HashTable.BucketIterator.advance(until:)` (score 60 Likely).

See [`triage-decisions.json`](triage-decisions.json) for the per-pick verdict and [`triage-notes.md`](triage-notes.md) for the rationale.
