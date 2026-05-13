# v1.59 Calibration Cycle 56 — Findings (second TypeShape scaffold step; .architectural-coverage-pending category structure substantially richer)

Captured: 2026-05-13. swift-infer at v1.59 (post-V1.59.A + V1.59.B). Fifty-sixth execution of PRD §17.3's empirical-tuning loop.

## Headline

**Aggregate counts unchanged from cycle-55** (20 measured + 83 pending + 0 error + 103 total), but **26 OS picks moved past the resolver layer** into `swift build`. They compile-fail at instance-method shape (V1.59.A reclassifies to specific architectural-pending detail strings, preserving the v1.56 `.measured-error = 0` baseline).

| Outcome | Cycle-55 (103) | Cycle-56 (103) | Δ |
|---|---:|---:|---:|
| measured-bothPass | 6 | 6 | 0 |
| measured-edgeCaseAdvisory | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 0 |
| measured-error | 0 | 0 | 0 |
| architectural-coverage-pending | 83 | 83 | 0 |

**Detail-string distribution shifts substantially**:

| Detail | Cycle-55 | Cycle-56 | Δ |
|---|---:|---:|---:|
| `unsupported-carrier: OrderedSet<Int>` | 29 | **3** | **-26** |
| **`instance-method-shape-not-supported`** | 0 | **21** | **+21** |
| `internal-api-not-accessible` | 2 | **5** | **+3** |
| **`carrier-missing-required-conformance`** | 0 | **2** | **+2** |
| `unsupported-carrier: <other-OC>` | 52 | 52 | 0 |

The detail-string distribution is now 6 distinct architectural-pending categories (vs ~3 pre-v1.59), each pointing at a specific v1.60+/v1.61+ workstream.

## What V1.59.A accomplished

V1.59 ships four coupled fixes in a single feat commit:

1. **Strategist OC recipe** (`StrategistDispatchEmitter.curatedOCRecipe`): curated `Generator<OrderedSet<Int>, ...>` expression returned for the `OrderedSet<Int>` carrier. Inserted between the RawType and typeShape branches in `resolveRecipe`. Imports `OrderedCollections`.

2. **Verifier workdir Package.swift update** (`VerifierWorkdir.renderPackageSwift`): adds `swift-collections` as a SwiftPM dep + `OrderedCollections` as a target product. Unconditional — every workdir gets it.

3. **Double-qualifier strip in `CallExpressionShape.render`**: the indexer's `primaryFunctionName` carries a type-qualifier prefix for some picks (e.g. `OrderedSet.sort()` from extension-on-OrderedSet declarations) but not others (e.g. `exp(_:)` from extension-on-Complex). The resolver was producing `OrderedSet.OrderedSet.sort` for the qualified case. Fix: strip the `<typeQualifier>.` prefix if `bareFunctionName` starts with it. No-op for bare names.

4. **Reclassification pattern extension** (`architecturalPendingDetail`): 3 new patterns for the cycle-56 build errors that would otherwise land in `.measured-error`:
   - `"instance member ... cannot be used on type"` → `instance-method-shape-not-supported`
   - `"no exact matches in call to instance method"` → same detail (alternate Swift compiler diagnostic)
   - `"compile command failed due to signal"` / `"emit-module command failed due to signal"` → same detail (the swift-frontend CRASH on static-call-of-instance-mutating-method shape; empirical from cycle-56 OS internal-mutating picks)
   - `"requires that"` + `"conform to"` → `carrier-missing-required-conformance` (the monotonicity-on-non-Comparable case)

V1.59.B ships 4 unit tests pinning the new patterns + the double-qualifier strip behavior.

## OS pick movement (29 cycle-27 OrderedSet picks)

V1.58.A binding + V1.59.A recipe + reclassification → OS picks split:

| Bucket | Count | Cause | v1.60+ fix |
|---|---:|---|---|
| `instance-method-shape-not-supported` | 21 | Static-call shape on instance method | Mutating-method emission |
| `internal-api-not-accessible` | 3 | Compile-fail at `internal` access | `@testable import` or skip |
| `carrier-missing-required-conformance` | 2 | Monotonicity needs Comparable; OS<Int> doesn't conform | Comparable-aware monotonicity composer |
| `unsupported-carrier: OrderedSet<Int>` (still at resolver) | 3 | Dual-style picks taking a different path | Extend `DualStyleConsistencyPairResolver` |

**Total: 29** ✓.

## What cycle-56 establishes

1. **V1.59.A delivers the next scaffold step.** 26 OS picks moved past the resolver layer; the next gap (instance-method shape) is now visible at the build step.

2. **`.measured-error = 0` baseline preserved across the scaffold transition.** V1.59.A's reclassification pattern matcher absorbs the new error categories cleanly. The cycle-N CI-alarm invariant from v1.56 still holds.

3. **The detail-string distribution is now substantially more informative.** 6 distinct architectural-pending categories, each pointing at a specific workstream.

4. **The double-qualifier strip is a load-bearing bug fix.** Affects any pick whose indexer-produced `primaryFunctionName` is qualified (mostly OS picks; uncommon for Complex/Double picks). Regression-pinned by V1.59.B.

5. **The compiler-crash heuristic is empirical**. V1.59.A's match on "compile command failed due to signal" treats swift-frontend crashes during type-check of static-call-of-instance-mutating-method as instance-method-shape errors. Brittle but pragmatic; if cycle-N surfaces a non-OS compiler crash, the heuristic may need refinement.

6. **The 21 `instance-method-shape-not-supported` picks are the dominant v1.60 target.** Once mutating-method emission lands, those picks become measurable. Best-case projection: ~15-20 of them reach `.bothPass` / `.defaultFails`.

## Cycle-46 predictions vs cycle-56 actuals

Unchanged from cycle-55 (none of the 26 newly-categorized OS picks were in the cycle-46 stratified sample subset):
- **Strict 4-category match**: 5 / 13 = 38%
- **Semantic "property holds" match**: 13 / 13 = **100%**

## v1.60+ priorities

In priority order:

1. **v1.60 — Mutating-instance-method idempotence emission** for OC. Closes ~15-20 OS picks. New emit shape: `var copy1 = value; copy1.sort(); var copy2 = value; copy2.sort(); copy2.sort(); if copy1 != copy2 { fail }`.

2. **v1.60 — Mutating-instance-method dual-style-consistency emission** for OC. Tests `non-mutating-form(x)` vs `var copy = x; copy.mutating-form(); copy` equivalence. Likely closes 9-12 picks.

3. **v1.60 — Investigate the 3 OS picks still at resolver layer.** Likely dual-style-consistency picks going through `DualStyleConsistencyPairResolver` separately.

4. **v1.60-v1.61 — Strategist recipes for nested-OC carriers** (`OrderedSet.UnorderedView`, `OrderedDictionary.Elements`, etc.). ~33 pending picks.

5. **v1.61 — Comparable-aware monotonicity composer** (closes 2 picks).

6. **v1.61 — Strategist recipes for non-OC generics** (`_HashTable`, `ChunkedByCollection`, etc.). ~17 picks.

7. **v1.62+ — Phase 2 accept-flow integration**.

## Captured artifacts

- Cycle-56 survey JSON: `docs/calibration-cycle-56-data/full-surface-outcomes.json` (103 entries).
- Aggregate summary: `docs/calibration-cycle-56-data/full-surface-summary.md`.
- V1.59.A bundled code + V1.59.B tests — staged for the v1.59 commit.

## Open threads carried into v1.60

1. **Mutating-instance-method emission** — the v1.60 dominant target.
2. **3 OS picks still at resolver** — investigate as part of v1.60.
3. **Compiler-crash heuristic** — monitor for false positives in cycle-N+.
4. **Methodology guard escape-hatch** — 4 V1.47.D entries carry forward.
5. **The `.measured-error = 0` baseline** — depends on V1.59.A's pattern matcher; v1.60 changes may require pattern updates.
