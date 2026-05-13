# v1.62 Calibration Cycle 59 — Findings (+8 .bothPass; OS-family now 57% measured)

Captured: 2026-05-13. swift-infer at v1.62.

## Headline

**+8 .bothPass** — all 8 OrderedSet.UnorderedView dual-style picks closed. V1.62.A's 3-edit scaffold (binding + recipe + mutatingInstanceCarriers gate) reuses V1.61.B's emission unchanged.

| Outcome | Cycle-58 (103) | Cycle-59 (103) | Δ |
|---|---:|---:|---:|
| **measured-bothPass** | 19 | **27** | **+8** |
| measured-edgeCaseAdvisory | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 0 |
| measured-error | 0 | 0 | 0 |
| architectural-coverage-pending | 70 | **62** | **-8** |

**Measured-execution rate: 32.0% → 39.8% (+7.8pp).**

**OS-family coverage**: 29 OS picks → 13 closed (V1.60+V1.61), 8 OS.UnorderedView picks → 8 closed (V1.62). Combined: **21/37 = 57% OS-family measured** in 3 release cycles.

## What V1.62.A accomplished

Three small edits, no new emission shape:

1. **GenericBindingResolver.curatedBindings**: `"OrderedSet.UnorderedView" → "OrderedSet<Int>.UnorderedView"`
2. **StrategistDispatchEmitter.curatedOCRecipe**: new branch for `OrderedSet<Int>.UnorderedView` with `Gen<Int>.int(in: 0 ... 100).map { OrderedSet([$0, $0+1, $0+2, $0+3]).unordered }`
3. **mutatingInstanceCarriers**: added `"OrderedSet<Int>.UnorderedView"`

V1.61.A's curated SetAlgebra pair table + V1.61.B's `composeMutatingDualStylePass` carry forward unchanged — same `formUnion`/`formIntersection`/`formSymmetricDifference`/`subtract` names work on the nested-view type.

## What cycle-59 establishes

1. **The scaffold pattern (binding + recipe + gate) generalizes** to nested-OC carriers without new emission shape. v1.63 can apply the same 3-edit pattern to OD.Elements, OS.SubSequence, OD.Values, OD.Elements.SubSequence.

2. **`.measured-error = 0` baseline preserved.**

3. **OS-family is meaningfully measured at scale** — 21/37 = 57% with 100-trial property checks each.

4. **Measured-execution rate ~40%** — up from ~10% at v1.53 (cycle-50). 3 OC cycles (v1.60/v1.61/v1.62) closed 21 OS-family picks total.

## v1.63+ priorities

In priority order:

1. **v1.63 — Strategist recipes for the remaining nested-OC carriers** (25 picks: 7 OD.Elements, 6 OS.SubSequence, 6 OD.Values, 6 OD.Elements.SubSequence). Each follows V1.62.A's 3-edit pattern.

2. **v1.63 — Strategist recipes for non-OC generics** (17 picks).

3. **v1.64 — Comparable-aware monotonicity composer** (2 picks).

4. **v1.64 — `_minimumCapacity/_maximumCapacity` curated round-trip pair** (3 picks at the resolver layer; likely reclassify to internal-api).

5. **v1.65+ — Phase 2 accept-flow integration** — demonstrably viable (40% measured, 0 measured-error).

## Captured artifacts

- Cycle-59 survey JSON: `docs/calibration-cycle-59-data/full-surface-outcomes.json` (103 entries).
- Aggregate summary: `docs/calibration-cycle-59-data/full-surface-summary.md`.
- V1.62.A code — staged.
