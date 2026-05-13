# v1.61 Calibration Cycle 58 — Findings (+12 .bothPass; biggest single-cycle gain in project history)

Captured: 2026-05-13. swift-infer at v1.61. Fifty-eighth execution of PRD §17.3's empirical-tuning loop.

## Headline

**+12 measured-bothPass picks in a single cycle.** All 12 OrderedSet SetAlgebra dual-style-consistency picks reached `.bothPass` at 100 trials each. **Biggest single-cycle measured-execution gain in the project's history.**

| Outcome | Cycle-57 (103) | Cycle-58 (103) | Δ |
|---|---:|---:|---:|
| **measured-bothPass** | 7 | **19** | **+12** |
| measured-edgeCaseAdvisory | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 0 |
| measured-error | 0 | 0 | 0 |
| architectural-coverage-pending | 82 | **70** | **-12** |

**Measured-execution rate: 20.4% → 32.0% (+11.6pp).**

## What V1.61.A + V1.61.B accomplished

**V1.61.A — Fixed V1.51.B's mismatched curated pairs.** V1.51.B (cycle-47) introduced 4 SetAlgebra dual-style pairs but with both halves mapped to the same name (`Pair(nonMutating: "formUnion(_:)", mutating: "formUnion")` — treated the mutating-form as the non-mutating spelling). Per Swift's `SetAlgebra` protocol the actual pair is `union(_:)` (non-mut) ↔ `formUnion(_:)` (mut), and similarly for `intersection ↔ formIntersection`, `symmetricDifference ↔ formSymmetricDifference`, `subtracting ↔ subtract`. V1.61.A corrects all 4 pairs.

Since cycle-27 captures the mutating name (`formUnion(_:)`) as `primaryFunctionName`, V1.61.A also updates the resolver's lookup to match against **either** field (with parameter-label stripping for cross-format flexibility). Future cycles can add curated entries by either the mutating or non-mutating name.

**V1.61.B — Mutating-instance-method dual-style emission.** New `composeMutatingDualStylePass` helper gated on `mutatingInstanceCarriers.contains(recipe.carrierTypeName)`. Generates 2 OC values per trial; both halves use instance-method call shape with the second value as argument:

```swift
let original = defaultGenerator.run(...)
let other = defaultGenerator.run(...)
let nonMutResult = original.union(other)
var mutCopy = original
mutCopy.formUnion(other)
if nonMutResult != mutCopy { fail }
```

For non-OC dual-style picks (`sorted/sort`, `reversed/reverse`, `shuffled/shuffle` — 0-arg variants), the existing v1.48.B emit path carries forward.

## The 12 new .bothPass picks (cycle-27 OS dual-style surface)

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

All 12 picks verify Swift SetAlgebra's mutating-vs-non-mutating equivalence contract for swift-collections's `OrderedSet<Int>`.

## What cycle-58 establishes

1. **The mutating-instance-method emit pattern generalizes.** V1.60.A's 1-pick scaffold (idempotence on sort) extended to 12 dual-style picks via V1.61.A+B. The pattern is reusable for v1.62's commutativity/associativity instance-method picks.

2. **V1.51.B's curated-pair bug had non-trivial impact.** The mismatched pairs blocked 12 picks from reaching `.bothPass` since v1.48 — ~13 release cycles of latent measurement-tooling gap. V1.61.A's correction is a methodology lesson: curated tables that name foreign-API methods need cross-checking against the target API's conventions, not just the indexer's outputs.

3. **Biggest single-cycle measured-execution gain in project history.** +12 `.bothPass` exceeds the cumulative wins from cycles 50-57 combined (+13 `.bothPass` across 8 cycles).

4. **The measurable subset spans 13 OS picks now.** 1 idempotence (sort) + 12 dual-style. The architecture's OC coverage is meaningfully demonstrated; v1.62+ extends to commutativity/associativity + nested-OC carriers.

5. **`.measured-error = 0` baseline preserved.**

6. **The remaining 4 `instance-method-shape-not-supported` picks** are commutativity/associativity instance methods (`index(_:offsetBy:)`, `distance(from:to:)`). v1.62 target.

## Cycle-46 predictions vs cycle-58 actuals

OS picks aren't in the cycle-46 stratified subset (cycle-46 sampled from the v1.42-era surface which had fewer OC carriers):
- **Strict 4-category match (on cycle-46 subset)**: 5 / 13 = 38%
- **Semantic "property holds" match (on cycle-46 subset)**: 13 / 13 = **100%**

The new 13 OS `.bothPass` outcomes extend the measurable set substantially beyond the cycle-46 sample. Per-pick correctness on these 13 — verified empirically via 100 trials × 13 picks = 1300 OS-input samples; all asserted equality between non-mutating and mutating SetAlgebra spellings.

## v1.62+ priorities (per cycle-58 evidence)

In priority order:

1. **v1.62 — Commutativity/associativity instance-method emission**. 4 picks. Shape: `value.method(args)` instead of `Type.method(value, args)`. Cycle-59 may reveal `distance(from:to:)` doesn't satisfy commutativity semantically (signed); `.defaultFails` is the expected outcome.

2. **v1.62-v1.63 — Strategist recipes for nested-OC carriers** (33 picks: 8 `OrderedSet.UnorderedView`, 7 `OrderedDictionary.Elements`, 6 each for several others).

3. **v1.63 — Comparable-aware monotonicity composer** (2 picks).

4. **v1.63 — Strategist recipes for non-OC generics** (17 picks).

5. **v1.64+ — Phase 2 accept-flow integration** — demonstrably viable (32% measured rate, 0 measured-error, 13 OC picks measurable).

## Captured artifacts

- Cycle-58 survey JSON: `docs/calibration-cycle-58-data/full-surface-outcomes.json` (103 entries).
- Aggregate summary: `docs/calibration-cycle-58-data/full-surface-summary.md`.
- V1.61.A + V1.61.B code + updated V1.51.B tests — staged for the v1.61 commit.

## Open threads carried into v1.62

1. **Commutativity/associativity instance-method emission** — 4 picks; smaller emit shape change than dual-style.
2. **Nested-OC strategist recipes** — 33 picks; biggest residual category.
3. **`distance` commutativity** — may surface as `.defaultFails`; correct verifier behavior on a non-property.
4. **Methodology-guard parallel for curated-pair tables** — V1.58.B caught binding-table latent issues; a similar fixture-level check for `DualStyleConsistencyPairResolver.curated` would have surfaced V1.51.B's mismatch pre-merge.
5. **`mutatingInstanceCarriers` set growth** — v1.62 may add `OrderedDictionary<Int, Int>` etc. as more recipes land.
