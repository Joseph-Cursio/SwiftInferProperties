# Cycle-59 full-surface measurement summary

Captured: 2026-05-13. swift-infer at v1.62.

## Aggregate

| Classification | Cycle-57 | Cycle-58 | Cycle-59 | Δ vs c58 |
|---|---:|---:|---:|---:|
| **measured-bothPass** | 7 | 19 | **27** | **+8** |
| measured-edgeCaseAdvisory | 8 | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 6 | 0 |
| measured-error | 0 | 0 | 0 | 0 |
| architectural-coverage-pending | 82 | 70 | **62** | **-8** |
| **Total measured-execution** | 21 | 33 | **41** | **+8** |
| **Rate** | 20.4% | 32.0% | **39.8%** | **+7.8pp** |

**+8 .bothPass — all 8 OrderedSet.UnorderedView dual-style picks closed.** Following the pattern from V1.61.B (12 OS dual-style picks); V1.62.A scaffolds the next nested carrier with 3 small edits.

## The 8 new .bothPass picks

All `OrderedSet.UnorderedView` × dual-style-consistency:

| Hash | Function |
|---|---|
| 0x01FF | `formUnion(_:)` |
| 0x39BE | `formIntersection(_:)` |
| 0x5AF3 | `formIntersection(_:)` |
| 0x6326 | `formUnion(_:)` |
| 0x73A9 | `subtract(_:)` |
| 0xA271 | `formSymmetricDifference(_:)` |
| 0xB683 | `subtract(_:)` |
| 0xFAE7 | `formSymmetricDifference(_:)` |

Each pick: generate 2 `OrderedSet<Int>.UnorderedView` instances per trial, assert `original.union(other) == { var c = original; c.formUnion(other); return c }` (and similarly for intersection/subtraction/etc.). 100 trials × 8 picks = 800 input pairs asserted equivalent across both call shapes for swift-collections's UnorderedView.

## Detail-string distribution

| Detail | Cycle-58 | Cycle-59 | Δ |
|---|---:|---:|---:|
| `unsupported-carrier: OrderedSet.UnorderedView` | 8 | **0** | **-8** |
| `instance-method-shape-not-supported` | 4 | 4 | 0 |
| `internal-api-not-accessible` | 9 | 9 | 0 |
| `carrier-missing-required-conformance` | 2 | 2 | 0 |
| `unsupported-carrier: OrderedSet<Int>` (round-trip resolver layer) | 3 | 3 | 0 |
| Other `unsupported-carrier: <other-OC>` | 44 | 44 | 0 |

The `OrderedSet.UnorderedView` detail-string is eliminated entirely (8 → 0). The remaining 4 `instance-method-shape-not-supported` picks are commutativity/associativity discover-layer false-positives (`distance(from:Int,to:Int)` doesn't have commutativity over OS values; v1.62 noted as not-easily-fixable in current architecture).

## OS-family coverage so far

| Carrier | Picks | .bothPass | Pending |
|---|---:|---:|---:|
| `OrderedSet<Int>` | 29 | 13 (1 idempotence + 12 dual-style) | 16 |
| **`OrderedSet<Int>.UnorderedView`** | **8** | **8** | **0** |
| **OS-family total** | **37** | **21** | **16** |

OS-family is now 57% measured. The remaining 16 are 7 internal-api + 2 conformance + 3 round-trip-resolver + 4 discover-layer false-positives.

## What cycle-59 establishes

1. **The scaffold pattern (binding + recipe + gate) generalizes to nested-OC carriers** without new emission shape. V1.62.A is 3 small edits across 3 files; V1.61.A+B's curated-pair + emission carry forward unchanged.

2. **`.measured-error = 0` baseline preserved.**

3. **Measured-execution rate now ~40%** — up from ~10% at the start of v1.53. 6 OC closures (1 in v1.60, 12 in v1.61, 8 in v1.62) brought 21 of 29 OS-family picks to `.bothPass` over 3 cycles.

4. **The remaining 25 nested-OC carriers** (OD.Elements 7, OS.SubSequence 6, OD.Values 6, OD.Elements.SubSequence 6) likely each need their own bindings + recipes. v1.63+ scope.

## v1.63+ priorities

In priority order:

1. **v1.63 — Strategist recipes for the remaining 4 nested-OC carriers**. 25 picks (the bulk of remaining pending). Each carrier follows the V1.62.A 3-edit pattern (binding + recipe + gate). Some templates may need new emit shapes (e.g., OD.Values is a sequence-of-values type; not all SetAlgebra picks apply).

2. **v1.63 — Strategist recipes for non-OC generics** (17 picks: `_HashTable`, `_HashTable.UnsafeHandle`, `OrderedDictionary`, `EvenlyChunkedCollection`, `ChunkedByCollection`, `CombinationsSequence`, `_UnsafeHashTable`).

3. **v1.64 — Comparable-aware monotonicity composer** (2 picks).

4. **v1.64 — Add `_minimumCapacity/_maximumCapacity` curated round-trip pair** — closes the 3 round-trip OS picks at the resolver layer (likely reclassifies via V1.56.A to internal-api).

5. **v1.65+ — Phase 2 accept-flow integration** — demonstrably viable.

6. **v1.65+ — Methodology guard for curated-pair tables** — V1.58.B-style fixture check for `RoundTripPairResolver.curated` + `DualStyleConsistencyPairResolver.curated`.

## Methodology notes

- **Wall-clock**: ~14 min for the 103-pick survey. +1-2 min over cycle-58's ~12-15 (8 additional picks running full property-check + edge pass).
- **The V1.62.A 3-edit pattern is reusable** for v1.63's nested-OC carriers. Each adds ~10 LoC.
- **The mutating-instance-method emission scales** — V1.60.A's 1-pick scaffold → V1.61.B's 12-pick batch → V1.62.A's 8-pick batch. Same gate, same emit shape, different carriers.
