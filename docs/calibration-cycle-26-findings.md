# v1.29 Calibration Cycle 26 — Findings

Captured: 2026-05-11. swift-infer at v1.29 development tip (`e4f5290`). The twenty-sixth execution of PRD §17.3's empirical-tuning loop and the **fifth consecutive measurement-driven mechanism cycle** (cycles 18 + 19 + 21 + 22 + 24 + 26 = v1.21 + v1.22 + v1.24 + v1.25 + v1.27 + v1.29).

## Headline

**Three workstreams, -4 surface closures, plan-vs-actual exact match.** Surface 113 → **109** (-3.5%). Cumulative reduction **-90.66%** vs cycle-1's 1167-baseline (new low; prior: -90.32% at cycle 24). Three mechanism classes are now empty on the cycle-1..14 corpora (inverse-pair, identity-element, composition-lifted).

| Workstream | Mechanism class | Projected | Actual | Detail |
|---|---|---:|---:|---|
| V1.29.A | inverse-pair asymmetric full-veto (ext. class 6) | -2 OC | -2 OC | bucket(after:|before:) × firstOccupiedBucketInChain |
| V1.29.B | identity-element algebraic-family veto (new class 15) | -1 CM | -1 CM | rescaledDivide × Complex.zero |
| V1.29.C | composition-lifted monotone-bounded veto (promote class 11) | -1 OC | -1 OC | _HashTable.BucketIterator.advance(until:) |
| **Total** | | **-4** | **-4** | |

## Surface composition post-v1.29

| Template | Algo | OC | CM | PLK | Total | Δ vs v1.27 |
|---|---:|---:|---:|---:|---:|---:|
| round-trip | 0 | 4 | 8 | 0 | **12** | 0 |
| idempotence (non-lifted) | 3 | 1 | 0 | 1 | **5** | 0 |
| idempotence-lifted | 0 | 7 | 0 | 0 | **7** | 0 |
| monotonicity | 3 | 20 | 0 | 6 | **29** | 0 |
| commutativity | 1 | 10 | 6 | 0 | **17** | 0 |
| associativity | 1 | 10 | 6 | 0 | **17** | 0 |
| inverse-pair | 0 | 0 | 0 | 0 | **0** | **-2** |
| identity-element | 0 | 0 | 0 | 0 | **0** | **-1** |
| dual-style-consistency | 0 | 22 | 0 | 0 | **22** | 0 |
| composition (lifted) | 0 | 0 | 0 | 0 | **0** | **-1** |
| **Total** | **8** | **74** | **20** | **7** | **109** | **-4** |

**Three mechanism classes are now empty** (inverse-pair, identity-element, composition-lifted) — first time in the loop's history. The remaining 109-surface is dominated by:
- dual-style-consistency (22 OC; 4-cycle 100% rate-stability anchor)
- monotonicity (29; high accept on math + cap)
- commutativity / associativity (17 each; mixed; CM `_relaxedAdd/_relaxedMul` accept, OC `index(_:offsetBy:)` reject)
- round-trip (12; canonical math + 1 OC pack/unpack pair)
- idempotence-lifted (7 OC; sorts + internal helpers)
- idempotence non-lifted (5; Algo chunk methods + 2 unknowns)

## Aggregate-rate projection for cycle 27

Cycle-25 measured 21 Accept / 12 Reject / 3 Unknown on the 113-surface. The 4 picks v1.29 closes were all REJECT in cycle-25:
- #28 + #29 (inverse-pair) — both REJECT
- #30 (identity-element) — REJECT
- #36 (composition-lifted) — REJECT

Replacing 4 REJECT picks with 4 absent picks shifts the cycle-25 numbers:
- Accept = 21 (unchanged)
- Reject = 12 - 4 = 8
- **Projected acceptance rate = 21 / (21 + 8) = 72.4%**

If cycle-27 (v1.30) measurement confirms this projection, **§19 ≥70% target is reached on the v1.29 surface**. Sample-noise band ±5pp on n≈33-36 means the projected 72.4% could measure anywhere in 67-78%; the 4 picks are canonical-reject patterns closed at-source-time, so the projection is mechanism-precision-driven (high confidence).

## Mechanism-class effectiveness post-v1.29

- **V1.27.B + V1.29.A inverse-pair name-prefix gates**: 0 surviving picks on cycle-1..14 corpora. Both symmetric (V1.27.B) and asymmetric (V1.29.A) direction-pair noise classes closed.
- **V1.29.B algebraic-family mismatch veto**: 0 surviving identity-element picks. Also closed the legacy V1.5.2 cross-product test cases (zero × *, one × +) at signal-construction time.
- **V1.21.B → V1.29.C monotone-bounded veto promotion**: 0 surviving composition-lifted picks. 4-cycle stable reject pattern (cycles 17/20/23/25) confirmed the promotion.
- **V1.18.C dual-style**: 22 picks; 4-cycle 100% rate-stability continues.
- **V1.21.A + V1.22.A + V1.24.B + V1.27.A IteratorProtocol/mutator vetoes**: 0 picks closed at-source-time on the cycle-1..14 corpora; infrastructure ready for future corpora.

## Mechanism-class taxonomy update

The 14-class taxonomy (V1.22.C class 14 = recall-positive fixed-point-name) gains **class 15: algebraic-family-mismatch veto on identity-element**. The first cross-template signal pattern combining curated-constant naming with operator-algebraic-family compatibility.

Taxonomy: **14 → 15** classes.

## Cycle-27 priority list

1. **v1.30 = cycle 27 empirical-only re-measurement** — seventh measurement point. Validates the 72.4% projection. Potentially the cycle that reaches §19 ≥70% target after 27 calibration cycles.
2. **Architectural shift to test-execution evidence** (PRD §20 v1.1+) — if cycle-27 confirms ≥70%, the name-based heuristic asymptote has been reached and further gains require execution evidence rather than mechanism cycles.
3. **FP approximate-equality template arm** (13-cycle carry-forward; correctness-emission work) — doesn't shift the rate but unblocks production CM round-trip emission.
4. **Cycle-26 finding (if cycle-27 reveals new reject classes)** — currently no surviving picks in three mechanism classes (inverse-pair, identity-element, composition-lifted); the residual 109-surface targets are dual-style/monotonicity/round-trip canonical-accepts + idempotence non-lifted unknowns + commutativity/associativity OC index-ops.

## Conclusion

Cycle 26 produced the **fifth consecutive measurement-driven mechanism release** with exact plan-vs-actual match (-4 / -4). Three mechanism classes are now empty on the cycle-1..14 corpora, leaving the 109-surface dominated by high-precision canonical-accept patterns plus a residual ~5-pick reject pool (commutativity/associativity OC index-ops + idempotence non-lifted Algo chunk methods).

The cycle-25 plateau-confirmation result motivated this targeted mechanism cycle; cycle-27 will determine whether the v1.29 closures lift the aggregate above the §19 ≥70% threshold. The projected 72.4% has a sample-noise band of 67-78%, with the mechanism-precision-driven projection at high confidence.

If cycle-27 confirms ≥70%, **the empirical-tuning loop has achieved its design intent within 27 calibration cycles** — a milestone that would close the post-v1.0 calibration era and pivot the project to PRD §20 v1.1+ work (SemanticIndex, IDE integration, `swift-infer apply`, and the test-execution evidence path).
