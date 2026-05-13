# v1.57 Calibration Cycle 54 — Findings (baseline shift 109 → 103; .architectural-coverage-pending category cleaner)

Captured: 2026-05-13. swift-infer at v1.57 (post-V1.57.A + cycle-27 fixture rebuild). Fifty-fourth execution of PRD §17.3's empirical-tuning loop.

## Headline

**Cycle-27 fixture baseline shifts from 109 to 103 picks.** V1.57.A's scanner-level filter drops 6 file-private declarations from SwiftPropertyLaws that were always noise in the v1.29-era baseline. Total measured-execution count unchanged at 20; rate goes 18.3% → 19.4% (denominator-driven).

| Outcome | Cycle-53 (109) | Cycle-54 (103) | Δ |
|---|---:|---:|---:|
| measured-bothPass | 6 | 6 | 0 |
| measured-edgeCaseAdvisory | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 0 |
| measured-error | 0 | 0 | 0 |
| **architectural-coverage-pending** | **89** | **83** | **-6** |
| **Total** | **109** | **103** | **-6** |

**Methodologically clean baseline correction.** The 6 dropped picks were file-private (`private` modifier) — not reachable cross-module, never property-testable. The v1.29-era FunctionScannerVisitor over-collected them; V1.57.A's filter is the right architectural fix.

## What V1.57.A accomplished

V1.57.A — `private`/`fileprivate` filter in FunctionScannerVisitor:

```swift
let modifiers = node.modifiers.map { $0.name.text }
if modifiers.contains("private") || modifiers.contains("fileprivate") {
    return .skipChildren
}
```

Applied retroactively to the cycle-27 fixture via per-checkout reindex. 6 picks dropped, all from SwiftPropertyLaws's PropertyLawKit target:

| Hash prefix | Function | Modifier | File |
|---|---|---|---|
| 0x9352 | `walkCap(for:)` | `private` | Public/BidirectionalCollectionLaws.swift:237 |
| 0xAD05 | `iterationCap(for:)` | `private` | Public/IteratorProtocolLaws.swift:97 |
| 0xBA0E | `snapshot(_:)` | `private` | Public/MutableCollectionLaws.swift:181 |
| 0xD694 | `headerLine(_:)` | `private static` | Internal/ViolationFormatter.swift:27 |
| 0x840A | `nearMissLines(_:)` | `private static` | Internal/ViolationFormatter.swift:58 |
| 0xF67C | `formatBuckets(_:)` | `private static` | Internal/ViolationFormatter.swift:81 |

The 3 free-function helpers were the cycle-53 `(none)`-typeName picks. The 3 `private static` ViolationFormatter members were inside an `internal enum`; their explicit `private` modifier overrode the enclosing access level — V1.57.A's filter correctly catches them.

**Why not also filter `internal`**: Swift's default access level is `internal`. Most user code carries no explicit modifier; filtering internal would be over-aggressive (would drop most picks). Internal-but-explicit symbols (cycle-52's `rescaledDivide`) stay handled at verify time via V1.56.A's pattern matcher.

**Why not filter `_`-prefix names**: that's a convention, not an access modifier. swift-numerics's `_relaxedAdd`/`_relaxedMul` are `public _`-prefixed (kit-internal-by-convention but accessible). Cycle-50/52 confirmed they reach the property check and produce valid `.bothPass` outcomes. Filtering by prefix would drop them — not what we want.

## What cycle-54 establishes

1. **The baseline shift is methodologically clean.** The 6 dropped picks violate cross-module visibility constraints; they couldn't have produced valid measurements regardless of the verifier's other capabilities. v1.57's baseline reflects what's actually verifiable in the cycle-27 corpus.

2. **The `.architectural-coverage-pending` category structure is now cleaner**. The `(none)`-typeName detail (3 picks in cycle-53) is eliminated entirely. The `ViolationFormatter` count dropped 4 → 1 (only the `public static func format(_:)` remains). The remaining 83 pending picks are dominated by OC + Algo generic-instantiation gaps (83 / 83 = 100%).

3. **The `.measured-error = 0` baseline established in v1.56 holds.** V1.57.A doesn't introduce any error-category changes.

4. **Cross-cycle comparison after v1.57 normalizes against the 103 baseline.** Cycles 47-53 reference 109; cycles 54+ reference 103. Both are valid baselines for their respective measurement periods.

5. **The unit test added with V1.57.A pins the scanner behavior**. Synthetic source with 5 functions (public/private/fileprivate/internal/default) → 3 captured. Future cycle that reverts the filter would fail this test.

6. **A future `swift-infer index` run on a user's codebase will produce a smaller index than pre-V1.57.** Documented in the V1.57.A code comment + the v1.57.0 CLAUDE.md entry.

## Cycle-46 predictions vs cycle-54 actuals

Unchanged from cycle-53:
- **Strict 4-category match**: 5 / 13 = 38%
- **Semantic "property holds" match**: 13 / 13 = **100%**

V1.57.A doesn't change the 32-pick sample (none of the dropped picks were in the cycle-46 stratified subset).

## v1.58+ priorities (per cycle-54 evidence)

In priority order:

1. **v1.58-v1.59 — TypeShape-driven generic instantiation** for OC + Algo types. Dominant remaining category (83 picks; 83/83 = 100% of pending). Multi-cycle scope.

2. **v1.58 — Instance-method emission** for OC + Algo wrappers. The current emitters assume free or static functions; OC picks are mostly instance methods on the wrapper.

3. **v1.58 — Methodology guard for binding tables**. Fixture-level check that every `GenericBindingResolver.curatedBindings` key matches at least one indexer-produced carrier name (or member-type-name in some indexed TypeShape).

4. **v1.59+ — Phase 2 accept-flow integration**. The 20-pick measurable sample + `.measured-error = 0` + 103-pick coherent index make accept-flow viable.

5. **v1.59+ — Optional `internal`-modifier filter** — would require careful audit (Swift default is internal; over-aggressive without no-modifier exception). v1.59+ may revisit.

## Captured artifacts

- Cycle-54 survey JSON: `docs/calibration-cycle-54-data/full-surface-outcomes.json` (sorted by identityHash; surveyVersion: 1; **103 entries**).
- Aggregate summary: `docs/calibration-cycle-54-data/full-surface-summary.md` (template × outcome cross-tab + per-checkout drop breakdown + .architectural-coverage-pending detail-string distribution).
- V1.57.A code + unit test — committed `58a3cd5`.
- Cycle-27 fixture rebuild + build-index.sh doc — committed `709412b`.

## Open threads carried into v1.58

1. **TypeShape-driven OC + Algo instantiation** — load-bearing for the next 60+ picks.
2. **Instance-method emission** — needed alongside TypeShape work.
3. **Methodology guard for binding tables** — prevents V1.51.B + V1.52.C latent-key recurrence.
4. **`@_spi` / `@_implementationOnly` access patterns** — may need separate handling.
5. **The 1 remaining `ViolationFormatter` pick** — `format(_:)` is public; if cycle-N reaches it via property-test infrastructure, will be a measurable outcome.
6. **Per-function default-pass domain extensions** (v1.55 carry-forward) — refine generator ranges as cycle-N evidence motivates.
