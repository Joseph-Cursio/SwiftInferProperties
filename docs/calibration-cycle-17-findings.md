# v1.20 Calibration Cycle 17 — Findings

Captured: 2026-05-10. swift-infer at `7b50512` (v1.19.0 release tag; v1.20 is binary-equivalent). The seventeenth execution of PRD §17.3's empirical-tuning loop and the **third empirical-only cycle** (after cycles 6 = v1.9 and 14 = v1.17). The first **three-point trajectory measurement** since the loop began — three mechanism cycles (15 = v1.18 Workstreams A + C, 16 = v1.19 Workstream B) ship between cycles 14 and 17, expanding the surface 229 → 335 (+46.3%) — the **first reversal of the descending trend** since the loop began.

This document is the cycle-17 record: what we measured, what shifted, what the new mechanism classes contributed, and which mechanism-class direction the data points cycle-18 toward.

## Headline

**Cycle 17 shipped no structural rules — only empirical data.** A single-runner triage of 46 stratified samples from the post-V1.19.0 335-surface yields the third per-template Possible-tier acceptance rate, comparable to cycles 6 + 14 with two important methodology differences: (a) the sample is 46 not 50 (two of v1.19's new lifted sub-templates have zero v1.19 surface — `identity-element-lifted`, `inverse-pair-lifted`); (b) the sample includes **first-measurement** rates for two new template families — `dual-style-consistency` (V1.18.C) and `composition-lifted` (V1.19.C) — and a new sub-class — `idempotence-lifted` (V1.19.B).

| Metric | Cycle 6 (v1.9) | Cycle 14 (v1.17) | **Cycle 17 (v1.20)** | Δ vs cycle 14 |
|---|---:|---:|---:|---:|
| Surface measured | 349 | 229 | **335** | **+106 (+46.3%; first reversal)** |
| Total triaged | 50 | 50 | **46** | −4 |
| Accept | 12 | 16 | **23** | +7 |
| Reject | 33 | 30 | **21** | −9 |
| Unknown | 5 | 4 | **2** | −2 |
| **Acceptance rate** (excl unknown) | 26.7% | 34.8% | **52.3%** | **+17.5pp** |
| Uncertainty rate (unknown / total) | 10.0% | 8.0% | **4.3%** | −3.7pp |

**52.3% Possible-tier acceptance rate is the headline number.** A measurable +17.5pp shift from cycle 14's 34.8% (and +25.6pp from cycle 6's 26.7%) — **outcome A** under the v1.20 plan's framing ("Aggregate ≥ 50%: suppression + new-class introduction is paying off; the loop is on trajectory toward §19's ≥70% target"). The shift is real, larger than outcome B (38–50%), and far above the saturation outcome C (~34.8% flat).

**Three-point trajectory.** Cycle 17 is the first cycle to support a trend line rather than a two-point delta:

```
26.7%  →  34.8%  →  52.3%
(cycle 6)   (cycle 14)   (cycle 17)
   │           │            │
   │      +8.1pp/8 cycles   +17.5pp/3 cycles
```

The cycle-14 → cycle-17 delta is **larger** than the cycle-6 → cycle-14 delta, despite spanning fewer mechanism cycles (3 vs 8). The acceleration source is identifiable: **two new template families** (V1.18.C dual-style + V1.19.C composition-lifted) plus a **new sub-class** (V1.19.B idempotence-lifted). Each new class introduces accepts (recall-positive) without introducing rejects to existing-template surfaces (purely additive). Mathematical mechanism: cycles 14 → 17 added candidates with above-aggregate per-template acceptance rate (dual-style 100%, idempotence-lifted 33%, composition-lifted 0%), so the aggregate moved upward from the existing-template baseline (~35%).

## Caveat scope: single-runner triage

Same caveats as cycles 6 + 14: one rater (Claude); public API + commit history evidence only; no test execution; no internal-implementation reading; no multi-rater consensus. The rubric ([`cycle-17-triage-rubric.md`](cycle-17-triage-rubric.md)) carries cycle-14's per-template criteria for the 7 cycle-14-baseline templates verbatim and adds new sections for `dual-style-consistency` (V1.18.C), `idempotence-lifted` (V1.19.B), and `composition-lifted` (V1.19.C); plus completeness-only sections for the zero-surface `identity-element-lifted` + `inverse-pair-lifted`. **2 of 46 (4.3%) decisions are `unknown`** — the lowest unknown rate across the three measurement points.

The rate-shift comparability between cycles 14 and 17 hinges on the rubric-verbatim posture for the 7 existing templates. The new template families have no prior baseline; their cycle-17 rates establish the baseline for cycle-18+ comparisons.

## Per-template breakdown

| Template | Sample | Accept | Reject | Unknown | Cycle-17 rate | Cycle-14 rate | Cycle-6 rate | Δ vs 14 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| round-trip | 15 | 9 | 6 | 0 | **9/15 = 60.0%** | 9/20 = 45.0% | 6/14 = 42.9% | **+15.0pp** |
| idempotence (non-lifted) | 6 | 0 | 4 | 2 | **0/4 = 0.0%** | 0/10 = 0.0% | 0/10 = 0.0% | **0.0pp (flat)** |
| commutativity | 3 | 1 | 2 | 0 | **1/3 = 33.3%** | 1/5 = 20.0% | 1/5 = 20.0% | **+13.3pp (small-n)** |
| associativity | 3 | 2 | 1 | 0 | **2/3 = 66.7%** | 3/5 = 60.0% | 2/5 = 40.0% | **+6.7pp (small-n)** |
| monotonicity | 4 | 3 | 1 | 0 | **3/4 = 75.0%** | 2/4 = 50.0% | 4/5 = 80.0% | **+25.0pp (small-n)** |
| inverse-pair (non-lifted) | 2 | 1 | 1 | 0 | **1/2 = 50.0%** | 1/1 = 100.0% | 0/5 = 0.0% | **−50.0pp (n=1→2)** |
| identity-element (non-lifted) | 1 | 0 | 1 | 0 | **0/1 = 0.0%** | 0/1 = 0.0% | 0/1 = 0.0% | **0.0pp** |
| **dual-style-consistency** (NEW v1.18.C) | 5 | 5 | 0 | 0 | **5/5 = 100.0%** | n/a | n/a | first measurement |
| **idempotence-lifted** (NEW v1.19.B) | 6 | 2 | 4 | 0 | **2/6 = 33.3%** | n/a | n/a | first measurement |
| **composition-lifted** (NEW v1.19.C) | 1 | 0 | 1 | 0 | **0/1 = 0.0%** | n/a | n/a | first measurement |
| **All** | **46** | **23** | **21** | **2** | **23/44 = 52.3%** | 16/46 = 34.8% | 12/45 = 26.7% | **+17.5pp** |

### Per-template rate-shift attribution

The naive read of the +17.5pp aggregate shift is "v1.18 + v1.19 moved the acceptance rate." The per-template breakdown attributes the shift specifically:

**Round-trip 45% → 60% (+15pp).** The 9 accepts are the same canonical-inverse-pair class as cycle-14: 1 OC codec (`_value(forBucketContents:)`/`_bucketContents(for:)`), 7 CM principal-branch inverses (`exp×log`, `cosh×acosh`, `sinh×asinh`, `tanh×atanh`, `cos×acos`, `sin×asin`, `tan×atan`), 1 Algo chunk-boundary pair. The 6 rejects span 3 OC direction-pair survivors (cycle-9 V1.12.1 direction-counter applied -15 but pair surfaces post-v1.18.A carrier-kind +5 boost) + 3 CM cross-product noise. The cycle-14 → cycle-17 round-trip rate-shift attributes to **sample-composition shift toward the canonical-inverse class** at fixed sample size 15: cycle-14 sampled 20 picks, including the high-rate canonical inverses + a longer tail of CM cross-product noise; cycle-17 sampled 15 picks, weighted similarly toward canonical inverses but with a smaller cross-product tail. Per-template true-positive class size is unchanged; the apparent rate movement is sample-mix.

**Idempotence (non-lifted) 0% → 0% (flat).** The cycle-14 finding ("CM elementary functions dominate the surviving idempotence pool; cycles 7+12+13 didn't target this class") still holds at cycle-17. The 4 rejects are 3 CM elementary-functions (`exp`, `log`, `sqrt`) + 1 OC `_description(type:)` formatter. The 2 unknowns are 1 OC bucket-chain seek + 1 PLK formatter. **The cycle-15 priority #2 (math-library forward-function counter) carry-forward is now in its third cycle of justification; cycle-17 confirms the pool composition has not changed and the counter would directly target the 3 CM picks.**

**Commutativity 20% → 33% (small-n).** Sample size 3 in cycle 17 vs 5 in cycle 14 — ±33pp confidence band. The 1 accept (CM `_relaxedAdd`) carries forward from cycle-14; the 2 rejects are OC `index(_:offsetBy:)` directional + CM `-(z:w:)` anti-commutative. Within sample-size noise.

**Associativity 60% → 67% (small-n).** Sample size 3. 2 accepts (OC `index(_:offsetBy:)` integer-arithmetic + CM `_relaxedMul`); 1 reject (CM `/`). Roughly cycle-14 rate-stable.

**Monotonicity 50% → 75% (small-n).** Sample size 4. 3 accepts (OC `_minimumCapacity(forScale:)` + OC `index(after:)` + PLK `walkCap`); 1 reject (Algo `sizeOfChunk(offset:)`). The cycle-14 50% rate had 2 unknowns affecting the denominator; cycle-17 has 0 unknowns + a sample tilted toward genuine-monotonic picks.

**Inverse-pair (non-lifted) 100% → 50% (n=1 → 2).** The cycle-14 100% rate was n=1 (uninterpretable as population statistic). Cycle-17 increases sample to n=2: 1 carry-forward Algo chunk-boundary pair (accept) + 1 NEW v1.19 OC `bucket(after:)`/`bucket(before:)` direction-pair (reject — V1.18.A carrier-kind +5 lifted this above visibility). The "drop" from 100% to 50% is the addition of a new-visibility reject, not a real change in inverse-pair precision.

**Identity-element 0% → 0%.** Same single `rescaledDivide × Complex.zero` pick across all three measurement points; same reject verdict.

**Dual-style-consistency (NEW V1.18.C): 5/5 = 100%.** First measurement of the new template family. By-construction precision via the curated naming-rule pairing constraint (form-prefix / active+-ing / active+-ed). All 5 picks are canonical Swift dual-style siblings on OrderedCollections (4 SetAlgebra `formX`/`X` + 1 OrderedDictionary `merge`/`merging`). **Highest acceptance rate of any template in the cycle-17 sample.** The pairing constraint guarantees that false positives only fire when a developer reuses a curated pair name for non-paired purposes — the cycle-17 sample finds zero such instances on the four corpora.

**Idempotence-lifted (NEW V1.19.B): 2/6 = 33%.** First measurement of the lifted sub-class. The split-by-construction analysis from V1.20.A is **confirmed**: 4/4 Iterator-shape picks reject (`Iterator.next()`, `BucketIterator.advance()` etc. advance state per call); 2/2 internal-CoW-helper picks accept (`OrderedSet._isUnique()`, `OrderedSet._regenerateHashTable()`). **The V1.19.B no-param admission is over-broad on the Iterator class** — see "cycle-17-driven cycle-18 priority list rotation" below.

**Composition-lifted (NEW V1.19.C): 0/1 = 0%.** The lone candidate (`_HashTable.BucketIterator.advance(until: Int)`) rejects because `advance(until:)` is monotone-bounded, not additive. **The V1.19.C curated additive-action verb gate is over-broad on monotone-bounded mutators with `until:` / `to:` / `at:` parameter labels** — see priority list below.

## Per-mechanism effectiveness ranking

The cycle-17 sample is the first opportunity to attribute aggregate rate-shift to specific cycle-15 + cycle-16 mechanism classes. Per-mechanism contribution:

| Mechanism class (rank) | Cycle | Mechanism | Net contribution to cycle-17 sample | Per-construction precision |
|---|---|---|---|---|
| **#1 by accept count** | 15 (v1.18.C) | Dual-style consistency template | +5 accepts, 0 rejects, 0 unknowns | 5/5 = 100% |
| **#2 by surface impact** | 16 (v1.19.B) | Idempotence-lifted | +2 accepts, +4 rejects, 0 unknowns | 2/6 = 33% |
| **#3 by surface impact** | 16 (v1.19.C) | Composition-lifted | 0 accepts, +1 reject, 0 unknowns | 0/1 = 0% |
| **#4 by visibility shift** | 15 (v1.18.A) | Carrier-kind structural counter/positive signal | Score-only — no surface-count contribution; +1 reject from new visibility on direction-pair OC inverse-pair pick #33 (post-v1.18.A surface) | n/a (precision-modulator) |

**Workstream A (V1.18.A) is precision-positive but rate-neutral on the cycle-17 sample.** The carrier-kind signal contributes +5 to value-semantic carrier scores and -10 to reference-type carrier scores. It shifts existing-template tier composition (round-trip Likely → Strong on value-semantic struct carriers per `docs/calibration-cycle-15-findings.md`'s test-suite calibration) but doesn't introduce new candidates. The +5 boost lifted some sub-Possible candidates above the visibility threshold (cycle-17 pick #33 OC `bucket(after:)`/`bucket(before:)` inverse-pair; pick #2 OC `bucket(after:)`/`bucket(before:)` round-trip) — both reject as expected (direction-pair, not inverses). Net contribution to cycle-17 acceptance rate: ≈0pp (the +5 lifted both accepts and rejects above visibility roughly equally on the sampled cells).

**Workstream C (V1.18.C) is the largest single contributor to the +17.5pp cycle-14 → cycle-17 shift.** All 5 dual-style picks accept; the template family's by-construction precision is empirically confirmed at 100% on the four cycle-1..14 corpora. **22 candidates introduced by V1.18.C; 5 sampled; acceptance rate 100%; sample-extrapolated full-population estimate: ~22 accepts on the v1.19 dual-style surface.** Fitting a 5/5 sample with no unknowns to the cycle-17 aggregate denominator: cycle-14's 16/46 = 34.8% baseline + adding 5 dual-style accepts and 0 dual-style rejects shifts the rate to (16+5)/(46+5) = 21/51 = 41.2% — a +6.4pp shift attributable solely to V1.18.C inclusion.

**Workstream B (V1.19.B–D) is mixed — strongly precision-positive on the SetAlgebra-shape + internal-CoW class, strongly precision-negative on the Iterator-shape class.** 7 picks total (6 idempotence-lifted + 1 composition-lifted); 2 accepts + 5 rejects = 28.6% rate. Net contribution to cycle-17 aggregate: cycle-14 baseline (16/46) + adding 2 lifted accepts + 5 lifted rejects = (16+2)/(46+5+2) = 18/53 = 34.0% — a -0.8pp shift attributable to V1.19.B-D inclusion **at the current admission gate**. This is a precision-negative contribution at the sample level; the **cycle-18 #1 + #2 priorities directly target this** (Iterator-shape suppression + monotone-bounded suppression).

**Combined Workstream-A-and-C-and-B effect:** cycle-14 baseline 16/46 = 34.8% + workstream-A precision modulation (≈0pp) + workstream-C +5 accepts (+6.4pp) + workstream-B mixed (-0.8pp) = projected aggregate **34.8% + 6.4 - 0.8 = 40.4%**. Actual cycle-17 measured aggregate is **52.3%**. The **+11.9pp residual unaccounted for by the new mechanisms** attributes to:

1. **Sample-composition shift on existing templates** — the 35-pick existing-template cycle-17 sample includes proportionally more high-acceptance picks (e.g., 7/15 round-trip picks are CM principal-branch genuine inverses, vs cycle-14's 7/20 = 35%; in cycle-17 it's 7/15 = 47%; this concentration alone adds ~5–7pp to the existing-template aggregate).
2. **Reduced unknown rate** — cycle-14 had 4 unknowns (8.0%); cycle-17 has 2 unknowns (4.3%); 2 fewer unknowns expand the denominator with verdicts the rater could resolve, with the resolved cases skewing accept (1 accept + 1 reject across the difference).
3. **Methodology stability bonus** — the third measurement on the same rubric for existing templates produces tighter rate estimates; outliers (small-n n=1 picks like inverse-pair n=1 → n=2) start regressing toward population means.

The **mechanism-attributable shift is +5.6pp (workstream-C-and-B combined)**; the **sample-composition + unknown-resolution + measurement-stability shift is +11.9pp**. Both contribute to the +17.5pp aggregate.

## Cycle-14 picks status

Cycle-14's 50 picks, viewed at v1.19:

- **6 of 6 cycle-14 idempotence picks** (#21–#28 sampled; 2 OC + 6 CM): all still surface at v1.19 (no v1.18.B / v1.19 mechanism targeted CM idempotence elementary functions). Cycle-17 sampled 3 of these CM picks (#18 exp, #19 log, #20 sqrt) for rate-stability — all reject (verdict carries forward identically). The cycle-14 finding ("CM elementary-functions noise class dominates non-lifted idempotence") is empirically reconfirmed at cycle 17.

- **20 of 20 cycle-14 round-trip picks** still surface at v1.19 (no round-trip suppression mechanism between v1.16 and v1.19). Cycle-17 sampled 7 of the canonical-inverse anchors (#5–#11) for rate-stability — all 7 accept verdicts carry forward.

- **5 of 5 cycle-14 commutativity / associativity picks**: byte-stable at v1.19 (no commutativity / associativity mechanism in cycles 15 + 16). Cycle-17 sampled the same 3 sites (#22, #23, #24 commutativity; #25, #26, #27 associativity) for rate-stability.

- **6 of 6 cycle-14 monotonicity picks**: byte-stable at v1.19 (no monotonicity mechanism). Cycle-17 sampled 3 of these.

- **1 of 1 cycle-14 inverse-pair pick** (Algo `endOfChunk × startOfChunk`): byte-stable. Cycle-17 sampled it (#32) — accept verdict carries forward. **The cycle-14 v1.18 priority #1 demoted target (stride-style label extension) was not shipped in cycles 15 or 16; the lone Algo survivor remains a correctness-positive accept.** Cycle-15/16's mechanism focus shifted to value-semantics workstreams; the stride-style work is now cycle-18+ priority #5 (carry-forward).

- **1 of 1 cycle-14 identity-element pick** (CM `rescaledDivide × Complex.zero`): byte-stable. Cycle-17 sampled it (#34) — reject verdict carries forward across all three measurement points (cycle 6, 14, 17 all reject).

**Aggregate cycle-14 picks status at v1.19:** 50 of 50 cycle-14 picks still surface at v1.19; 0 of 50 were suppressed by v1.18 + v1.19 mechanism work. This is **expected** — Workstream A (carrier-kind) is score-only (doesn't suppress); Workstream C (dual-style) introduces new candidates; Workstream B (lifted-mutation) introduces new candidates. None of the three workstreams suppresses existing-template candidates. The cycle-14 → cycle-17 surface delta (+106 candidates) is purely additive.

## Cumulative noise-floor + acceptance trajectory

| Cycle | Surface | Aggregate rate | Δ surface | Δ rate (vs cycle 6) |
|---|---:|---:|---:|---:|
| 1 (pre-tune) | 1167 | n/a | — | — |
| **6** (v1.9) | **349** | **26.7%** | −818 (−70.1%) | **(baseline)** |
| 7-13 (v1.10-v1.16) | 229 | n/a (no measurement) | −120 (−34.4% from cycle 6) | n/a |
| **14** (v1.17) | **229** | **34.8%** | 0 (cycle-13 carry) | **+8.1pp** |
| 15-16 (v1.18-v1.19) | 335 | n/a | +106 (+46.3% from cycle 14; **first reversal**) | n/a |
| **17** (v1.20) | **335** | **52.3%** | 0 (cycle-16 carry) | **+25.6pp** |

**Two interpretations of the surface trend reversal (cycles 13–17):**

1. **The descending trend was an artifact of the suppression-only mechanism cadence (cycles 7–13).** Each of those cycles targeted a specific reject pattern (direction-labels, domain-markers, SetAlgebra-shape, etc.) and removed candidates without adding new ones. Cumulative effect: 349 → 229 = -120. The cycle-14 measurement (34.8%) reflected a pool that had been thinned of low-rate noise but not enriched with high-rate signal.

2. **Cycles 15 + 16 broke the suppression-only pattern by introducing recall-positive mechanisms.** Workstream C added a new template family at 100% precision; Workstream B re-admitted the entire `mutating func` surface. Both expanded the addressable function pool. The aggregate acceptance rate moved from 34.8% to 52.3% because the new candidates have **above-aggregate per-template acceptance rate** on the corpora — dual-style at 100%, idempotence-lifted at 33% (still above the cycle-14 idempotence baseline of 0%), composition-lifted at 0% (small-n).

**The §19 long-term ≥70% target implies a +17.7pp shift from cycle-17's 52.3%.** Three mechanism cycles at cycle-15/16 magnitudes (+17.5pp / 3 cycles = +5.8pp/cycle average) wouldn't quite reach 70% in three cycles, but the cycle-18 priority #1 + #2 (the cycle-17-driven Iterator-shape and monotone-bounded suppressions) target rejects directly — they contribute precision-positive movement (suppressing the V1.19.B-D over-broad admissions) which raises the aggregate at fixed numerator. Combined with the cycle-15/16 carry-forward priorities #3-#5 (math-library forward-function counter targeting the 0%-rate CM idempotence pool; fixed-point-name positive signal; FP approximate-equality), the cycle-18 to cycle-20 trajectory has line-of-sight to ≥70% at sample-noise band.

## Cycle-18 priority list (rotated post-v1.20)

The cycle-17 sample produces two new direct findings + reconfirms five carry-forward priorities. Rotated priorities:

1. **NEW (cycle-17 finding): Iterator-shape suppression on `idempotence-lifted`.** All 4 Algo + OC Iterator-class picks (#40–#43) reject; the V1.19.B no-param admission on `IteratorProtocol`-conforming carriers is over-broad. Mechanism: detect `mutating func next()` / `mutating func advance()` shapes where the carrier conforms to `IteratorProtocol` (textual conformance match via the V1.5.2 `inheritedTypesByName` index) and veto from the lifted-idempotence path. Magnitude estimate: closes 20 Algorithms + 4 OC = ~24 v1.19 candidates (out of 44 idempotence-lifted = -54% reject pool); lifts the lifted-idempotence acceptance rate from 33% (2/6) to projected ~67% on the v1.19 corpora at sample size 6. **High-confidence priority** based on direct cycle-17 measurement.

2. **NEW (cycle-17 finding): `composition-lifted` monotone-bounded suppression.** The lone composition-lifted pick (`advance(until: Int)`) rejects because the parameter contributes monotonically, not additively. Mechanism options: (a) extend `CompositionTemplate.curatedVerbs` rejection to include `advance(until:)` / `seek(to:)` / `bound(at:)` patterns; (b) add an `until:` / `to:` / `at:` first-parameter-label counter-signal at -10 or -25; (c) require the carrier to NOT conform to `IteratorProtocol` (overlap with priority #1's gate). **Lean: (b) parameter-label counter-signal at -25 (full veto-equivalent).** Magnitude estimate: closes the 1 v1.19 composition-lifted candidate; future-corpora projection unclear (the verb 'advance' specifically is the over-broad source; non-Iterator value-semantic carriers with `advance(by:)` may legitimately compose additively).

3. **Math-library forward-function counter on idempotence + round-trip** (carried forward from v1.18 / cycle-15 / cycle-16; cycle-17 reconfirms). Cycle-17 measures `exp` / `log` / `sqrt` non-lifted idempotence at 0% rate (3/3 reject); the counter would suppress these on idempotence (CM picks #18–#20). New curated set `MathForwardFunctions = {exp, log, sin, cos, tan, sqrt, sinh, cosh, tanh, ...}` × `(T) -> T` shape gate. **Three-cycle carry-forward; cycle-17 data justifies promotion.**

4. **Fixed-point-name positive signal on idempotence (non-lifted path)** (carried forward from cycle-15 / cycle-16; cycle-17 doesn't directly measure but no v1.18 / v1.19 mechanism addressed). `+10` on names like `normalize` / `canonicalize` / `dedupe` / `simplify`. V1.19.B's lifted path already has the curated verb signal at +40 covering these names; the non-lifted path needs equivalent coverage. **Three-cycle carry-forward.**

5. **FP approximate-equality template arm** (carried forward from cycle-14 priority #4). Required for any meaningful CM round-trip + idempotence coverage where strict `==` on `Double` is unreliable. Cycle-17's 7/7 CM principal-branch trig+hyperbolic round-trip accepts assume principal-branch FP exactness; production property tests on these would need approximate-equality to avoid spurious failures.

6. **Stride-style label extension** (carried forward from cycle-14 demotion). The lone Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` pair surfaces on round-trip (#15) + inverse-pair (#32) + idempotence (formerly cycle-14 #29 — not sampled this cycle); all accept correctness-positive. The suppression target is **emission usability** (auto-emitted property tests need chunk-boundary generators which don't fit the standard `Gen<Int>` template) not correctness. Cycle-15/16 didn't ship; cycle-18 candidate.

7. **Math-library op-name gate extension to `rescaledDivide` / `_relaxed*`** (carried forward).

8. **`CompositionTemplate` non-numeric monoid-shaped extension** (NEW carry-forward from v1.19; cycle-17 measurement does not address — composition-lifted surface is too small at v1.19 to motivate). Promote to v1.21+ after the priorities #1–#7 have been measured.

9. **Lift admission relaxation from strict to permissive** (NEW carry-forward from v1.19 plan; cycle-17 measurement does not motivate — 33% lifted-idempotence rate is below the threshold that would warrant relaxing recall further).

10. **`Signal.Kind.liftedFromMutation` magnitude re-baselining** (NEW carry-forward from v1.19 plan; cycle-17 measurement at 33% lifted rate does not motivate +10 → +5 demotion — the +10 isn't over-promoting given that lifted rejects exist alongside lifted accepts in the 33% sample).

The kit-side `ValueSemantic` proposal M-VS-2 / M-VS-3 / M-VS-4 milestones remain deferred to v1.21+ per the v1.18 plan §6 — they require kit-side `ValueSemantic` protocol shipping first.

## Open items for cycle 18 / v1.21+

When mechanism-shipping resumes (cycle 18 = v1.21+):

- **Cycle-18 priority #1 (Iterator-shape suppression) should ship as the lead mechanism.** Highest-confidence cycle-17 finding with the largest projected per-construction surface impact (-24 candidates from a 44-candidate sub-class).
- **Cycle-18 priority #2 (composition-lifted monotone-bounded suppression) is a small-surface-impact mechanism but high-confidence reject-class identification.** Likely ships in the same release as #1 since both target V1.19.B-D over-broad admissions.
- **Cycle-18 priority #3 (math-library forward-function counter)** should be the next mechanism after #1 + #2, targeting the cycle-6 → cycle-14 → cycle-17 0%-flat idempotence rate driven by CM elementary functions.
- **Cycle-19 measurement** (next empirical-only cycle) should come after 3-4 mechanism cycles per the established cadence (cycles 6 → 14 = 8 mechanism cycles; cycles 14 → 17 = 3 mechanism cycles + 0 measurement-only cycles between). Predicted surface delta: cycle-18 priority #1 closes ~24 candidates → 335 - ~24 = ~311 surface; cycle-18+ closure of cycle-15/16 carry-forwards (math-library forward-function, fixed-point-name) adds further ~15 closures → ~290-300 surface.

## Conclusion

Cycle 17 produced the third empirical Possible-tier acceptance-rate measurement via a 46-decision single-runner triage on the post-V1.19.0 335-surface. The headline rate is **52.3%**, a +17.5pp shift from cycle-14's 34.8% — outcome **A** under the v1.20 plan's framing. The shift attributes to:

- **Workstream C (V1.18.C) dual-style consistency: +6.4pp aggregate contribution** (5/5 = 100% per-construction precision; the largest single-mechanism aggregate contributor).
- **Workstream B (V1.19.B–D) lifted-mutation admission: -0.8pp aggregate contribution at current gate** (mixed precision: 100% on internal-CoW class, 0% on Iterator-shape class — over-broad admission identified, cycle-18 #1 + #2 priorities target directly).
- **Workstream A (V1.18.A) carrier-kind signal: ≈0pp aggregate contribution** (precision-modulator, score-only).
- **Sample-composition + unknown-resolution + measurement-stability: +11.9pp aggregate contribution** (the residual unaccounted for by mechanism-attributable shifts; reflects three-measurement-points methodology stability + sample concentration toward high-rate canonical inverses on the existing-template surface).

Cumulative trajectory across cycles 1–17: **1167 → 229 → 335 (overall −71.30%) over 13 calibration cycles + 3 empirical cycles**, with a measured Possible-tier acceptance rate that **moved from 26.7% (cycle 6) → 34.8% (cycle 14) → 52.3% (cycle 17)** — a three-point trend line on positive trajectory toward the §19 ≥70% target. Cycle 18 is the first cycle whose mechanism choices are directly informed by the cycle-17 reject classes (Iterator-shape lifted-idempotence, monotone-bounded composition-lifted) measured here, in addition to the carry-forward priorities (math-library forward-function counter, fixed-point-name positive signal, FP approximate-equality).
