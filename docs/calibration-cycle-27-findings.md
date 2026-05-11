# v1.30 Calibration Cycle 27 — Findings

Captured: 2026-05-11. swift-infer at v1.29.0 (`4eebd43`); v1.30 binary-equivalent. The twenty-seventh execution of PRD §17.3's empirical-tuning loop and the **seventh empirical-only cycle** (after cycles 6 + 14 + 17 + 20 + 23 + 25).

## Headline

**21/29 = 72.4% Possible-tier acceptance rate — §19 ≥70% TARGET REACHED.** A +8.8pp shift from cycle-25's 63.6% — **outcome A**. The empirical-tuning loop has **achieved its design intent within 27 calibration cycles**.

| Metric | C6 | C14 | C17 | C20 | C23 | C25 | **C27** | Δ vs C25 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Surface | 349 | 229 | 335 | 152 | 114 | 113 | **109** | −4 (−3.5%) |
| Sample | 50 | 50 | 46 | 46 | 40 | 36 | **32** | −4 |
| Accept | 12 | 16 | 23 | 21 | 25 | 21 | **21** | 0 |
| Reject | 33 | 30 | 21 | 22 | 12 | 12 | **8** | **−4** |
| Unknown | 5 | 4 | 2 | 3 | 3 | 3 | **3** | 0 |
| **Rate** | 26.7% | 34.8% | 52.3% | 48.8% | 67.6% | 63.6% | **72.4%** | **+8.8pp** |

**Seven-point trajectory:** 26.7% → 34.8% → 52.3% → 48.8% → 67.6% → 63.6% → **72.4%**. The cycle-25 plateau confirmation (-4.0pp settle from cycle-23) is followed by a targeted mechanism cycle (v1.29 / cycle 26 / -4 closures with exact plan-vs-actual match) that lifts the aggregate above the §19 threshold.

## Projection-vs-measurement: exact match

The cycle-26 findings projected 72.4% on the v1.29-trimmed surface (cycle-25's 21 Accept / 12 Reject minus 4 REJECT closures = 21 Accept / 8 Reject). Cycle-27 measured **exactly 72.4%**.

This is not coincidence — the verdict on each cycle-27 pick is rationally grounded in canonical patterns:
- Math inverse pairs (exp/log, sinh/asinh, tanh/atanh, tan/atan) → Accept by construction.
- Sorted-collection idempotence (sort × 3, regen/isUnique/ensureUnique × 3) → Accept.
- FP commutativity/associativity on `_relaxedMul` → Accept.
- Form/non-form dual-style on UnorderedView pairs → Accept.
- Algo chunk-offset idempotence → Reject by semantic incoherence.
- Cross-marker round-trip + binomial/distance commutativity/associativity → Reject by type-pattern.

Per-template rates are stable across cycles 25 + 27. The aggregate shift is entirely explained by surface composition. The projection model — "mechanism-precision-driven, replace REJECT with absent" — predicts the measurement to the percentage point.

## Per-template results

| Template | C27 | C25 | C20 | Trajectory |
|---|---:|---:|---:|---|
| round-trip | 5/6 = **83.3%** | 83.3% | 60.0% | 3-cycle stable high |
| idempotence (non-lifted) | 0/3 = 0.0% | 0.0% | 0.0% | 7-cycle 0% continues |
| idempotence-lifted | 6/6 = **100.0%** | 100.0% | 50.0% | 3-cycle stable 100% (post-cycle-22 surviving pool is OC-sort/internal-helper-dominated) |
| monotonicity | 3/3 = **100.0%** | 100.0% | 75.0% | 3-cycle stable 100% |
| commutativity | 1/3 = 33.3% | 33.3% | 33.3% | 4-cycle stable 33% |
| associativity | 1/3 = 33.3% | 33.3% | 66.7% | sample-shift back to C25 rate |
| inverse-pair | empty | 0.0% | 0.0% | mechanism class empty post-V1.29.A |
| identity-element | empty | 0.0% | 0.0% | mechanism class empty post-V1.29.B |
| dual-style-consistency | 5/5 = **100.0%** | 100.0% | 100.0% | **5-cycle stable 100%** (cycles 17 + 20 + 23 + 25 + 27) |
| composition-lifted | empty | 0.0% | 0.0% | mechanism class empty post-V1.29.C |

**Three mechanism classes are empty** on the v1.29 surface (inverse-pair, identity-element, composition-lifted); none of those classes' picks remain to reject-anchor the aggregate.

## Mechanism-class effectiveness at cycle 27

- **V1.18.C dual-style: 5/5 = 100%**. **5-cycle rate-stability** across cycles 17 + 20 + 23 + 25 + 27 — the largest mechanism-class precision contribution in the loop's history.
- **V1.21.C math-forward**: cycle-27 4 CM canonical anchors all preserve at ACCEPT. Combined with cycle-25's 4 CM anchors at ACCEPT, 8 of 8 sampled math-forward round-trips ACCEPT across the two most recent measurement points.
- **V1.27.B + V1.29.A inverse-pair gates**: 0 surviving picks; the cycle-1..14 corpora are fully closed against direction-pair noise.
- **V1.29.B identity-element algebraic-family veto**: 0 surviving picks; closes the cross-product noise class.
- **V1.21.B → V1.29.C monotone-bounded promotion**: 0 surviving picks; the 4-cycle stable-reject pattern is closed.
- **V1.21.A + V1.22.A + V1.24.B + V1.27.A IteratorProtocol/mutator vetoes**: 0 cycle-27 sample picks; closed at-source-time.
- **V1.22.C class 14 fixed-point-name**: still 0 sample picks (no surfacing on cycle-1..14 corpora; 11-cycle infrastructure-without-evidence).

## Mechanism-class taxonomy

15 mechanism classes shipped through cycle 27 (v1.4 - v1.29 + class 15 = V1.29.B algebraic-family-mismatch veto). Classes 6 + 7 + 11 received V1.29.A/B/C extensions; classes 12 + 13 + 14 unchanged. Classes 4 + 5 + 8 + 9 + 10 quiescent.

## §19 target achievement

PRD §19 set the acceptance-rate target at ≥70%. Cycle-27 measures **72.4%**, which is:
- **+2.4pp above the §19 70% threshold.**
- The first measurement above 70% in the loop's seven-measurement history.
- Mechanism-precision-driven (per-template rates stable; only surface composition changed).

The empirical-tuning loop has achieved its post-v1.0 design intent. The remaining residual reject pool (~8 picks on the 109-surface) comprises:
- 3 Algo idempotence chunk-method false-positives (V1.22.D's stride-style label demoter doesn't fire on idempotence template).
- ~6 OC commutativity/associativity `index(_:offsetBy:)` + `distance(from:to:)` cross-marker noise.
- Lone CM `-(z:w:)` / `/(z:w:)` / `rescaledDivide` / `pow` commutativity/associativity rejects.

These are name/type-pattern false-positives that name-based heuristics structurally cannot close further — the residual ~7-8 REJECT picks represent the precision asymptote of the name-based architecture.

## Cycle-28 priority list

With §19 reached, the loop's next priorities shift from precision-tuning to design-completion:

1. **Architectural pivot to PRD §20 v1.1+** — the test-execution evidence path (raised by the user earlier in the loop) is now the highest-leverage gain available. Direct property-test execution converts Unknown/Reject categories into hard verdicts and unblocks the residual ~7-8 name-based-asymptote picks.
2. **FP approximate-equality template arm** (13-cycle carry-forward; cycle-14 priority #4). Correctness-emission work — doesn't shift the rate (CM round-trips already accept) but unblocks production CM round-trip property-test emission.
3. **`swift-infer apply`** (PRD §20.6) — the "auto-apply accepted suggestions" CLI surface.
4. **SemanticIndex integration** (PRD §20.4) — replaces the current source-code walk with the SwiftSyntax semantic index.
5. **Domain Template Packs** (PRD §20.5) — extension surface for project-specific algebraic-property templates.

## Conclusion

Cycle 27 produced the **seventh empirical measurement point** and the **first §19-target-reached measurement** in the loop's history. The seven-point trajectory 26.7% → 34.8% → 52.3% → 48.8% → 67.6% → 63.6% → **72.4%** validates the cycle-26 mechanism-precision projection and confirms that name-based heuristic calibration has achieved the PRD §19 design intent within 27 cycles.

The cycle-23 → cycle-25 → cycle-27 trajectory (67.6% → 63.6% → 72.4%) follows the predicted pattern: cycle-23 was the upper edge of a 60-67% plateau; cycle-25 the middle; v1.29's targeted -4 closures shifted the aggregate cleanly above 70% to 72.4%, exactly as projected.

**The empirical-tuning loop has achieved its design intent.** The next high-leverage moves are PRD §20 v1.1+ work — particularly the test-execution evidence architectural shift the user raised earlier in the loop, which is now both technically motivated (name-based asymptote reached) and empirically supported (§19 target met).
