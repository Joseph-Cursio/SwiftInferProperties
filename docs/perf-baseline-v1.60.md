# SwiftInferProperties — v1.60 Performance Baseline (Phase 2; first OC closure)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-13. v1.60 ships V1.60.A mutating-instance-method
idempotence emission + V1.60.B regression tests + cycle-57 measurement
+ standard closeout. **First non-Complex/Double measured-bothPass**
in the project's calibration history.

**Discover-pipeline impact: none.**

**Test-suite measurement (non-subprocess fast path):** **2414 tests**
in **~4 seconds** via `swift test --skip VerifyPipelineIntegrationTests`.

**Test count +2 vs v1.59** (2412 → 2414). V1.60.B adds 2 regression
tests pinning the new emit shape (`idempotenceOrderedSetMutatingShape`
positive guard + `idempotenceIntCarrierStaticShape` negative guard).

**Per-survey-run cost (V1.60 cycle-57 measurement):** **~8-10 min**
wall-clock for the 103-pick survey. Slight reduction from cycle-56's
~10-12 min — the 4 internal-mutating OS picks now fail quickly at
access-check (V1.56.A diagnostic) rather than crashing the compiler.

Projected v1.61+ cost: similar ~8-12 min baseline. When v1.61's
dual-style + commutativity instance-method emission lands, expect
+12 more picks running property check → +5-7 min wall-clock.

**Per-verify-call cost**: ~13-15s cold for resolution-layer picks;
~25-30s for picks running the property check.

**§13 budget compliance:** all v1.41-v1.59 measurements hold.

**Phase 2 cycle-57 measurement summary**: **21 / 103 = 20.4%
measured-execution** (`.bothPass` + `.defaultFails` + `.edgeCaseAdvisory`,
excluding error). +1 vs cycle-56 — the `OrderedSet.sort()` idempotence
pick reached `.bothPass` via V1.60.A's mutating-instance-method
emission. **First non-Complex/Double measurement in the project's
history.**

**4 picks reclassified** as side-effect of V1.60.A's new emit shape:
the internal-mutating OS picks (`_ensureUnique`, `_isUnique`,
`_regenerateHashTable`, `_regenerateExistingHashTable`) now fail with
canonical `"is inaccessible"` diagnostics instead of swift-frontend
crashes. V1.56.A's pattern recognizes them as
`internal-api-not-accessible` — more accurate categorization.

**.architectural-coverage-pending detail-string distribution**:
- `instance-method-shape-not-supported`: 21 → **16** (-5; 1 to .bothPass,
  4 to internal-api)
- `internal-api-not-accessible`: 5 → **9** (+4)
- other categories unchanged.

**`.measured-error = 0` baseline preserved.**

**Cycle-46 sample-subset agreement**: unchanged (OS picks aren't in
the cycle-46 stratified subset).
- Strict 4-category match: 5/13 = 38%
- Semantic "property holds" match: 13/13 = **100%**

v1.60 baseline is the **first-non-Complex/Double-measured** reference
point.
