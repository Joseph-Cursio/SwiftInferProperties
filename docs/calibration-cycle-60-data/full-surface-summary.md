# Cycle-60 full-surface measurement summary

Captured: 2026-05-13. swift-infer at v1.63.

## Aggregate

| Classification | Cycle-58 | Cycle-59 | Cycle-60 | Δ vs c59 |
|---|---:|---:|---:|---:|
| **measured-bothPass** | 19 | 27 | **28** | **+1** |
| measured-edgeCaseAdvisory | 8 | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 6 | 0 |
| measured-error | 0 | 0 | 0 | 0 |
| architectural-coverage-pending | 70 | 62 | 61 | -1 |
| **Total measured-execution** | 33 | 41 | **42** | **+1** |
| **Rate** | 32.0% | 39.8% | **40.8%** | **+1.0pp** |

**+1 .bothPass** — `OrderedDictionary.Elements.sort()` idempotence closes. V1.63.A's 3-edit scaffold (binding + recipe + gate) reuses V1.60.A's idempotence emission for the new carrier.

## What V1.63.A accomplished

Three small edits, same pattern as V1.62.A:

1. **GenericBindingResolver**: `"OrderedDictionary.Elements" → "OrderedDictionary<Int, Int>.Elements"`.
2. **StrategistDispatchEmitter.curatedOCRecipe**: branch for `OrderedDictionary<Int, Int>.Elements` with `Gen<Int>.int(...).map { OrderedDictionary(uniqueKeysWithValues: [...]).elements }`.
3. **mutatingInstanceCarriers**: added `"OrderedDictionary<Int, Int>.Elements"`.

Plus V1.63.A reclassification pattern extension — new architectural-pending detail for the "generic parameter could not be inferred" diagnostic that Swift produces for static-call shape on nested generic types. Same category (`instance-method-shape-not-supported`) as the other instance-method-shape errors.

## Detail-string distribution

| Detail | Cycle-59 | Cycle-60 | Δ |
|---|---:|---:|---:|
| `instance-method-shape-not-supported` | 4 | **12** | **+8** |
| `internal-api-not-accessible` | 9 | 9 | 0 |
| `carrier-missing-required-conformance` | 2 | **4** | **+2** |
| `unsupported-carrier: OrderedDictionary.Elements` | 7 | **0** | **-7** |
| Other categories unchanged | | | |

The 7 OD.Elements picks moved out of `unsupported-carrier` into:
- 1 → `.bothPass` (OD.Elements.sort idempotence)
- 4 → `instance-method-shape-not-supported` (3 commutativity/associativity false-positives + 1 monotonicity-without-Comparable variant)
- 2 → `carrier-missing-required-conformance` (2 monotonicity picks needing Comparable)

## OC-family coverage

| Carrier | Picks | .bothPass | Pending |
|---|---:|---:|---:|
| `OrderedSet<Int>` | 29 | 13 | 16 |
| `OrderedSet<Int>.UnorderedView` | 8 | 8 | 0 |
| **`OrderedDictionary<Int, Int>.Elements`** | **7** | **1** | **6** |
| **OC-family subtotal** | **44** | **22** | **22** |

**22/44 = 50% OC-family measured** after v1.63.

## What cycle-60 establishes

1. **The 3-edit scaffold pattern works for OD.Elements.** Same as V1.62.A for UnorderedView.

2. **The "generic parameter ... could not be inferred" pattern is a new false-positive class** that V1.63.A's reclassification pattern matcher now catches. Critical for preserving the `.measured-error = 0` baseline across the OD.Elements scaffold transition.

3. **The marginal-pick returns diminish.** v1.62 closed 8 picks (UnorderedView); v1.63 closed 1 pick (OD.Elements.sort) + reclassified 6 others. The remaining nested-OC carriers have very few idempotence-on-mutating-method picks; most are commutativity/associativity false-positives + Comparable-blocked monotonicity.

4. **Future cycles should re-prioritize**: the dominant remaining work is (a) Comparable-aware monotonicity composer (unblocks 4+ picks), (b) non-OC generics scaffolding (17 picks), (c) the 3 round-trip OS picks at resolver. Adding more nested-OC scaffolds (OS.SubSequence, OD.Values, OD.Elements.SubSequence) closes very few picks per cycle.

## v1.64+ priorities (per cycle-60 evidence)

In priority order:

1. **v1.64 — Comparable-aware monotonicity composer**. Currently 4 picks blocked on `carrier-missing-required-conformance`. Plus future nested-OC monotonicity picks would benefit.

2. **v1.64 — `_minimumCapacity/_maximumCapacity` curated round-trip pair** (3 picks at resolver; likely reclassify to internal-api).

3. **v1.64-v1.65 — Strategist recipes for non-OC generics** (17 picks: `_HashTable`, `ChunkedByCollection`, etc.). Most are internal/private; many will reclassify to internal-api after compile-fail.

4. **v1.65 — Additional nested-OC scaffolds** (OS.SubSequence 6, OD.Values 6, OD.Elements.SubSequence 6) only if cycle-N evidence shows useful closure potential.

5. **v1.66+ — Phase 2 accept-flow integration**.

## Methodology notes

- **Wall-clock**: ~12-14 min for the 103-pick survey.
- **Pattern-matcher precision**: V1.63.A's "could not be inferred" pattern is sufficiently scoped (requires "generic parameter" + "could not be inferred"). False-positive risk is low.
- **The 3-edit scaffold pattern keeps shrinking returns** as the high-value targets (idempotence + dual-style on mutable carriers) get exhausted.
