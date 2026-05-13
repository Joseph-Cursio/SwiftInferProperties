# v1.56 Calibration Cycle 53 — Findings (.measured-error = 0; clean baseline; pending category now structured)

Captured: 2026-05-13. swift-infer at v1.56 (post-V1.56.A+B). Fifty-third execution of PRD §17.3's empirical-tuning loop.

## Headline

**`.measured-error = 0` for the first time** since the cycle-47 full-surface measurement began. The 2 cycle-52 `rescaledDivide` build failures shift `.measured-error → .architectural-coverage-pending` with detail `"internal-api-not-accessible"` — the function is declared `internal` in swift-numerics. Accessibility is a measurement-tooling gap, not a verifier-architecture gap.

| Outcome | Cycle-52 (v1.55) | Cycle-53 (v1.56) | Δ |
|---|---:|---:|---:|
| measured-bothPass | 6 | 6 | 0 |
| measured-edgeCaseAdvisory | 8 | 8 | 0 |
| measured-defaultFails | 6 | 6 | 0 |
| **measured-error** | **2** | **0** | **-2** |
| architectural-coverage-pending | 87 | **89** | **+2** |
| Measured-execution total | 20 | 20 | 0 |

**Total measured-execution unchanged at 20 / 109 = 18.3%**. The `.measured-error` reclassification doesn't change the headline; it cleans the categorization.

## What V1.56.A accomplished

Cycle-52 left 2 picks in `.measured-error` (both `Complex.rescaledDivide(_:_:)` × commutativity + associativity). Investigation: the function is declared `internal` in `Sources/ComplexModule/Complex+AlgebraicField.swift:48`. The build fails with:

```
error: 'rescaledDivide' is inaccessible due to 'internal' protection level
```

V1.56.A extracts a testable helper `architecturalPendingDetail(buildStdout:buildStderr:)` that pattern-matches the `"is inaccessible due to '"` substring on both streams and returns `"internal-api-not-accessible"` as the detail. The surveyRecord path reclassifies these picks to `.architectural-coverage-pending` instead of `.measured-error`.

**Why both streams**: cycle-53's first run with stderr-only check produced 0 transitions — the V1.56.A code didn't fire. Debugging via direct `swift build` invocation showed compiler diagnostics land on **stdout** when swift build runs as a subprocess (not stderr, which carries SwiftPM-level errors). Both-stream check makes the pattern robust.

V1.56.B's 6 unit tests pin the behavior:
- Matches `internal` / `private` / `fileprivate`
- Matches on either stream (stdout-only, stderr-only, both)
- Returns nil for unrelated build errors
- Returns nil for empty input

Test count: 2396 → 2402 (+6).

## The reclassified picks

| Hash prefix | Template | Function | Cycle-52 outcome | Cycle-53 outcome | Detail |
|---|---|---|---|---|---|
| 0xD6C6 | commutativity | `rescaledDivide(_:_:)` | `.measured-error` (build-failed: exit=1) | `.architectural-coverage-pending` | `internal-api-not-accessible` |
| 0xE724 | associativity | `rescaledDivide(_:_:)` | same | same | same |

The reclassification is precise — these picks were always tooling-gaps, never real verifier failures. Cycle-53 attributes them correctly.

## Why this matters: `.measured-error = 0` as a CI alarm

Pre-V1.56, the `.measured-error` category was a catch-all for any unexpected build/runtime failure plus the 2 internal-API cases. Cycle-by-cycle, it dropped: 22 (cycle-49) → 10 (cycle-50) → 2 (cycle-51) → 2 (cycle-52) → **0 (cycle-53)**.

With `.measured-error = 0` as the baseline, any future cycle producing `.measured-error > 0` is an alarm — it indicates an unexpected build/runtime failure not caught by the existing reclassification, motivating immediate investigation. A v1.57+ CI gate could enforce this directly.

The `.architectural-coverage-pending` category is also more informative now. Pre-V1.56 it was 87 picks with detail strings starting with `"unsupported-carrier:"`. Post-V1.56 it has 2 entries with the qualitatively different `"internal-api-not-accessible"` — the dominant gap category structure is now visible at a glance.

## Cycle-46 predictions vs cycle-53 actuals

Unchanged from cycle-52:
- **Strict 4-category match**: 5 / 13 = 38%
- **Semantic "property holds" match**: 13 / 13 = **100%**

V1.56.A doesn't change either rate — the 2 reclassified picks weren't in the 32-pick stratified sample (cycle-46 didn't predict outcomes for them).

## What cycle-53 establishes

1. **V1.56.A closes the cycle-52 `.measured-error` residual as designed.** All 109 cycle-27 picks classify correctly: 20 with real measurement (`.bothPass` / `.defaultFails` / `.edgeCaseAdvisory`), 89 with structured tooling-gap detail strings (`unsupported-carrier:X` / `internal-api-not-accessible`).

2. **The `.measured-error = 0` baseline is now a CI alarm.** Any future cycle producing measured-error > 0 indicates an unexpected build/runtime failure, motivating immediate investigation.

3. **`.architectural-coverage-pending` category structure makes priorities visible**:
   - 87 picks: `unsupported-carrier:<Type>` — OC + Algo generic-instantiation gap (v1.57+)
   - 2 picks: `internal-api-not-accessible` — access-level gap (deferred; minor)
   - 3 picks: `unsupported-carrier:(none)` — typeName field null in index, likely indexer bug (v1.57+)

4. **The pattern-matching helper is extension-ready**. v1.57+ can add more reclassification patterns (e.g. `@_spi`, internal-typed parameters) by extending `architecturalPendingDetail`. V1.56.B's tests pin the current behavior; future additions stay backward-compatible.

5. **Methodology lesson: stream assumptions deserve unit-test coverage.** The cycle-53 first-run bug (stderr-only check missing the stdout-borne diagnostic) cost ~10 min of debugging. A unit test that exercises both streams would have caught the bug pre-merge. V1.56.B's tests now cover this.

## v1.57+ priorities

In priority order:

1. **v1.57-v1.58 — TypeShape-driven generic instantiation** for OC + Algo types. Dominant remaining category (87 `unsupported-carrier` picks). Multi-cycle scope.

2. **v1.57 — Instance-method emission** for OC + Algo wrappers. Closes a subset of the OC picks once TypeShape work lands.

3. **v1.57 — Methodology guard for binding tables**. Fixture-level check that every `GenericBindingResolver.curatedBindings` key matches at least one indexer-produced carrier name.

4. **v1.57 — Investigate the 3 `(none)`-typeName picks**. Likely indexer-side bug; small scope.

5. **v1.58+ — Phase 2 accept-flow integration**. The 20-pick measurable sample + clean `.measured-error = 0` baseline make this viable.

6. **v1.58+ — Optional indexer-time non-public filter**. Drop the 2 internal-API picks from the index entirely; cycle-27 fixture reduces from 109 to 107. Decision deferred — preserves v1.29-frozen baseline by default.

## Captured artifacts

- Cycle-53 survey JSON: `docs/calibration-cycle-53-data/full-surface-outcomes.json` (sorted by identityHash; surveyVersion: 1; 109 entries).
- Aggregate summary: `docs/calibration-cycle-53-data/full-surface-summary.md` (template × outcome cross-tab + `.architectural-coverage-pending` detail-string breakdown + cycle-50/51/52 trajectory + methodology).
- V1.56.A + V1.56.B code + tests — committed `b522ee3`.

## Open threads carried into v1.57

1. **TypeShape-driven OC + Algo instantiation** — load-bearing for the next 60+ picks.
2. **Instance-method emission** — needed alongside TypeShape work for OC wrappers.
3. **3 `(none)`-typeName picks** — likely indexer bug; small fix.
4. **Methodology guard for binding tables** — prevents V1.51.B + V1.52.C latent-key recurrence.
5. **`@_spi` / `@_implementationOnly` access patterns** — v1.57+ may extend V1.56.A's pattern matcher.
6. **Per-function default-pass domain extensions** (v1.55 carry-forward) — refine generator ranges as cycle-N evidence reveals additional boundaries.
