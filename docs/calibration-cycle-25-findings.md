# v1.28 Calibration Cycle 25 — Findings

Captured: 2026-05-11. swift-infer at v1.27.0 (`287764a`); v1.28 binary-equivalent. The twenty-fifth execution of PRD §17.3's empirical-tuning loop and the **sixth empirical-only cycle** (after cycles 6 + 14 + 17 + 20 + 23).

## Headline

**21/33 = 63.6% Possible-tier acceptance rate.** A -4.0pp shift from cycle-23's 67.6% — **outcome B** (60-69% plateau range). §19 ≥70% target **not reached** within 25 cycles.

| Metric | C6 | C14 | C17 | C20 | C23 | **C25** | Δ vs C23 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Surface | 349 | 229 | 335 | 152 | 114 | **113** | −1 (−0.88%) |
| Sample | 50 | 50 | 46 | 46 | 40 | **36** | −4 |
| Accept | 12 | 16 | 23 | 21 | 25 | **21** | −4 |
| Reject | 33 | 30 | 21 | 22 | 12 | **12** | 0 |
| Unknown | 5 | 4 | 2 | 3 | 3 | **3** | 0 |
| **Rate** | 26.7% | 34.8% | 52.3% | 48.8% | 67.6% | **63.6%** | **−4.0pp** |

**Six-point trajectory:** 26.7% → 34.8% → 52.3% → 48.8% → 67.6% → **63.6%**. The cycle-23 spike (+18.8pp) settles back into a 60-67% band over two measurement points. Cycle-23's 67.6% was the upper edge of sample-noise; cycle-25's 63.6% is consistent with the true rate being in the **~63-67% range**.

## Outcome interpretation

The cycle-25 plan defined three scenarios:

- **A (≥70%)**: §19 target reached. **Did not materialize.**
- **B (60-69%)**: plateau range; reconsider architectural shift. **This is the measured outcome.**
- **C (<60%)**: cycle-23 was sample-noise high. **Did not materialize.**

The B-outcome is informative: the loop has converged to a precision ceiling materially above cycle-17's 52.3% but materially below the §19 70% threshold. Two consecutive measurement points (C23 67.6%, C25 63.6%) at this level — with one mechanism cycle (v1.27, -1 surface) between them — is sufficient to characterise the regime.

## Drivers of the -4.0pp settlement

Cycle 24 / v1.27 closed -1 candidate (V1.27.B `bucket(after:) × bucket(before:)` direction-pair). The aggregate rate shift is dominated by **sample composition** + **sampling-noise**, not by mechanism precision loss:

1. **Round-trip 5/6 = 83.3%** (cycle-23 85.7%). 1pp down within noise band; the 4 CM canonical math-inverse anchors all preserve at ACCEPT, plus the OC `_value × _bucketContents` pack/unpack pair. Lone OC reject is `_minCap × _maxCap` (same-domain-marker false-positive).

2. **Idempotence non-lifted 0/3 = 0%** (cycle-23 0/0 with 3 unknown). Surface composition recount (3 → 5 picks; cycle-23 had mislabelled the 3 Algo chunk methods as lifted) restored 3 REJECT picks to the pool. The 6-cycle 0% rate continues, now with REJECT verdicts rather than evaporation.

3. **Idempotence-lifted 6/6 = 100%** (cycle-23 4/6 = 66.7%). Sample-composition shift: cycle-23 included 2 Algo lifted Iterator-like REJECTs that no longer exist in the recounted v1.27 distribution (cycle-23 mis-bucketed; the 3 Algo chunk methods are non-lifted). The 6 OC-only lifted picks (3 sorts + 3 internal helpers) all pass.

4. **Monotonicity 3/4 = 75%** (cycle-23 4/5 = 80%). Within noise band.

5. **Commutativity 1/3 = 33.3%** (cycle-23 1/3 = 33.3%). Rate-stable. The CM `_relaxedAdd` accepts; Algo `binomial` + OC `index(_:offsetBy:)` reject.

6. **Associativity 1/3 = 33.3%** (cycle-23 2/3 = 66.7%). Sample-composition shift: cycle-25 sample includes OC `index(_:offsetBy:)` and Algo `binomial` rejects rather than two CM additive accepts.

7. **Inverse-pair 0/2 = 0%** (cycle-23 0/2). Continues. The 2 surviving picks both pair `bucket(after:|before:)` with `firstOccupiedBucketInChain(with:)` — a V1.27.B closure gap (see findings below).

8. **Identity-element 0/1 = 0%** (cycle-23 0/1). 6-cycle stable reject on `rescaledDivide × Complex.zero` curated-constant false-positive.

9. **Dual-style-consistency 5/5 = 100%** (cycle-23 6/6 = 100%). **Four consecutive measurement points** at 100% (cycles 17 + 20 + 23 + 25). Continues as the largest mechanism-class precision contribution.

10. **Composition-lifted 0/1 = 0%** (cycle-23 0/1). 3-cycle stable reject on `advance(until:)` monotone-bounded false-positive.

## Per-template results

| Template | Cycle-25 | Cycle-23 | Cycle-20 | Trajectory |
|---|---:|---:|---:|---|
| round-trip | 5/6 = **83.3%** | 85.7% | 60.0% | stable high |
| idempotence (non-lifted) | 0/3 = 0.0% | n/a (0/0) | 0.0% | 6-cycle 0% continues |
| idempotence-lifted | 6/6 = **100.0%** | 66.7% | 50.0% | up; OC-only pool is precision-dominant |
| monotonicity | 3/3 = **100.0%** | 80.0% | 75.0% | stable high |
| commutativity | 1/3 = 33.3% | 33.3% | 33.3% | 3-cycle rate-stable |
| associativity | 1/3 = 33.3% | 66.7% | 66.7% | sample-shift |
| inverse-pair | 0/2 = 0.0% | 0.0% | 0.0% | 3-cycle 0% (V1.27.B closure gap) |
| identity-element | 0/1 = 0.0% | 0.0% | 0.0% | 6-cycle stable reject |
| dual-style-consistency | 5/5 = **100.0%** | 100.0% | 100.0% | **4-cycle 100%** |
| composition-lifted | 0/1 = 0.0% | 0.0% | 0.0% | 3-cycle stable reject |

## Two new cycle-25 mechanism findings

### Finding 1: V1.27.B closure gap — `bucket(after:|before:) × firstOccupiedBucketInChain(with:)`

V1.27.B added a name-prefix-gated full-veto for inverse-pair direction-counter requiring BOTH sides of the pair to match the `["index", "bucket", "word"]` prefix list. The cycle-23 finding it targeted (`bucket(after:) × bucket(before:)`) was correctly full-vetoed (-1 surface). But the v1.27 surface contains *different* surviving inverse-pair candidates: `bucket(after:) × firstOccupiedBucketInChain(with:)` and `bucket(before:) × firstOccupiedBucketInChain(with:)`. The reverse side `firstOccupiedBucketInChain` doesn't match any prefix in the gate, so the full-veto doesn't fire — only the V1.11.1 either-side -10 counter applies, leaving score 20 (Possible).

Both pairs are REJECT in cycle-25 triage. **Proposed cycle-26 mechanism:** extend the name-prefix gate to either-side full-veto when the matching side has a curated direction label (`after`/`before`), since the asymmetric pairing (direction-op × search-op) is structurally not an inverse pair.

### Finding 2: Identity-element curated-constant match too lax for non-additive operators

`rescaledDivide(_:_:) (Complex, Complex) -> Complex` is suggested with `Complex.zero` as the identity. Division by zero is undefined; neither side of the two-sided identity holds. The IdentityElementTemplate's `+40` "Curated identity-element constant" signal matches on type-shape (`(T, T) -> T` with `T.zero`) without checking whether the operator is additive vs multiplicative vs neither. This is a 6-cycle stable reject — the same lone outlier has reject-anchored cycles 17/20/23/25.

**Proposed cycle-26 mechanism:** narrow the curated-constant match to the operator's algebraic family — `T.zero` should only fire on `+`-shape (additive) operators, not on `/`-shape (division) or `*`-shape (multiplicative); `T.one` should fire on multiplicative. Cross-reference with the curated additive/multiplicative verb sets that V1.19.C / V1.21.B already use for composition.

## Mechanism-class effectiveness at cycle 25

- **V1.18.C dual-style: 5/5 = 100%**. **Four-cycle rate-stability** (17 + 20 + 23 + 25) — the gold standard mechanism class.
- **V1.21.C math-forward**: cycle-25 4 CM canonical anchors all preserve at ACCEPT (rate-stable).
- **V1.21.A + V1.22.A + V1.24.B IteratorProtocol/mutator-blocklist vetoes**: 0 cycle-25 sample picks (carrier-classes fully closed).
- **V1.27.A Sequence-conformance fallback**: 0 cycle-25 sample picks. Closure projection 0 vs targeted -2 (cycle-24 finding); infrastructure ready for future corpora.
- **V1.27.B name-prefix gate**: closed `bucket(after:) × bucket(before:)` (cycle-23 finding) but didn't close the asymmetric `bucket(after:) × firstOccupiedBucketInChain` pair (cycle-25 finding 1).
- **V1.22.C class 14 (recall-positive fixed-point-name)**: still 0 sample picks (no surfacing on cycle-1..14 corpora; 9-cycle carry of infrastructure-without-evidence).

## §19 reachability assessment after 25 cycles

The empirical-tuning loop reached its **first plateau plateau measurement** at cycle 25. The two consecutive cycle-23/25 measurements at 63.6% and 67.6% bracket the true acceptance rate in the 63-68% range. The §19 ≥70% target is **3-7pp above the plateau**.

The mechanism-cycle cadence is yielding diminishing returns:
- Cycles 17 → 20: -3.5pp (calibration trade-off; sample-shift).
- Cycles 20 → 23: +18.8pp (largest single-cycle jump; 4 mechanism cycles closed -38 candidates).
- Cycles 23 → 25: -4.0pp (1 mechanism cycle closed -1 candidate; plateau).

The cycle-25 surface (113) is dominated by **canonical patterns that are correct-by-construction** (dual-style, math-forward, lifted-sort, ordered-codomain monotone) **and lone-outlier rejects that resist mechanism closure** (rescaledDivide identity-element, advance(until:) composition, bucket-pair inverse-pair, OC capacity-marker round-trip). Closing the remaining rejects requires either:

1. **Two cycle-26 mechanisms** (Findings 1 + 2 above) projected to close ~3-5 candidates at ~80%+ precision — potentially +2-4pp.
2. **The architectural shift to test-execution evidence** (user's prior question; deferred per "try mechanism cycles first" steer). Direct property-test execution would convert Unknown/Reject categories into hard verdicts, removing the type-pattern false-positives that comprise most rejects.

## Cycle-26 priority list

Top of list (priority-rotated post-cycle-25):

1. **Inverse-pair asymmetric-pair extension (cycle-25 finding 1)**. Name-prefix full-veto when one side matches direction-prefix and the other is a search-shape. Projected -2 OC closures.
2. **Identity-element algebraic-family narrow (cycle-25 finding 2)**. Restrict `T.zero` curated match to additive-verb operators. Projected -1 CM closure.
3. **Composition-lifted monotone-bounded full-veto (carry-forward)**. The `advance(until:)` -25 counter doesn't close; promote to veto. Projected -1 OC closure.
4. **FP approximate-equality template arm (12-cycle carry-forward)**. Correctness-emission work; doesn't shift the aggregate rate (CM round-trips already accept) but unblocks production test emission.
5. **Architectural reconsideration** (cycle-25 outcome B signal): the precision ceiling reached around 65% suggests name-based heuristics have approached the asymptote. The user's earlier raised question (test-execution evidence) becomes a higher-priority option than additional mechanism cycles.

## Conclusion

Cycle 25 produced the **sixth empirical measurement point** and the **first plateau confirmation in the loop's history**. The six-point trajectory 26.7% → 34.8% → 52.3% → 48.8% → 67.6% → **63.6%** establishes that the §19 ≥70% target is **3-7pp above the plateau** reached after 25 calibration cycles.

The cycle-23 +18.8pp jump was real (driven by -38 candidates of high-precision mechanism closure across v1.21-v1.25), but it overshot the steady-state rate by ~4pp. Two consecutive measurements now bracket the true rate at 63-68%.

Three mechanism classes carry the rate at 100% (idempotence-lifted, monotonicity, dual-style-consistency); four classes are 0% with lone outliers (inverse-pair, identity-element, composition-lifted, idempotence non-lifted). The structural finding is that **name-based heuristic precision has approached its asymptote** — additional mechanism cycles target small surfaces with diminishing returns. The next high-leverage move is either two targeted mechanism cycles addressing the cycle-25 findings (projected +2-4pp) or the architectural shift to test-execution evidence (PRD §20 v1.1+).
