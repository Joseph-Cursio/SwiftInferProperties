# SwiftInferProperties — v1.63 Performance Baseline (Phase 2)

**Captured**: 2026-05-13. v1.63 ships V1.63.A OD.Elements TypeShape scaffold + new reclassification pattern + cycle-60 measurement.

**Test-suite**: 2415 tests in ~5s (+1 from V1.63.A pattern test).

**Per-survey-run cost**: ~12-14 min wall-clock for the 103-pick survey.

**Cycle-60 summary**: 42/103 = 40.8% measured-execution (+1 vs cycle-59). 28 .bothPass + 6 .defaultFails + 8 .edgeCaseAdvisory + 0 .measured-error + 61 architectural-coverage-pending.

**OC-family coverage**: 22/44 = 50% measured.

**Diminishing returns pivot**: v1.62 closed 8 picks; v1.63 closed 1. The remaining nested-OC carriers are dominated by Comparable-blocked monotonicity + discover-layer false-positives. v1.64+ should pivot to Comparable-aware monotonicity or non-OC generics.

v1.63 baseline anchors the **diminishing-returns** reference point on the OC-scaffold ramp.
