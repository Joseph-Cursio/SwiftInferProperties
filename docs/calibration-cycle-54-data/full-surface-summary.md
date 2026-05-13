# Cycle-54 full-surface measurement summary

Captured: 2026-05-13 via `swift-infer verify --all-from-index --index-path fixtures/cycle27-surface/.swiftinfer/index.json --max-parallel 4`. swift-infer at v1.57 (post-V1.57.A scanner filter + cycle-27 fixture rebuild). **First cycle with the 103-pick baseline** (down from the v1.29-era 109).

## Aggregate

| Classification | Cycle-52 (109) | Cycle-53 (109) | Cycle-54 (103) | Δ vs c53 |
|---|---:|---:|---:|---:|
| measured-bothPass | 6 | 6 | 6 | 0 |
| measured-edgeCaseAdvisory | 8 | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 6 | 0 |
| measured-error | 2 | 0 | 0 | 0 |
| architectural-coverage-pending | 87 | 89 | **83** | **-6** |
| **Total** | **109** | **109** | **103** | **-6** |

**Total measured count unchanged at 20**, but the **denominator shrunk from 109 to 103** as V1.57.A dropped 6 private declarations from the index. Measured-execution rate: 18.3% → **19.4%**.

The 6 dropped picks were always noise (file-private declarations not reachable cross-module). V1.57.A corrects the v1.29-era scanner's over-collection.

## Per-checkout breakdown

| Checkout | Cycle-53 count | Cycle-54 count | Δ |
|---|---:|---:|---:|
| swift-numerics (ComplexModule) | 20 | 20 | 0 |
| swift-algorithms (Algorithms) | 8 | 8 | 0 |
| swift-collections (OrderedCollections) | 74 | 74 | 0 |
| **SwiftPropertyLaws (PropertyLawKit)** | **7** | **1** | **-6** |
| **Total** | **109** | **103** | **-6** |

All 6 dropped picks are from SwiftPropertyLaws:

| Hash prefix | Function | Modifier | File |
|---|---|---|---|
| 0x9352 | `walkCap(for:)` | `private` | Public/BidirectionalCollectionLaws.swift:237 |
| 0xAD05 | `iterationCap(for:)` | `private` | Public/IteratorProtocolLaws.swift:97 |
| 0xBA0E | `snapshot(_:)` | `private` | Public/MutableCollectionLaws.swift:181 |
| 0xD694 | `headerLine(_:)` | `private static` | Internal/ViolationFormatter.swift:27 |
| 0xF67C | `formatBuckets(_:)` | `private static` | Internal/ViolationFormatter.swift:81 |
| 0x840A | `nearMissLines(_:)` | `private static` | Internal/ViolationFormatter.swift:58 |

The 3 file-private helpers were the cycle-53 `(none)`-typeName picks (free functions, no enclosing type). The 3 `private static` ViolationFormatter members were inside an `internal enum`, but their explicit `private` modifier overrode the enclosing access — V1.57.A correctly filters them.

## .architectural-coverage-pending detail breakdown (83 picks)

The detail-string distribution after the rebuild:

| Detail | Count | Δ vs c53 |
|---|---:|---:|
| `unsupported-carrier: OrderedSet` | 29 | 0 |
| `unsupported-carrier: OrderedSet.UnorderedView` | 8 | 0 |
| `unsupported-carrier: OrderedDictionary.Elements` | 7 | 0 |
| `unsupported-carrier: OrderedSet.SubSequence` | 6 | 0 |
| `unsupported-carrier: OrderedDictionary.Values` | 6 | 0 |
| `unsupported-carrier: OrderedDictionary.Elements.SubSequence` | 6 | 0 |
| `unsupported-carrier: _HashTable.UnsafeHandle` | 4 | 0 |
| `unsupported-carrier: _HashTable` | 4 | 0 |
| `unsupported-carrier: ViolationFormatter` | **1** | **-3** (private members dropped) |
| `unsupported-carrier: OrderedDictionary` | 3 | 0 |
| `unsupported-carrier: (none)` | **0** | **-3** (private free fns dropped) |
| `unsupported-carrier: EvenlyChunkedCollection` | 2 | 0 |
| `unsupported-carrier: CombinationsSequence` | 2 | 0 |
| `unsupported-carrier: ChunkedByCollection` | 2 | 0 |
| `unsupported-carrier: _UnsafeHashTable` | 1 | 0 |
| `internal-api-not-accessible` | 2 | 0 (V1.56.A unchanged) |

The `(none)` detail is eliminated entirely. The `ViolationFormatter` detail dropped from 4 to 1 (the 3 private static members are gone).

## What V1.57.A accomplished

| Cycle | Total | Measured | Pending | Measured-execution rate |
|---|---:|---:|---:|---:|
| Cycle-52 (v1.55) | 109 | 20 | 87 (+2 error) | 18.3% |
| Cycle-53 (v1.56) | 109 | 20 | 89 (V1.56.A reclassified rescaledDivide) | 18.3% |
| Cycle-54 (v1.57) | **103** | 20 | **83** | **19.4%** |

The headline rate improvement (18.3% → 19.4%) is denominator-driven, not new measurements. But it reflects a meaningful baseline correction — the 6 dropped picks were artifacts of the v1.29-era scanner, not real cycle-27 picks.

## Cycle-46 predictions vs cycle-54 actuals

Unchanged from cycle-53:
- **Strict 4-category match**: 5 / 13 = 38%
- **Semantic "property holds" match**: 13 / 13 = **100%**

V1.57.A doesn't change the 32-pick sample (none of the dropped picks were in the cycle-46 stratified subset). The match rates carry forward unchanged.

## What cycle-54 establishes

1. **V1.57.A correctly filters file-private declarations.** Scanner-level filtering is the right architectural layer — these picks shouldn't have been in the index in the first place.

2. **The cycle-27 baseline shifts to 103 picks.** The v1.29-frozen 109 was a snapshot of the v1.29-era scanner; v1.57's correction reflects a better understanding of what's "indexable" cross-module. Cycle-N findings from v1.57 onward reference 103.

3. **The `.measured-error = 0` baseline established in v1.56 holds.** V1.57.A doesn't introduce any new error categories; the clean baseline carries forward.

4. **`.architectural-coverage-pending` is now cleaner**. The 3 `(none)`-typeName picks are gone (eliminated category); the `ViolationFormatter` count dropped to 1 (just the remaining `public static func format(_:)`). The remaining 83 picks are dominated by OC + Algo generic-instantiation gaps (v1.58+ TypeShape work).

5. **A future user `swift-infer index` will produce a smaller index than pre-V1.57.** Documented in the V1.57.A code comment; release notes flag the change.

## v1.58+ priorities (per cycle-54 evidence)

In priority order:

1. **v1.58-v1.59 — TypeShape-driven generic instantiation** for OC + Algo types. Dominant remaining category (83 picks). Multi-cycle scope.

2. **v1.58 — Instance-method emission** for OC + Algo wrappers. The current emitters assume free or static functions; OC picks are mostly instance methods on the wrapper.

3. **v1.58 — Methodology guard for binding tables**. Fixture-level check that every `GenericBindingResolver.curatedBindings` key matches at least one indexer-produced carrier name (or member-type-name in some indexed TypeShape).

4. **v1.59+ — Phase 2 accept-flow integration**. The 20-pick measurable sample + clean `.measured-error = 0` baseline + 103-pick coherent index make accept-flow viable.

5. **v1.59+ — Per-function default-pass domain refinement** (v1.55 carry-forward). Extend the 2-entry table with more granular per-function ranges as cycle-N evidence reveals additional boundaries.

6. **v1.59+ — Optional `internal`-modifier filter**. Would require careful audit (Swift's default is internal so most user code lacks explicit modifier; filtering would be over-aggressive). v1.59+ may revisit if cycle-N reveals further internal-symbol noise.

## Methodology notes

- **Wall-clock**: ~4-5 minutes for the 103-pick survey (matched cycles 50-53; slight drop due to smaller surface).
- **Fixture rebuild**: requires deleting per-checkout indexes for a fresh scan (the indexer merges with existing entries on re-run). Documented in V1.57.E's commit message.
- **Per-checkout drop verification**: swift-numerics/swift-algorithms/swift-collections counts unchanged → no surprises in those corpora. SwiftPropertyLaws's expected drop of 6 confirmed all the affected picks.
- **The 103-pick baseline is methodologically cleaner**. Pre-V1.57 the 109 included 6 file-private declarations that violate cross-module visibility; the v1.57 baseline reflects what's actually verifiable.
