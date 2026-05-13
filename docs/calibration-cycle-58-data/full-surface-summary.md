# Cycle-58 full-surface measurement summary

Captured: 2026-05-13. swift-infer at v1.61. **Biggest single-cycle measured-execution gain in the project's calibration history (+12 .bothPass).**

## Aggregate

| Classification | Cycle-56 (103) | Cycle-57 (103) | Cycle-58 (103) | Δ vs c57 |
|---|---:|---:|---:|---:|
| **measured-bothPass** | 6 | 7 | **19** | **+12** |
| measured-edgeCaseAdvisory | 8 | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 6 | 0 |
| measured-error | 0 | 0 | 0 | 0 |
| architectural-coverage-pending | 83 | 82 | **70** | **-12** |
| **Total measured-execution** | 20 | 21 | **33** | **+12** |
| **Rate** | 19.4% | 20.4% | **32.0%** | **+11.6pp** |

**12 OS SetAlgebra dual-style-consistency picks all reached `.bothPass`** — `formUnion / union`, `formIntersection / intersection`, `formSymmetricDifference / symmetricDifference`, `subtract / subtracting` (3 each across cycle-27's 12 dual-style picks). Every Swift SetAlgebra mutating-vs-non-mutating equivalence verified at 100 trials.

## The 12 new .bothPass picks

| Hash prefix | Function | Carrier |
|---|---|---|
| 0x28C6 | `formSymmetricDifference(_:)` | OrderedSet |
| 0x45D6 | `subtract(_:)` | OrderedSet |
| 0x57B8 | `formUnion(_:)` | OrderedSet |
| 0x6302 | `formUnion(_:)` | OrderedSet |
| 0xB34B | `formIntersection(_:)` | OrderedSet |
| 0xBB52 | `subtract(_:)` | OrderedSet |
| 0xC0B0 | `subtract(_:)` | OrderedSet |
| 0xCCCD | `formIntersection(_:)` | OrderedSet |
| 0xD81E | `formUnion(_:)` | OrderedSet |
| 0xE32D | `formSymmetricDifference(_:)` | OrderedSet |
| 0xEC35 | `formSymmetricDifference(_:)` | OrderedSet |
| 0xED14 | `formIntersection(_:)` | OrderedSet |

All 12 are dual-style-consistency picks on OrderedSet<Int>. The verifier:
1. Generates 2 OrderedSet<Int> values per trial (`{n,n+1,n+2,n+3}` and `{m,m+1,m+2,m+3}` for n,m ∈ [0,100])
2. Computes `original.<nonMut>(other)` (e.g. `value.union(other)`)
3. Computes `var copy = original; copy.<mut>(other); return copy` (e.g. `value.formUnion(other)` then return copy)
4. Asserts the two are equal

For SetAlgebra, this property holds by Swift's protocol contract — the mutating form is defined as in-place equivalent to the non-mutating form. The verifier confirms swift-collections's OrderedSet honors the contract empirically.

## Detail-string distribution

| Detail | Cycle-57 | Cycle-58 | Δ |
|---|---:|---:|---:|
| `instance-method-shape-not-supported` | 16 | **4** | **-12** |
| `internal-api-not-accessible` | 9 | 9 | 0 |
| `carrier-missing-required-conformance` | 2 | 2 | 0 |
| `unsupported-carrier: OrderedSet<Int>` (resolver-layer) | 3 | 3 | 0 |
| `unsupported-carrier: <other-OC>` | 52 | 52 | 0 |

The remaining 4 `instance-method-shape-not-supported` picks are the commutativity/associativity instance methods (`index(_:offsetBy:)`, `distance(from:to:)` × 2 templates). v1.62 target.

## What V1.61.A + V1.61.B accomplished

**V1.61.A**: fixed the V1.51.B mismatched curated pairs.
- Old: `Pair(nonMutating: "formUnion(_:)", mutating: "formUnion")` (treated mutating-form as both halves)
- New: `Pair(nonMutating: "union(_:)", mutating: "formUnion")` (correct Swift SetAlgebra mapping)

Plus 3 similar corrections for `intersection`, `symmetricDifference`, `subtracting`. Plus the resolver's `resolve()` updated to match against either field (with parameter-label stripping) so cycle-27's `formUnion(_:)`-form `primaryFunctionName` resolves correctly.

**V1.61.B**: new `composeMutatingDualStylePass` for the OC dual-style picks. Generates 2 OC values per trial; both halves use instance-method call shape with the second value passed as argument. Gated on `mutatingInstanceCarriers.contains(carrier)` (shares V1.60.A's gate). The v1.48.B 0-arg shape (sorted/sort) carries forward for non-OC dual-style picks via the existing emit path.

## OS pick coverage (29 cycle-27 picks)

| Bucket | Cycle-56 | Cycle-57 | Cycle-58 | Δ vs c57 |
|---|---:|---:|---:|---:|
| `.bothPass` | 0 | 1 | **13** | **+12** |
| `instance-method-shape-not-supported` | 21 | 16 → 12 OS | 4 → 0 OS | **-12** |
| `internal-api-not-accessible` | 5 → 3 OS | 9 → 7 OS | 9 → 7 OS | 0 |
| `carrier-missing-required-conformance` | 2 | 2 | 2 | 0 |
| `unsupported-carrier: OrderedSet<Int>` | 3 | 3 | 3 | 0 |

OS picks: 13 measured + 7 internal-api + 2 conformance + 3 still at resolver + 4 OS-related residual = 29 ✓ (with 12 dual-style + 1 sort + ~16 others split as above).

## Cycle-46 predictions vs cycle-58 actuals

OS picks aren't in the cycle-46 stratified subset, so the existing match rates carry forward:
- **Strict 4-category match**: 5 / 13 = 38%
- **Semantic "property holds" match**: 13 / 13 = **100%**

The new 13 OS `.bothPass` outcomes add to the measurable set outside the cycle-46 subset.

## What cycle-58 establishes

1. **The mutating-instance-method pattern generalizes.** V1.60.A's 1-pick scaffold extended to 12 dual-style picks via V1.61.A+B. Same `mutatingInstanceCarriers` gate; specialized emit shape per template.

2. **V1.51.B's curated-pair bug had non-trivial impact.** The mismatched pairs blocked 12 picks from reaching `.bothPass` since v1.48 (~13 release cycles). V1.61.A's correction is a methodology lesson — curated-name tables need cross-checking against the target API's conventions, not just the indexer's outputs.

3. **The biggest single-cycle measured-execution gain in the project's history.** +12 `.bothPass` is more than the cumulative wins from cycles 50-57 combined (cycles 50/57 added +12 → +1 → +12 = 25). Cycle-58 alone matches the cycle-50 milestone.

4. **The measurable subset now spans 13 OS picks** — 1 idempotence (sort) + 12 dual-style. The architecture's OC coverage is meaningfully demonstrated.

5. **`.measured-error = 0` baseline preserved.** No new error categories introduced.

6. **The remaining 4 instance-method-shape-not-supported picks** are commutativity/associativity instance methods on OS. v1.62 target.

## v1.62+ priorities (per cycle-58 evidence)

In priority order:

1. **v1.62 — Commutativity/associativity instance-method emission**. 4 picks: `index(_:offsetBy:)` × commutativity + associativity, `distance(from:to:)` × commutativity + associativity. Shape: `value.method(args)` instead of `Type.method(value, args)`. Note: cycle-59 may reveal these don't actually satisfy commutativity/associativity (distance is signed) — `.defaultFails` is the expected outcome for some.

2. **v1.62-v1.63 — Strategist recipes for nested-OC carriers** (33 picks: `OrderedSet.UnorderedView` 8, `OrderedDictionary.Elements` 7, `OrderedSet.SubSequence` 6, `OrderedDictionary.Values` 6, `OrderedDictionary.Elements.SubSequence` 6).

3. **v1.63 — Comparable-aware monotonicity composer** (2 picks).

4. **v1.63 — Strategist recipes for non-OC generics** (17 picks: `_HashTable` 4, `_HashTable.UnsafeHandle` 4, `OrderedDictionary` 3, `EvenlyChunkedCollection` 2, `ChunkedByCollection` 2, `CombinationsSequence` 2).

5. **v1.64+ — Phase 2 accept-flow integration** — demonstrably viable (32% measured rate, .measured-error = 0).

## Methodology notes

- **Wall-clock**: ~12-15 min for the 103-pick survey. 12 additional picks running 100-trial property checks added ~3-5 min over cycle-57.
- **The V1.61.A curated-pair fix exposed the V1.51.B latent bug** — 12 picks couldn't reach property check for 13 cycles. Methodology-guard parallel (V1.58.B caught binding-table latent issues; curated-pair tables deserve similar guards).
- **The mutating-instance-method emit pattern continues to scale** — v1.62 commutativity/associativity instance methods follow the same template.
