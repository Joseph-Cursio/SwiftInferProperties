# SwiftInferProperties — v1.62 Performance Baseline (Phase 2)

PRD v1.0 §13 mandates that "a 25% regression in any number fails the build."

**Captured:** 2026-05-13. v1.62 ships V1.62.A UnorderedView TypeShape scaffold (3-edit pattern: binding + recipe + gate) + cycle-59 measurement.

**Test-suite measurement (non-subprocess fast path):** **2414 tests** in **~4 seconds**. Test count unchanged from v1.61.

**Per-survey-run cost (cycle-59):** **~14 min** wall-clock. +1-2 min over cycle-58's ~12-15 (8 additional picks running full property-check + edge pass).

**Phase 2 cycle-59 measurement summary**: **41 / 103 = 39.8% measured-execution** (+8 vs cycle-58). All 8 OS.UnorderedView dual-style picks closed via V1.62.A. Distribution: 27 .bothPass + 6 .defaultFails + 8 .edgeCaseAdvisory + 0 .measured-error + 62 .architectural-coverage-pending.

**OS-family coverage**: 21/37 = 57% measured across OS<Int> + OS<Int>.UnorderedView.

**`.measured-error = 0` baseline preserved.**

**Cycle-46 sample-subset agreement** unchanged.

v1.62 baseline anchors the **nested-OC scaffold reusability** reference point.
