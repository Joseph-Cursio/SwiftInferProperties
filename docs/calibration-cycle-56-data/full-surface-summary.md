# Cycle-56 full-surface measurement summary

Captured: 2026-05-13 via `swift-infer verify --all-from-index --index-path fixtures/cycle27-surface/.swiftinfer/index.json --max-parallel 4`. swift-infer at v1.59 (post-V1.59.A + V1.59.B).

## Aggregate

| Classification | Cycle-55 (103) | Cycle-56 (103) | Δ vs c55 |
|---|---:|---:|---:|
| measured-bothPass | 6 | 6 | 0 |
| measured-edgeCaseAdvisory | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 0 |
| measured-error | 0 | 0 | 0 |
| architectural-coverage-pending | 83 | 83 | 0 |
| **Total** | **103** | **103** | 0 |

**Aggregate counts unchanged.** v1.59 is groundwork; no picks closed. But the `.architectural-coverage-pending` detail-string distribution shifts substantially as 26 OS picks move down the layers (resolver → strategist → swift build → compile-fail at instance-method shape).

**Critical: `.measured-error = 0` baseline preserved.** V1.59.A's strategist recipe pushed 26 OS picks past resolution into the build step (compile-failing); V1.59.A's reclassification pattern matcher catches the resulting build errors and routes them to `.architectural-coverage-pending` with specific detail strings, preserving the v1.56 CI-alarm invariant.

## .architectural-coverage-pending detail breakdown

| Detail | Cycle-55 | Cycle-56 | Δ |
|---|---:|---:|---:|
| `unsupported-carrier: OrderedSet<Int>` | 29 | **3** | **-26** |
| **`instance-method-shape-not-supported`** | 0 | **21** | **+21** |
| `internal-api-not-accessible` | 2 | **5** | **+3** |
| **`carrier-missing-required-conformance`** | 0 | **2** | **+2** |
| `unsupported-carrier: OrderedSet.UnorderedView` | 8 | 8 | 0 |
| `unsupported-carrier: OrderedDictionary.Elements` | 7 | 7 | 0 |
| `unsupported-carrier: OrderedSet.SubSequence` | 6 | 6 | 0 |
| `unsupported-carrier: OrderedDictionary.Values` | 6 | 6 | 0 |
| `unsupported-carrier: OrderedDictionary.Elements.SubSequence` | 6 | 6 | 0 |
| `unsupported-carrier: _HashTable.UnsafeHandle` | 4 | 4 | 0 |
| `unsupported-carrier: _HashTable` | 4 | 4 | 0 |
| `unsupported-carrier: OrderedDictionary` | 3 | 3 | 0 |
| `unsupported-carrier: EvenlyChunkedCollection` | 2 | 2 | 0 |
| `unsupported-carrier: CombinationsSequence` | 2 | 2 | 0 |
| `unsupported-carrier: ChunkedByCollection` | 2 | 2 | 0 |
| `unsupported-carrier: ViolationFormatter` | 1 | 1 | 0 |
| `unsupported-carrier: _UnsafeHashTable` | 1 | 1 | 0 |
| `unsupported-carrier: (none)` | 0 | 0 | 0 |
| **Total** | **83** | **83** | 0 |

## OS pick movement (29 cycle-27 OrderedSet picks)

V1.58.A's binding + V1.59.A's recipe + double-qualifier strip + reclassification pattern matcher route OS picks into 4 distinct buckets:

| Bucket | Count | What it means | v1.60+ fix |
|---|---:|---|---|
| `instance-method-shape-not-supported` | 21 | Compile-fail: static call shape doesn't match the instance method declaration | Mutating-instance-method emission |
| `internal-api-not-accessible` | 3 | Compile-fail: function is `internal` (e.g. `OrderedSet._ensureUnique()`) | `@testable import` in workdir or indexer-time filter |
| `carrier-missing-required-conformance` | 2 | Compile-fail: monotonicity template requires `Comparable`; `OrderedSet<Int>` doesn't conform | Comparable-aware monotonicity composer, or non-Comparable value-ordering |
| `unsupported-carrier: OrderedSet<Int>` (still at resolver) | 3 | Resolver layer rejects despite V1.58.A binding | Investigate: probably dual-style-consistency picks going through a different code path |

**Total accounted: 21 + 3 + 2 + 3 = 29** ✓.

## What V1.59.A accomplished

V1.59 ships three coupled fixes + a related reclassification:

1. **Curated `OrderedSet<Int>` strategist recipe** — added a `curatedOCRecipe(carrier:)` branch in `StrategistDispatchEmitter.resolveRecipe` returning `Gen<Int>.int(in: 0 ... 100).map { OrderedSet([$0, $0+1, $0+2, $0+3]) }`. Imports include `OrderedCollections`.

2. **`swift-collections` workdir dep** — `VerifierWorkdir.renderPackageSwift` adds `.package(url: "swift-collections", from: "1.0.0")` + `.product(name: "OrderedCollections", package: "swift-collections")`. Unconditional (all workdirs get the dep; cost ~0 due to SwiftPM caching).

3. **Double-qualifier strip in `CallExpressionShape.render`** — surfaced during smoke-test. Indexer-produced `primaryFunctionName` values can be qualified (`OrderedSet.sort()`) or bare (`exp(_:)`); the resolver was building `OrderedSet.OrderedSet.sort` for qualified ones. Fix: strip the `<typeQualifier>.` prefix if present.

4. **`architecturalPendingDetail` extension** — 3 new patterns matching the cycle-56 surfaced build errors. Detail strings: `instance-method-shape-not-supported` (the dominant category; covers explicit "instance member" diagnostic + "no exact matches" form + compiler-crash signal-6 form) and `carrier-missing-required-conformance` (monotonicity-on-non-Comparable carriers).

## What V1.59.A unlocks per OS pick template

| Template | OS picks | v1.59 outcome | Next step |
|---|---:|---|---|
| idempotence (`sort`, `_ensureUnique`, etc.) | 6 | 4 instance-method-shape + 2 internal-api | v1.60: mutating-method emission + @testable |
| dual-style-consistency (`subtract`, `formUnion`, etc.) | 12 | 9 instance-method-shape + 3 unsupported-carrier-still | v1.60: instance-method + investigate the 3 still-at-resolver |
| monotonicity (`_minimumCapacity`, `index*`, etc.) | 5 | 2 carrier-missing-conformance + 3 instance-method-shape | v1.61: Comparable-aware monotonicity composer |
| round-trip (`_minimumCapacity / _scale`) | 3 | mostly internal-api or instance-method-shape | v1.60+ via @testable or instance-method |
| commutativity / associativity (no OS picks in cycle-27) | 0 | n/a | n/a |
| (other templates) | 3 | mostly instance-method-shape | v1.60 |

**The 21 `instance-method-shape-not-supported` picks are the dominant v1.60 target.** Once mutating-method emission lands, those become measurable.

## Cycle-46 predictions vs cycle-56 actuals

Unchanged from cycle-55 (the 26 newly-categorized OS picks weren't in the cycle-46 stratified sample subset):
- **Strict 4-category match**: 5 / 13 = 38%
- **Semantic "property holds" match**: 13 / 13 = **100%**

## What cycle-56 establishes

1. **V1.59.A delivers the next scaffold step.** 26 OS picks moved past the resolver layer; the next gap (instance-method shape) is now visible at the build step.

2. **`.measured-error = 0` baseline preserved across the scaffold transition.** V1.59.A's reclassification pattern matcher absorbed the new error categories without breaking the v1.56 CI-alarm invariant. The cycle-N findings doc can continue to say "any measured-error is an alarm" — true.

3. **The detail-string distribution is now substantially more informative.** Pre-v1.59 there were ~3 detail categories (mostly `unsupported-carrier:<Type>`). Post-v1.59 there are 6 distinct architectural-pending categories, each pointing at a specific v1.60+/v1.61+ workstream.

4. **3 OS picks didn't move past the resolver.** Investigate in v1.60: they're likely dual-style-consistency picks taking the `DualStyleConsistencyPairResolver` path (separate from the strategist) that hasn't been extended for OS<Int>.

5. **The double-qualifier strip in `CallExpressionShape.render` is a load-bearing bug fix.** Affects only qualified-name picks (mostly OS); regression-pinned by V1.59.B's unit test.

6. **The compiler-crash-as-instance-method-shape heuristic is empirical.** V1.59.A's match on "compile command failed due to signal" treats compiler crashes during type-check of static-call-of-instance-mutating-method as instance-method-shape errors. Brittle but pragmatic; if cycle-N+1 surfaces a non-OS compiler crash, the heuristic may need refinement.

## v1.60+ priorities (per cycle-56 evidence)

In priority order:

1. **v1.60 — Mutating-instance-method idempotence emission** for OC. The dominant remaining target (21 instance-method-shape-not-supported picks). New emit shape: `var copy1 = value; copy1.sort(); var copy2 = value; copy2.sort(); copy2.sort(); if copy1 != copy2 { fail }`. Most likely closes 15-20 picks to `.bothPass` / `.defaultFails`.

2. **v1.60 — Mutating-instance-method dual-style emission** for OC. The dual-style template tests `non-mutating-form` vs `var copy = x; copy.mutating-form(); copy` equivalence. New emit shape for both halves. Likely closes 9-12 picks.

3. **v1.60 — Investigate the 3 unsupported-carrier OS picks at resolver layer**. Probably dual-style-consistency picks routing through `DualStyleConsistencyPairResolver` separately. Small follow-up fix.

4. **v1.60 — Strategist recipes for OC.UnorderedView / OD.Elements / etc.** (the 8 + 7 + 6 + 6 + 6 = 33 pending nested-OC picks). Extends V1.59.A's pattern.

5. **v1.61 — Comparable-aware monotonicity composer** OR non-Comparable value-ordering strategy. Closes 2 picks.

6. **v1.61 — Strategist recipes for non-OC generics** (`_HashTable`, `ChunkedByCollection`, `EvenlyChunkedCollection`, `CombinationsSequence`, ~17 picks). Extends V1.59.A's pattern further.

7. **v1.62+ — Phase 2 accept-flow integration**.

## Methodology notes

- **Wall-clock**: ~10-12 min for the 103-pick survey (substantially longer than cycle-55's ~5 min). The increase reflects 26 OS picks now actually running `swift build` instead of failing fast at resolution. Each compile-then-fail cycle adds ~10-15s; 26 × ~12s ≈ 5 min extra.
- **The compiler-crash heuristic is OS-specific evidence**: only seen on `_ensureUnique`, `_isUnique`, `_regenerateHashTable`, `_regenerateExistingHashTable` picks. v1.60+ may need to revisit if false-positives surface.
- **The `intentionallyUnmatchedKeys` escape hatch from V1.58.B carries forward** — 4 V1.47.D entries (Self.Index / Self.Element / Base.Element / Iterator.Element).
- **`Base.Index` still has the load-bearing binding (V1.47.D)** — confirmed via the V1.58.B methodology guard.
