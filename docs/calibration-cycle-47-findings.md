# v1.50 Calibration Cycle 47 — Findings (Phase 2 opening; first full-surface measurement)

Captured: 2026-05-12. swift-infer at v1.50 (post-V1.50.F). The forty-seventh execution of PRD §17.3's empirical-tuning loop and the **first full-coverage verify measurement** in this loop's history — extending verify-mode coverage from the cycle-27 stratified 32-pick sample (cycles 41–46) to the **full 109-pick surface** that v1.29 froze.

## Headline

**Full-surface verifiable-fraction: 0/109 = 0.0% (measured-execution).** First real-indexed verify run against the cycle-27 surface lands at 100% `architectural-coverage-pending` — every pick errors at carrier/pair/template resolution before the verify subprocess reaches `swift build`. The cycle-47 measurement is **methodologically reframing**, not a regression:

- **Cycle-46's 100% per-pick agreement** was on hand-crafted SemanticIndexEntry instances with v1.49-emitter-expected carrier strings (`"Complex<Double>"`, `"Int"`, etc.).
- **Cycle-47's 0% measured-verified** is the first time the verify pipeline has run against a *real-source-indexed* SemanticIndex. The indexer stores bare carrier names (`"Complex"` rather than `"Complex<Double>"`; `"OrderedSet"` without generic args; etc.); the v1.49 emitters expect qualified forms.

**This was the load-bearing measurement of v1.50** — and it landed exactly where the v1.50 plan's Risk #3 + #4 anticipated. The first full-surface measurement was always going to surface measurement-tooling gaps that cycle-46's synthetic-shape framing didn't capture. v1.50 establishes the measurement infrastructure (`verify --all-from-index`, the cycle27-surface fixture, the 5-category classification, the JSON survey artifact) and *honestly records* where measurement stands. v1.51+ closes the gap.

## Cycle-47 surface re-survey

| Template | Surface count | Per-template result | Failure-reason distribution |
|---|---:|---:|---|
| round-trip | 12 | 0/12 measured | 12 × `unsupported-carrier` (all are `Complex` or OC-internal carriers) |
| idempotence | 12 | 0/12 measured | 12 × `unsupported-carrier` (`Base.Index`, OC `_Bucket`/`_HashTable`, etc.) |
| commutativity | 17 | 0/17 measured | 17 × `unsupported-carrier` |
| associativity | 17 | 0/17 measured | 17 × `unsupported-carrier` |
| monotonicity | 29 | 0/29 measured | 27 × `unsupported-carrier` + 2 × `unsupported-template` (the residual v1.46-hardcoded-path miss) |
| dual-style-consistency | 22 | 0/22 measured | 22 × `unsupported-pair` (curated list is 3 entries; cycle-27 picks include `formIntersection`, `formUnion`, `formSymmetricDifference`, `subtract`, `merge`, etc.) |
| **Total** | **109** | **0/109 = 0.0%** | **85 unsupported-carrier + 22 unsupported-pair + 2 unsupported-template** |

See `docs/calibration-cycle-47-data/full-surface-summary.md` for the carrier-level breakdown and `full-surface-outcomes.json` for the per-pick JSON records.

## V1.50.B finding: misleading-template-error routing fix

During the first survey run, **49 picks were misclassified as `unsupported-template`** when their real failure reason was `unsupported-carrier`. Root cause: V1.47.F's strategist→v1.46 fallback fired indiscriminately for any `VerifyError` from the strategist path; the v1.46HardcodedBundle's 4-case switch then defaulted to `.unsupportedTemplate` for the v1.48-added templates (monotonicity / dual-style / idempotence-lifted).

The fix (V1.50.B): gate the fallback on `v1_46HardcodedTemplates = {round-trip, idempotence, commutativity, associativity}`. For v1.48 templates, the original strategist error surfaces instead of the misleading v1.46 default-case error.

Post-fix breakdown: 85 `unsupported-carrier` (real gap) + 22 `unsupported-pair` (curated-list gap) + 2 `unsupported-template` (genuine v1.46-path coverage gap for `monotonicity × Double` picks). The 2 residual unsupported-template picks are the only ones where the v1.46 hardcoded path is the actual blocker — v1.51 either adds v1.46 paths for monotonicity-on-Double (small) or routes those specifically to the strategist (smaller).

## Why this is a Phase 2 opening, not a Phase 1.5 regression

Three observations frame this honestly:

1. **Cycle-46 was synthetic-shape-class agreement.** Cycles 42–46's "100% per-pick agreement" was: "for a hand-crafted SemanticIndexEntry mirroring the cycle-27 pick's structural class, does the v1.49 integration test agree with the cycle-27 verdict?" That measurement is still load-bearing — it established that the *capability* exists. Cycle-47 measures something different: "for an entry produced by the real indexer against the real source, does the verify pipeline reach `swift build` and run the property check?" The answer is currently no, for 109/109 picks.

2. **The cycle-46 close-out claim of "100% architectural verifiable-fraction" was accurate at the capability level.** v1.49.B's `.memberwiseArbitrary`, v1.49.C's non-curated round-trip pair, v1.49.A's preamble channel — these architectural mechanisms exist and pass their unit + integration tests. What cycle-47 reveals is that wiring those mechanisms to *real indexer output* requires additional normalization work that v1.42–v1.49's tests didn't exercise. The capability is there; the measurement bridge is not.

3. **v1.50 was always meant to be the measurement-instrumentation cycle.** The v1.50 plan opened with "Pure measurement-instrumentation cycle, no new architecture" and explicitly flagged in §"Risks" that the first full-surface measurement could surface gaps the 32-pick sample missed. Cycle-47 is the realization of that risk — not an unexpected regression.

## Gap shape & v1.51 priorities

Three measurement-tooling gaps are now load-bearing:

1. **Bare-carrier-name vs qualified-carrier-name normalization** (the 85 `unsupported-carrier` picks). The indexer stores `"Complex"`, `"OrderedSet"`, `"_Bucket"`, etc.; the v1.49 emitter expects `"Complex<Double>"`, etc., for v1.46 hardcoded carriers, and a memberwise-derivable TypeShape for the rest. **Two candidate fixes**:
   - **(a)** Discover-side normalization: `IndexCommand.buildEntry` infers a canonical qualified form when the type has well-known generic-arg defaults (e.g., `Complex` → `Complex<Double>` for ComplexModule).
   - **(b)** Verify-side normalization: V1.47.F's router applies a bare-name → qualified-name canonicalization table before the v1_46HardcodedCarriers check.

   Path (b) is smaller; v1.51 should ship it as the minimum-viable normalization layer.

2. **Dual-style-consistency curated-pair list gap** (22 picks). V1.48.B's resolver has 3 entries (sorted/sort, reversed/reverse, shuffled/shuffle); cycle-27's OC dual-style picks use `formIntersection`/`formSymmetricDifference`/`formUnion`/`subtract`/`merge` non-mutating × mutating pairs. **Fix**: append ~6 entries to `DualStyleConsistencyPairResolver.curated` based on the cycle-27 surface evidence. Cycle-48 measurement quantifies the lift.

3. **Internal-typed carrier accessibility** (the OC `_HashTable`, `_Bucket`, `ViolationFormatter` picks — 12 total). Even with carrier-name normalization, the verify subprocess workdir uses `import OrderedCollections` which doesn't expose `_HashTable`. **Fix candidates**:
   - **(c)** `@testable import` for the workdir's package import — requires the workdir to be a test target rather than a source target, structural SwiftPM change.
   - **(d)** Synthesize the internal types from indexed TypeShape via V1.49.A preamble (each `_Bucket` pick gets a `struct _Bucket { ... }` preamble matching the indexed shape). Skips the real-package internal-access requirement entirely; verifies the heuristic match against a synthetic version of the same shape.

   Path (d) is more architectural but fits the V1.49.A preamble channel's intended use case. v1.51 or v1.52 candidate.

## Why no fix-now in v1.50

Three reasons the gaps stay as cycle-47 findings rather than fix-now:

1. **Each fix needs its own design pass.** Bare-name normalization could be discover-side or verify-side; dual-style curated-list expansion needs cycle-27-evidence-driven entry selection; internal-typed carrier access has two architectural alternatives. v1.50's scope was the measurement instrumentation, not the gap-closing.

2. **Cycle-47 is the load-bearing measurement of v1.50.** Closing the gaps in the same cycle would conflate "first measurement" with "first measurement after a fix" — making the cycle-47 → cycle-48 trajectory hard to interpret. v1.51 measures the gap-close with the cycle-47 baseline as the reference point.

3. **The framing matters more than the raw 0/109 number.** Recording the gap honestly — rather than scrambling to fix-now and reporting a partial close — is the methodologically correct posture. The v1.50 plan's Risk #3 ("First verify-vs-heuristic disagreement may surface") underestimated the scale of the gap; cycle-47 records that the disagreement isn't pick-level (verify says X vs heuristic says Y) but infrastructure-level (verify can't run on the real-indexed pick at all).

## v1.51+ roadmap

v1.51 priorities (per the gap shape above):

1. **Bare→qualified carrier normalization** at V1.47.F router (~30 LoC). Should close the 85 `unsupported-carrier` picks at least to the point where they hit `unsupported-pair` or `measured-error` rather than carrier-name-mismatch.
2. **`DualStyleConsistencyPairResolver.curated` expansion** — append 6+ cycle-27-evidenced pairs (~10 LoC). Closes the 22 `unsupported-pair` picks.
3. **`v1_46HardcodedTemplates` widening for monotonicity-on-Double** — small. Closes the 2 `unsupported-template` picks.
4. **Cycle-48 measurement** — re-run the full survey, record the percentage closed. Anchors the v1.51 trajectory.

v1.52+ priorities (deferred from cycle-47):

5. Internal-typed carrier handling — either `@testable` workdir or preamble-synthesized stubs.
6. Phase 2's accept-flow integration — wait for cycle-48+ to confirm a meaningful subset of the surface is `measured-*`.

## Captured artifacts

- Full-surface survey JSON: `docs/calibration-cycle-47-data/full-surface-outcomes.json` (sorted by identityHash; surveyVersion: 1; 109 entries).
- Aggregate summary: `docs/calibration-cycle-47-data/full-surface-summary.md` (template × failure-reason cross-tab + methodology note).
- V1.50.B routing fix: 49 picks reclassified from misleading `unsupported-template` to accurate `unsupported-carrier` (or kept as `unsupported-template` for the 2 genuine v1.46-path-coverage gaps).
- V1.50.A fixture: `fixtures/cycle27-surface/` SwiftPM workspace reproducing the cycle-27 109-surface via 4 package deps + a merge script.

No `triage-decisions.json` in `docs/calibration-cycle-47-data/` — cycle 47 didn't produce new per-pick verdicts (the cycle-27 corpus is unchanged at 21/29 = 72.4%). The measured-execution survey is the cycle-47 output.

## Open thread carried into v1.51

**The cycle-46 close-out narrative needs updating.** Cycle-46 claimed Phase 1.5 closed at "8/8 = 100% verifier-mode REJECT lift + 100% architectural verifiable-fraction" — both true at the capability level (cycles 42–46 confirmed agreement on hand-crafted SemanticIndexEntry instances). Cycle-47 establishes that **real-source-indexed verification has substantial measurement-tooling gaps** that the synthetic-shape framing didn't reveal. v1.51's findings should reconcile the two: capability-level claims (Phase 1.5) vs measurement-execution claims (Phase 2 ongoing). The honest framing is that Phase 1.5 closed the architecture and Phase 2 opens the measurement-tooling.
