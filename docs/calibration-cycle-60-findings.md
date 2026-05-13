# v1.63 Calibration Cycle 60 — Findings (+1 .bothPass; diminishing-returns pivot point)

Captured: 2026-05-13. swift-infer at v1.63.

## Headline

**+1 .bothPass** (OD.Elements.sort()). Plus V1.63.A reclassification pattern extension absorbs 3 newly-surfaced false-positive build failures, preserving `.measured-error = 0` baseline.

| Outcome | Cycle-59 | Cycle-60 | Δ |
|---|---:|---:|---:|
| measured-bothPass | 27 | **28** | **+1** |
| measured-error | 0 | 0 | 0 |
| architectural-coverage-pending | 62 | 61 | -1 |

**Rate**: 39.8% → 40.8%. **Diminishing-returns pivot**: v1.62 closed 8 picks, v1.63 closed 1. The remaining nested-OC carriers (OS.SubSequence, OD.Values, OD.Elements.SubSequence) are dominated by commutativity/associativity discover-layer false-positives + Comparable-blocked monotonicity. Future cycles should pivot to Comparable-aware monotonicity (unblocks broader pick category) or non-OC generics.

## What V1.63.A accomplished

3-edit scaffold for OD.Elements + reclassification pattern for "generic parameter could not be inferred":

1. Binding: `OrderedDictionary.Elements → OrderedDictionary<Int, Int>.Elements`
2. Recipe: `Gen<Int>.int(...).map { OrderedDictionary(uniqueKeysWithValues: [...]).elements }`
3. Gate: added to `mutatingInstanceCarriers`
4. Pattern extension: `architecturalPendingDetail` recognizes `"generic parameter" + "could not be inferred"` → `instance-method-shape-not-supported`

V1.61.B's `composeMutatingDualStylePass` + V1.60.A's idempotence emission carry forward unchanged.

## OD.Elements pick distribution (7 picks)

| Outcome | Count | Picks |
|---|---:|---|
| `.bothPass` | 1 | sort() |
| `instance-method-shape-not-supported` | 4 | commutativity/associativity distance(from:to:), index(_:offsetBy:) — discover-layer false-positives |
| `carrier-missing-required-conformance` | 2 | monotonicity index(before:), index(after:) — Comparable required |

## OC-family coverage after v1.63

| Carrier | Picks | .bothPass | Pending |
|---|---:|---:|---:|
| OS<Int> | 29 | 13 | 16 |
| OS<Int>.UnorderedView | 8 | 8 | 0 |
| OD<Int,Int>.Elements | 7 | 1 | 6 |
| **OC-family** | **44** | **22** | **22** |

**50% OC-family measured.**

## v1.64+ priorities (re-prioritized per diminishing-returns)

1. **v1.64 — Comparable-aware monotonicity composer**. 4 picks currently blocked on Comparable; potentially unblocks more as future nested-OC carriers land.
2. **v1.64 — `_minimumCapacity/_maximumCapacity` curated round-trip pair** (3 picks).
3. **v1.65 — Non-OC generic scaffolds** (17 picks).
4. **v1.66 — Phase 2 accept-flow integration**.

## Captured artifacts

- Cycle-60 survey JSON: `docs/calibration-cycle-60-data/full-surface-outcomes.json` (103 entries).
- Aggregate summary: `docs/calibration-cycle-60-data/full-surface-summary.md`.
- V1.63.A code — staged.
