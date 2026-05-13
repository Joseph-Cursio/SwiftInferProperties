# Cycle-57 full-surface measurement summary

Captured: 2026-05-13. swift-infer at v1.60 (post-V1.60.A+B). **First non-Complex/Double measured-bothPass in the project's calibration history.**

## Aggregate

| Classification | Cycle-55 (103) | Cycle-56 (103) | Cycle-57 (103) | Δ vs c56 |
|---|---:|---:|---:|---:|
| **measured-bothPass** | 6 | 6 | **7** | **+1** |
| measured-edgeCaseAdvisory | 8 | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 6 | 0 |
| measured-error | 0 | 0 | 0 | 0 |
| architectural-coverage-pending | 83 | 83 | **82** | **-1** |
| **Total measured-execution** | 20 | 20 | **21** | **+1** |
| **Rate** | 19.4% | 19.4% | **20.4%** | **+1.0pp** |

**The +1 is `OrderedSet.sort()` reaching `.bothPass`** via V1.60.A's mutating-instance-method emit shape. First OC pick to produce a real measurement.

## Detail-string distribution

| Detail | Cycle-56 | Cycle-57 | Δ |
|---|---:|---:|---:|
| `instance-method-shape-not-supported` | 21 | **16** | **-5** |
| `internal-api-not-accessible` | 5 | **9** | **+4** |
| `carrier-missing-required-conformance` | 2 | 2 | 0 |
| `unsupported-carrier: OrderedSet<Int>` | 3 | 3 | 0 |
| `unsupported-carrier: <other-OC>` | 52 | 52 | 0 |

**5-pick shift breakdown**:
- **1** moved to `.bothPass` (sort()).
- **4** moved to `internal-api-not-accessible`: `_ensureUnique`, `_isUnique`, `_regenerateHashTable`, `_regenerateExistingHashTable`. With the new emit shape (`copy._ensureUnique()` instead of `OrderedSet._ensureUnique(value)`), Swift emits the canonical "is inaccessible due to 'internal'" diagnostic, which V1.56.A's pattern matcher correctly catches. Previously these surfaced as swift-frontend crashes that V1.59.A's signal-6 pattern caught as `instance-method-shape-not-supported` (less accurate).

## What V1.60.A accomplished

**Single pick closure** (`OrderedSet.sort()` × idempotence): the verifier ran 100 trials of OS<Int> values through `var copy1 = value; copy1.sort(); var copy2 = value; copy2.sort(); copy2.sort(); assert copy1 == copy2`. All 100 trials passed. Sorting an OrderedSet twice yields the same result as sorting once — `.bothPass` is the correct outcome.

**Methodology side-effect**: V1.60.A's emit shape also restores accurate categorization for the 4 internal-mutating OS picks. Pre-v1.60 they surfaced as swift-frontend crashes (V1.59.A's signal-6 pattern caught them as `instance-method-shape-not-supported`); post-v1.60 they fail with the canonical "is inaccessible" diagnostic and V1.56.A's pattern recognizes them as `internal-api-not-accessible`. Same architectural category (pending), more accurate detail.

## OS pick movement (29 cycle-27 picks)

| Bucket | Cycle-56 | Cycle-57 | Δ |
|---|---:|---:|---:|
| `.bothPass` | 0 | **1** | **+1** |
| `instance-method-shape-not-supported` | 21 (of which OS: 21) | 16 (of which OS: ~16) | -5 |
| `internal-api-not-accessible` | 5 (of which OS: 3) | 9 (of which OS: 7) | +4 |
| `carrier-missing-required-conformance` | 2 | 2 | 0 |
| `unsupported-carrier: OrderedSet<Int>` | 3 | 3 | 0 |

OS picks total: 1 + ~16 + 7 + 2 + 3 = 29 ✓.

## Cycle-46 predictions vs cycle-57 actuals

The OS picks weren't in the cycle-46 stratified subset, so the existing match rates carry forward unchanged:
- **Strict 4-category match**: 5 / 13 = 38%
- **Semantic "property holds" match**: 13 / 13 = **100%**

The new `OrderedSet.sort()` pick adds an additional measurable result (not in the cycle-46 subset).

## What cycle-57 establishes

1. **V1.60.A delivers the first non-Complex/Double OC closure.** `OrderedSet.sort()` idempotence reaches `.bothPass` after 100 trials. **Milestone: the measurable subset now spans 3 distinct carriers** (Complex, Double, OrderedSet) — the architecture isn't single-carrier-bound.

2. **The mutating-instance-method emit shape works as designed.** Method-name extraction (split on `.`, take last) is reliable for the cycle-27 surface. v1.61+ extends the pattern to dual-style + commutativity instance methods.

3. **V1.60.A had a methodology side-effect: 4 internal-mutating OS picks now categorize correctly** as `internal-api-not-accessible` rather than `instance-method-shape-not-supported`. The previous compiler-crash-driven classification was less accurate; v1.60's emit shape exposes the real diagnostic.

4. **`.measured-error = 0` baseline preserved.** v1.60 introduces no new error categories; V1.56.A's reclassification continues to handle build-time errors cleanly.

5. **The remaining 16 instance-method-shape-not-supported picks** are now exclusively dual-style + commutativity/associativity. v1.61 targets those.

## v1.61+ priorities (per cycle-57 evidence)

In priority order:

1. **v1.61 — Mutating-instance-method dual-style-consistency emission**. 12 picks. Requires both (a) fixing `DualStyleConsistencyPairResolver`'s mismatched curated pairs (V1.51.B treats `formUnion` as both nonMutating and mutating — should be `union` (non-mut) ↔ `formUnion` (mut) per Swift SetAlgebra) and (b) new emit shape: `let nonMutResult = value.union(other); var copy = value; copy.formUnion(other); assert nonMutResult == copy`.

2. **v1.61 — Commutativity/associativity instance-method emission**. 4 picks (`index(_:offsetBy:)` × commutativity + associativity, `distance(from:to:)` × commutativity + associativity). Shape: `value.method(args)` instead of `Type.method(value, args)`. Note: these picks may not actually satisfy commutativity/associativity semantically (e.g., `distance` is signed); cycle-58 outcome will tell.

3. **v1.61-v1.62 — Strategist recipes for nested-OC carriers** (33 picks). `OrderedSet.UnorderedView`, `OrderedDictionary.Elements`, etc.

4. **v1.62 — Comparable-aware monotonicity composer** (2 picks).

5. **v1.62 — Strategist recipes for non-OC generics** (17 picks).

6. **v1.63+ — Phase 2 accept-flow integration**.

## Methodology notes

- **Wall-clock**: ~8-10 min for the 103-pick survey. Slight reduction from cycle-56 (~10-12 min) because the 4 internal-mutating OS picks now fail quickly at access-check rather than crashing the compiler.
- **The "first non-Complex/Double measured-bothPass" milestone** is significant for project framing. Pre-v1.60 the measurable subset was 100% FP (Complex, Double). v1.60 demonstrably extends to collection carriers.
- **V1.60.A's hardcoded `mutatingInstanceCarriers = {"OrderedSet<Int>"}` is the same scaling pattern as V1.51.A's `Complex`-only canonicalization** — start with one carrier, validate, extend to more in subsequent cycles.
