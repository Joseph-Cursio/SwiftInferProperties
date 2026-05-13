# SwiftInferProperties — v1.61 Performance Baseline (Phase 2; biggest single-cycle gain)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-13. v1.61 ships V1.61.A curated-pair fix +
V1.61.B mutating-instance-method dual-style emission + cycle-58
measurement + standard closeout. **Biggest single-cycle measured-
execution gain in the project's history (+12 .bothPass).**

**Discover-pipeline impact: none.**

**Test-suite measurement (non-subprocess fast path):** **2414 tests**
in **~4 seconds**.

**Test count unchanged from v1.60** (2414). V1.61.A rewrites 6
existing V1.51.B tests with corrected expected values (testing the
new pair mappings) but doesn't add new tests. V1.61.B exercises
the new emit shape via the existing dual-style integration tests.

**Per-survey-run cost (V1.61 cycle-58 measurement):** **~12-15 min**
wall-clock for the 103-pick survey. +3-5 min over cycle-57's ~8-10
min — 12 additional picks running 100-trial property checks.

Projected v1.62+ cost: similar ~12-15 min baseline plus +1-2 min
when v1.62 commutativity/associativity instance-method picks reach
property check (4 picks × ~30s each).

**Per-verify-call cost (single suggestion)**: ~13-15s cold for
resolution-layer picks; ~30-40s for picks running the full property
check + edge pass.

**§13 budget compliance:** all v1.41-v1.60 measurements hold.

**Phase 2 cycle-58 measurement summary**: **33 / 103 = 32.0%
measured-execution** (`.bothPass` + `.defaultFails` + `.edgeCaseAdvisory`,
excluding error). **+12 vs cycle-57** — all 12 OS SetAlgebra dual-style
picks closed to `.bothPass` via V1.61.A's curated-pair fix + V1.61.B's
mutating-instance-method emission. Distribution: **19** `.bothPass`
+ 6 `.defaultFails` + 8 `.edgeCaseAdvisory` + 0 `.measured-error`
+ 70 `.architectural-coverage-pending`.

**Detail-string distribution shift (cycle-57 → cycle-58)**:
- `instance-method-shape-not-supported`: 16 → **4** (-12; the 12 OS
  dual-style picks closed)
- Other categories unchanged.

The remaining 4 `instance-method-shape-not-supported` are
commutativity/associativity instance methods (`index(_:offsetBy:)`,
`distance(from:to:)`). v1.62 target.

**Cycle-46 sample-subset agreement**: unchanged (OS picks aren't in
the cycle-46 stratified subset):
- Strict 4-category match: 5/13 = 38%
- Semantic "property holds" match: 13/13 = **100%**

The 13 OS `.bothPass` outcomes extend the measurable set substantially
beyond the cycle-46 sample; 100% per-pick mathematical correctness
on the SetAlgebra-equivalence contract.

v1.61 baseline is the **biggest-single-cycle-gain** reference point.
