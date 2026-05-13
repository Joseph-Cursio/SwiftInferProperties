# v1.60 Calibration Cycle 57 — Findings (first non-Complex/Double measured-bothPass)

Captured: 2026-05-13. swift-infer at v1.60 (post-V1.60.A+B). Fifty-seventh execution of PRD §17.3's empirical-tuning loop.

## Headline

**`OrderedSet.sort()` reaches `.bothPass`** — first non-Complex/Double measured-execution outcome in the project's calibration history.

| Outcome | Cycle-56 (103) | Cycle-57 (103) | Δ |
|---|---:|---:|---:|
| **measured-bothPass** | 6 | **7** | **+1** |
| measured-edgeCaseAdvisory | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 0 |
| measured-error | 0 | 0 | 0 |
| architectural-coverage-pending | 83 | **82** | **-1** |

**Total measured-execution: 21 / 103 = 20.4%** (up from cycle-56's 19.4%). +1 pick = the OS sort() closure.

## What V1.60.A accomplished

**`composeMutatingIdempotencePass`** — new emit shape for OC carriers (`mutatingInstanceCarriers = {"OrderedSet<Int>"}`). Replaces the static-call shape with:

```swift
var onceCopy = value
onceCopy.<methodName>()
var twiceCopy = value
twiceCopy.<methodName>()
twiceCopy.<methodName>()
if onceCopy != twiceCopy { fail }
```

For `OrderedSet.sort()` × idempotence: 100 trials of OS<Int> values pass — sorting twice yields the same result as sorting once. `.bothPass` is the mathematically correct outcome.

**Side effect — 4 internal-mutating OS picks reclassified.** Pre-v1.60 these (`_ensureUnique`, `_isUnique`, `_regenerateHashTable`, `_regenerateExistingHashTable`) compiled into swift-frontend crashes (V1.59.A's signal-6 pattern caught them as `instance-method-shape-not-supported`). Post-v1.60 the new emit shape produces canonical `"is inaccessible due to 'internal'"` diagnostics, which V1.56.A's pattern matcher correctly attributes as `internal-api-not-accessible`. The category shift (instance-method-shape → internal-api) is **more accurate categorization**.

## Detail-string movement

| Detail | Cycle-56 | Cycle-57 | Δ |
|---|---:|---:|---:|
| `instance-method-shape-not-supported` | 21 | **16** | **-5** |
| `internal-api-not-accessible` | 5 | **9** | **+4** |
| `carrier-missing-required-conformance` | 2 | 2 | 0 |
| `unsupported-carrier: OrderedSet<Int>` (resolver-layer) | 3 | 3 | 0 |
| `unsupported-carrier: <other-OC>` | 52 | 52 | 0 |

**5-pick movement**: 1 to `.bothPass` + 4 to `internal-api-not-accessible`. The remaining 16 `instance-method-shape-not-supported` picks are 12 dual-style-consistency + 4 commutativity/associativity instance methods (v1.61+ scope).

## Cycle-46 predictions vs cycle-57 actuals

OS picks weren't in the cycle-46 stratified subset, so existing match rates unchanged:
- **Strict 4-category match**: 5 / 13 = 38%
- **Semantic "property holds" match**: 13 / 13 = **100%**

The new `OrderedSet.sort()` pick adds 1 additional measurable result outside the cycle-46 subset.

## What cycle-57 establishes

1. **First non-Complex/Double measured-bothPass.** The measurable subset spans 3 distinct carriers (Complex, Double, OrderedSet) — the architecture isn't single-carrier-bound.

2. **Mutating-instance-method idempotence shape works as designed.** Method-name extraction (split on `.`, take last) is reliable for the cycle-27 surface. Pattern extends to v1.61+'s dual-style + commutativity workstreams.

3. **V1.60.A had a useful side-effect on internal-mutating picks.** The new emit shape exposes the real `internal` access diagnostic instead of triggering a compiler crash; 4 picks reclassify to `internal-api-not-accessible` (more accurate detail).

4. **`.measured-error = 0` baseline preserved.** V1.60 introduces no new error categories; V1.56.A's reclassification continues to handle build-time errors cleanly.

5. **The remaining 16 `instance-method-shape-not-supported` picks** are exclusively dual-style + commutativity/associativity instance methods. v1.61 targets dual-style (12 picks, biggest single category).

## v1.61+ priorities (per cycle-57 evidence)

In priority order:

1. **v1.61 — Mutating-instance-method dual-style-consistency emission**. 12 picks. Requires (a) fixing `DualStyleConsistencyPairResolver`'s mismatched V1.51.B curated pairs (`formUnion` mapped to itself; should be `union` ↔ `formUnion` per Swift SetAlgebra) and (b) new emit shape: `let nonMutResult = value.union(other); var copy = value; copy.formUnion(other); assert nonMutResult == copy`.

2. **v1.61 — Commutativity/associativity instance-method emission**. 4 picks. Shape: `value.method(args)` instead of `Type.method(value, args)`. Note: cycle-58 may reveal `distance` isn't actually commutative/associative semantically (it's signed) — discover-side template-matching may be over-eager. The verifier's `.defaultFails` outcome would correctly flag this.

3. **v1.61-v1.62 — Strategist recipes for nested-OC carriers** (33 picks).

4. **v1.62 — Comparable-aware monotonicity composer** (2 picks).

5. **v1.62 — Strategist recipes for non-OC generics** (17 picks).

6. **v1.63+ — Phase 2 accept-flow integration**.

## Captured artifacts

- Cycle-57 survey JSON: `docs/calibration-cycle-57-data/full-surface-outcomes.json` (103 entries).
- Aggregate summary: `docs/calibration-cycle-57-data/full-surface-summary.md`.
- V1.60.A + V1.60.B code + tests — staged for the v1.60 commit.

## Open threads carried into v1.61

1. **Dual-style-consistency curated-pair fix** — V1.51.B's pairs are mismatched per Swift SetAlgebra convention. v1.61.A target.
2. **Instance-method emission for commutativity/associativity templates** — 4 picks; simpler than dual-style (single function, multiple args).
3. **`mutatingInstanceCarriers` set growth** — v1.61 may add `OrderedSet<Int>` (already there), `OrderedDictionary<Int, Int>`, others as recipes land.
4. **`distance` commutativity** — might surface as `.defaultFails` rather than `.bothPass` once it reaches the property check (distance is signed; commutativity requires unsigned).
5. **`.measured-error = 0` baseline** — depends on V1.59.A's reclassification continuing to catch new error patterns.
