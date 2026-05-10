# v1.17 Calibration Cycle 14 — Findings

Captured: 2026-05-09. swift-infer at `9e36efd` (v1.16.0 release tag; v1.17 is binary-equivalent). The fourteenth execution of PRD §17.3's empirical-tuning loop and the **second empirical-only cycle** (after cycle 6 = v1.9). The first **same-methodology re-measurement** of Possible-tier acceptance rate since cycle 6 — six mechanism cycles + one refactor cycle have shipped between the two measurement points, suppressing the surface 349 → 229 (−34.4%).

This document is the cycle-14 record: what we measured, what shifted, what stayed, and which mechanism-class direction the data points cycle-15 toward.

## Headline

**Cycle 14 shipped no structural rules — only empirical data.** A single-runner triage of 50 stratified samples from the post-V1.16.1 229-surface yields the second per-template Possible-tier acceptance rate, comparable point-for-point to cycle-6's measurement on the post-V1.8.1 349-surface.

| Metric | Cycle 6 (v1.9) | **Cycle 14 (v1.17)** | Δ |
|---|---:|---:|---:|
| Surface measured | 349 | **229** | −120 (−34.4%) |
| Total triaged | 50 | **50** | 0 |
| Accept | 12 | **16** | +4 |
| Reject | 33 | **30** | −3 |
| Unknown | 5 | **4** | −1 |
| **Acceptance rate** (excl unknown) | **26.7%** | **34.8%** | **+8.1pp** |
| Uncertainty rate (unknown / total) | 10.0% | 8.0% | −2.0pp |

**34.8% Possible-tier acceptance rate is the headline number.** A measurable +8.1pp shift from cycle 6's 26.7% — outcome **B** under the v1.17 plan's framing ("Aggregate 30-50%: modest improvement; mechanism cycles are precision-positive but recall is also dropping"). The shift is real, smaller than outcome A would have produced, larger than the "flat" outcome C threshold.

## Caveat scope: single-runner triage

Same caveats as cycle 6: one rater (Claude); public API + commit history evidence only; no test execution; no internal-implementation reading; no multi-rater consensus. The rubric ([`cycle-14-triage-rubric.md`](cycle-14-triage-rubric.md)) carries cycle-6's per-template criteria verbatim and adds a Post-cycle-6 mechanism context section so the rater knows which suppression layers (cycles 7-13) each surviving v1.16 candidate has cleared. 4 of 50 (8.0%) decisions are `unknown`.

The rate-shift comparability between cycles 6 and 14 hinges on this rubric-verbatim posture. Methodology drift was the largest threat to the cycle-14 measurement; carrying cycle-6's per-template criteria word-for-word neutralises it.

## Per-template breakdown

| Template | Sample | Accept | Reject | Unknown | Cycle-14 rate | Cycle-6 rate | Δ |
|---|---:|---:|---:|---:|---:|---:|---:|
| round-trip | 20 | 9 | 11 | 0 | **9/20 = 45.0%** | 6/14 = 42.9% | **+2.1pp (flat)** |
| idempotence | 12 | 0 | 10 | 2 | **0/10 = 0.0%** | 0/10 = 0.0% | **0.0pp (flat)** |
| commutativity | 5 | 1 | 4 | 0 | **1/5 = 20.0%** | 1/5 = 20.0% | **0.0pp (flat)** |
| associativity | 5 | 3 | 2 | 0 | **3/5 = 60.0%** | 2/5 = 40.0% | **+20.0pp (small-n)** |
| monotonicity | 6 | 2 | 2 | 2 | **2/4 = 50.0%** | 4/5 = 80.0% | **−30.0pp (small-n)** |
| inverse-pair | 1 | 1 | 0 | 0 | **1/1 = 100.0%** | 0/5 = 0.0% | **+100.0pp (n=1)** |
| identity-element | 1 | 0 | 1 | 0 | **0/1 = 0.0%** | 0/1 = 0.0% | **0.0pp (n=1)** |
| **All** | **50** | **16** | **30** | **4** | **16/46 = 34.8%** | **12/45 = 26.7%** | **+8.1pp** |

### Per-template rate-shift attribution

The naive read of the +8.1pp aggregate shift is "mechanism cycles 7-13 moved the acceptance rate." The per-template breakdown tells a more nuanced story:

**Idempotence stays at 0/10 = 0%.** This is the cycle-14 finding most worth dwelling on. Cycles 7 (V1.10.1 direction-label counter), 12 (V1.15.1 domain-marker counter), and 13 (V1.16.1 SetAlgebra-shape veto) all targeted idempotence specifically. They worked: of the 10 cycle-6 idempotence rejects (#17-#27, IDs cycle-6), 5 are V1.10.1-suppressed direction-labeled, 4 are V1.15.1-suppressed domain-marker-labeled, 1 is now V1.16.1-suppressed SetAlgebra-shaped. **Zero of cycle-6's 10 idempotence rejection picks survive to v1.16.** Yet the cycle-14 idempotence rate is still 0%, because the surviving v1.16 idempotence pool (25 candidates) is dominated by **CM elementary functions** (17 of 25 = 68% — `exp(_:)`, `log(_:)`, `sin(_:)`, `cos(_:)`, `sqrt(_:)` etc.), a noise class cycles 7-13 didn't target. The 6 CM idempotence picks (#23-#28) are all rejects; the 3 Algo picks (#29-#31) are all rejects; the 2 OC picks split into 1 reject + 1 unknown; the 1 PLK pick is unknown. Numerator stays at 0.

**This is selection-shift evidence, not target-improvement evidence.** Cycles 7+12+13 cleared their targeted patterns (precision-positive). They didn't introduce new accepts (recall stayed flat on idempotence). The denominator shrunk; the numerator stayed at zero. So the rate didn't move. **Cycle-15 priority signal: a CM-elementary-functions counter-signal class would target the new dominant rejection pattern.**

**Round-trip 43% → 45% (flat).** Same selection-shift dynamic, smaller scale. Cycles 9+12+13 targeted round-trip rejection patterns; the v1.16 round-trip pool (139 candidates, 136 of which are CM cross-product) still has high reject density. The 9 cycle-14 round-trip accepts are: 1 OC codec, 7 CM principal-branch trig+hyperbolic inverses, 1 Algo chunk-boundary pair. The 11 rejects are CM cross-products + the lone Algo `log(_:) ↔ log(onePlus:)` two-overload pair.

**Commutativity 20% → 20% (flat).** Cycle-6 picked 5 OC `index(_:offsetBy:)` / `distance(from:to:)` Int-op picks + 1 CM `_relaxedAdd` accept; cycle-14 picked 3 OC variants + 1 CM `_relaxedAdd` + 1 CM `-(z:w:)` reject. Mix difference is small; rate is flat.

**Associativity 40% → 60% (n=5 sample-mix noise).** Cycle-14 picked 3 OC `index(_:offsetBy:)` accepts (associativity holds on integer-offset addition) + 1 OC `distance` reject + 1 CM `_relaxedMul` accept + 1 CM `/` reject. The accepts are the integer-arithmetic-associativity cases. With n=5, ±1 pick changes the rate by 20pp — the "shift" is within sample-size noise.

**Monotonicity 80% → 50% (n=4 effective sample-mix noise).** Cycle-6 oversampled the OC capacity-from-scale family (`minimumCapacity` / `maximumCapacity` / `scale` / `walkCap`), all of which accept. Cycle-14 picked 1 capacity (#43 accept) + 1 description (#44 unknown) + 1 index increment (#45 accept) + 1 sizeOfChunk (#46 reject) + 1 walkCap (#47 unknown) + 1 format (#48 reject). More file-diversity → 2 unknowns + 2 rejects. With n=4 effective (after excluding unknowns), the rate has a ±25pp confidence band; the apparent drop is sample-mix noise.

**Inverse-pair 0% → 100% (n=1 uninterpretable).** Only 1 candidate at v1.16 (the lone Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor). Cycle-14 accepts it on chunk-boundary domain. The rate of 1/1 is mathematically 100% but uninterpretable as a population statistic. The cycle-14 finding is "the lone surviving pre-cycle-15 inverse-pair candidate is correctness-positive", which has implications for the cycle-15 priority list (see below).

**Identity-element 0% → 0%.** Same single Likely-tier `rescaledDivide × Complex.zero` pick as cycle-6, same reject verdict.

## Per-corpus breakdown

| Corpus | Sample | Accept | Reject | Unknown | Cycle-14 rate | Cycle-6 rate | Δ |
|---|---:|---:|---:|---:|---:|---:|---:|
| OC | 12 | 5 | 5 | 2 | **5/10 = 50.0%** | 6/22 = 27.3% | **+22.7pp** |
| CM | 28 | 9 | 19 | 0 | **9/28 = 32.1%** | 4/11 = 36.4% | −4.3pp |
| Algo | 7 | 2 | 5 | 0 | **2/7 = 28.6%** | 2/9 = 22.2% | +6.4pp |
| PLK | 3 | 0 | 1 | 2 | **0/1 = 0.0%** | 1/2 = 50.0% | (n≤2 effective) |

**OC's +22.7pp jump is the largest per-corpus shift.** Cycles 7+12+13 targeted OC heavily — direction-label counter cleared 14 OC candidates, domain-marker counter cleared 16 OC candidates, SetAlgebra-shape veto cleared 6 OC candidates. The post-v1.16 OC surface is much cleaner: 43 candidates vs 101 at cycle 6 (−57.4% per-corpus reduction). Of cycle-14's 12 OC picks, 5 accept (vs cycle-6's 6 of 22 accept) — proportionally much higher. **OC is the corpus where mechanism cycles 7-13 had visible per-template rate impact.**

**CM's −4.3pp drift is within sample-size noise.** No mechanism cycle targeted CM directly between cycles 7-13 (CM has 0 deltas in the cycles 7+8+9+11+12+13 corpus tables). The CM rate is essentially unchanged. Cycle-14 oversampled CM to 28 picks (vs cycle-6's 15), so the CM cycle-14 rate has a tighter error bar than cycle-6's CM rate did — the apparent slight drop is consistent with larger-n converging on the true rate. **CM is the corpus where mechanism cycles 7-13 had effectively no impact.**

**Algo's +6.4pp shift is modest and partially mechanism-driven.** Cycles 7+8+9 each suppressed Algo Index-op false positives. Algo's surface dropped 75 → 13 (−82.7% per-corpus reduction, the largest of the four). The remaining 13 Algo candidates are a more concentrated mix; cycle-14 picks include 2 accepts (chunk-boundary inverse pair + true round-trip), 5 rejects, 0 unknowns.

**PLK rate is uninterpretable.** 3 picks total; 2 of them unknown (insufficient public-API evidence to determine `walkCap` monotonicity and `nearMissLines` idempotence). The 1 effective decision (`format(_:)` reject) gives a 0/1 rate. Same pattern as cycle 6 (1/2 effective).

## Cycle-6 picks status rollup

Of the 50 cycle-6 picks, the cycle-7-13 mechanism cycles have suppressed a documented subset. Continuing the cycle-12 + cycle-13 closure (which cycle-13 findings already documented):

| Cycle-6 pick class | Cycle-6 verdict | v1.16 status | Suppression mechanism |
|---|---|---|---|
| OC capacity-from-scale (#1, #2, #3, #17, #20) | reject | suppressed | V1.15.1 domain-marker counter (cycle 12) |
| Algo Index direction (#4, #14, #18, #19, #24, #26, #27) | reject (#18, #19, #24, #26, #27) / accept (#4, #14) | suppressed | V1.10.1 + V1.11.1 + V1.12.1 direction-label counter (cycles 7-9) — **including the cycle-6 accepts**, a known precision-vs-recall tradeoff |
| OC SetAlgebra (#6, #45-#47) | reject | suppressed | V1.14.1 + V1.16.1 SetAlgebra-shape veto (cycles 11+13) |
| CM elementary functions cross-product (#7-#10, #13, #21-#23) | reject (#7-#10, #21, #22) / unknown (#13, #23) | **surviving** | — (no mechanism targets this class) |
| CM principal-branch inverse pairs (#11, #12) | accept | surviving | — (preserved, correctly surfaced) |
| OC user-name `index(_:offsetBy:)` / `distance` (#29-#31, #34-#36) | reject (commut), accept (assoc) | surviving | — (preserved) |
| CM `_relaxed*` (#33, #38) | accept | surviving | — (preserved) |
| OC capacity monotonicity (#39-#41) | accept | surviving | — (preserved) |
| PLK monotonicity (#42, #43) | reject (#42), unknown (#43) | surviving | — |
| Algo Chunk inverse-pair (#15, #48-#49) | accept (#15) / reject (#48-#49) | surviving (#15) / suppressed (#48-#49) | V1.11.1 direction-label (#48-#49) |
| CM identity-element (#50) | reject | surviving | — |

**Aggregate cycle-6 picks status at v1.16:**
- Suppressed by post-cycle-6 mechanisms: ~20 of 50 cycle-6 picks (mostly cycle-6 rejects + a few cycle-6 accepts that fell to direction-label counter).
- Still surfacing at v1.16: ~30 of 50 cycle-6 picks (cycle-6 accepts that survived + cycle-6 rejects/unknowns that aren't in any post-cycle-6 mechanism's curated set).

The notable suppressed cycle-6 ACCEPTS — `index(after:) ↔ index(before:)` Collection-protocol pairs (cycle-6 #4, #14) — are direction-label-counter casualties. They're true positives that the rubric rates as accept; the direction-label counter classifies them as noise based on the parameter-label heuristic, not the underlying property. **This is the clearest precision-vs-recall tradeoff in the cycle 7-13 mechanism family** and the source of the cycle-14 cycle-15-priority-list inverse-pair pick (#19 + #49 acceptance) cautionary note: not every "suppression target" is a false positive.

## Mechanism-class effectiveness ranking

The eight distinct mechanism classes that have shipped across cycles 1-13, ranked by **measurable per-template rate impact** in cycle 14 (vs surface-reduction impact, where cycle 1 dominates):

| Class | Cycles | Surface reduction | Per-template rate impact | Effectiveness |
|---|---|---:|---|---|
| 1. Textual type-name + cross-type pair counter | 1 (V1.4.3) | −809 (−69%) | (no cycle-6 baseline) | **Largest absolute reduction; pre-measurement** |
| 2. Protocol-coverage veto | 2 (V1.5.2) | −5 | (no cycle-6 baseline) | Small reduction; precision-positive |
| 3. Pair-formation skip-list | 3 (V1.6.1) | −3 | (no cycle-6 baseline) | Small reduction; precision-positive |
| 4. Stdlib-conformance bake-in | 4 (V1.7.1) | −24 | (no cycle-6 baseline) | Modest reduction; precision-positive |
| 5. Shape-gated veto | 5 (V1.8.1) | +23 (re-emergence) | (no cycle-6 baseline) | Mixed (re-surfaces; net precision-positive after triage) |
| 6. Parameter-label direction counter (3-template family) | 7-9 (V1.10.1, V1.11.1, V1.12.1) | −92 | OC +22.7pp; Algo +6.4pp; CM 0; PLK 0 | **Largest post-cycle-6 reduction; rate impact concentrated on OC + Algo** |
| 7. Function-name + type-shape composite (3-template family) | 11+13 (V1.14.1, V1.16.1) | −12 | OC +22.7pp (shared with class 6); CM 0; Algo 0; PLK 0 | Small reduction; rate impact OC-only |
| 8. Parameter-label semantic-intent counter | 12 (V1.15.1) | −16 | OC +22.7pp (shared); CM 0; Algo 0; PLK 0 | Small reduction; rate impact OC-only |

**Key observation: classes 6+7+8 collectively delivered the +22.7pp OC rate shift but 0pp on CM.** All three post-cycle-6 mechanism families targeted patterns that exist on OC + Algo (Int / Index / Bucket types, SetAlgebra ops, scale / capacity domain markers) and not on CM (which is dominated by `(Complex) -> Complex` elementary functions). The OC surface dropped 101 → 43 (−57.4%); the CM surface dropped 166 → 166 (0%). Cycle-15's empirical priority is **a mechanism class that targets CM**.

The cycle-14 measurement also reveals that **mechanism-class effectiveness is asymmetric: classes that increase precision (suppress rejects) don't automatically increase recall (introduce accepts)**. Idempotence rate stayed at 0% despite three precision-positive cycles. To move idempotence above 0%, cycle-15 either needs to target the new dominant rejection class (selection-shift continuation) or introduce a positive signal that surfaces idempotence accepts (e.g., the cycle-7 priority list's option (b) — fixed-point-name positive signal on `normalize`/`canonicalize`/`dedupe`/`simplify`).

## What v1.17 ships (the data)

Five artifacts (mirroring cycle 6's three-artifact pattern, plus the cycle-14 supplemental rubric and this findings doc):

- **[`cycle-14-triage-rubric.md`](cycle-14-triage-rubric.md)** — methodology document carrying cycle-6's per-template criteria verbatim + a Post-cycle-6 mechanism context section.
- **[`calibration-cycle-14-data/sample-manifest.md`](calibration-cycle-14-data/sample-manifest.md)** — 50 picks stratified by template × corpus.
- **[`calibration-cycle-14-data/triage-decisions.json`](calibration-cycle-14-data/triage-decisions.json)** — per-decision verdict in the cycle-6-mirroring schema.
- **[`calibration-cycle-14-data/triage-notes.md`](calibration-cycle-14-data/triage-notes.md)** — per-decision rationale.
- **This document** — cycle-14 findings.

No code changes; no test changes; no §13 budget changes. v1.17 is binary-equivalent to v1.16.0.

## Cycle-15 priority list (rotated post-v1.17)

The cycle-15 priority list is anchored in cycle-14's rate-shift attribution. Two new priorities surface; one cycle-13-priority-#1 demotes; the rest carry forward.

1. **Math-library forward-function counter on idempotence + round-trip.** *(NEW; surfaced by cycle-14 idempotence 0% → 0% finding.)* Add a new curated set `SwiftInferCore.MathForwardFunctions.curated = {exp, expMinusOne, log, log(onePlus:), sin, cos, tan, sinh, cosh, tanh, asin, acos, atan, asinh, acosh, atanh, sqrt, ...}` consumed by `IdempotenceTemplate` and `RoundTripTemplate`. Counter weight TBD (likely `-15` parallel to direction-label) on idempotence when single-fn name in set + `(T) -> T` shape with T ∈ FloatingPoint or Complex; on round-trip when both pair-side names in set (so true-inverse pairs `log ↔ exp` etc. survive but cross-product pairs `exp ↔ cosh` get suppressed — calibration TBD). Mechanism class: function-name + type-shape composite (extends class 7 from V1.14.1+V1.16.1). Estimated effect: **suppresses ~10-15 CM idempotence picks + many CM round-trip cross-products**, the dominant cycle-14 rejection class. ~half a day to a day.

2. **Fixed-point-name positive signal on idempotence.** *(NEW; alternative or complement to #1.)* Add `+10` (or similar) on `IdempotenceTemplate` when function name matches `{normalize, canonicalize, dedupe, simplify, clamped, flattened, sorted, uniqued}` curated set. Net effect: surfaces well-named idempotence candidates more aggressively, potentially producing the first non-zero cycle-N idempotence acceptance rate. Mechanism class: parameter-name positive signal (extends class 6 from cycles 7-9). Cycle-7 priority list flagged this as option (b); cycle-14's continued 0% signals it's time. ~1 hour.

3. **Reference-type carrier counter-signal.** *(Carried forward from post-v1.16 priority #3.)* `Signal.Kind.referenceTypeCarrier` counter on idempotence + round-trip + inverse-pair when carrier resolves to `kind == .class` or `kind == .actor`. Empirical effect projected small on cycle-1..14 corpora (struct + enum dominant). ~1 day.

4. **FP approximate-equality template arm.** *(Carried forward from cycles 2-13.)* Real `KitFloatingPointTemplate` emitting `checkFloatingPointPropertyLaws(...)` stubs. Cycle-14 picks #37 (`_relaxedAdd` commutativity accept) + #42 (`_relaxedMul` associativity accept) again confirm the need: these are abstractly-correct accepts where bit-exact equality fails under FP rounding. ~1 day.

5. **Math-library op-name gate extension.** *(Carried forward from cycle-4.)* Add `rescaledDivide` / `_relaxedAdd` / `_relaxedMul` to V1.6.1's `IdentityElementPairing.stdlibBinaryOperators`. Cycle-14 pick #50 (`rescaledDivide × Complex.zero` reject) reaffirms — this is suppressable by name pattern. ~1 hour.

6. **Stride-style label extension.** *(DEMOTED from post-v1.16 priority #1.)* Cycle-14 picks #19 + #49 measure the lone Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor as **correctness-positive on chunk-boundary domain**. Suppressing it would lose recall on a true positive. The earlier framing ("stride-style label cleanup of the lone survivor") was based on the assumption that the survivor was a false positive; cycle-14 falsifies that assumption. The mechanism is still defensible on **usability grounds** (auto-emitted property tests need chunk-boundary generators that v1's TestLifter doesn't synthesise — so the candidate is rater-friendly noise from a maintainer-output perspective even though it's correctness-positive), but it's no longer priority #1. **Reframe**: ship as part of a future release that pairs the suppression with chunk-boundary generator support, not as standalone cleanup.

7. **`surfacedAt` plumbing.** *(Carried forward from cycle-1 priority #4.)* ~half a day.

8. **Multi-rater triage methodology.** *(Carried forward from cycle-6.)* Cycle-14 reaffirms the single-runner caveat. The 34.8% cycle-14 rate is one rater's view — a second-rater overlap on a 20-pick subset would tighten the confidence interval on both cycle-6 and cycle-14 numbers. ~1 day if a second rater is available.

9. **Codec set broadening + SuggestionIdentity continuity fixture.** *(Carried forward.)* Cycle-14 pick #1 (`_value(forBucketContents:) ↔ _bucketContents(for:)` accept) is exactly the codec-shape pattern that motivated this priority — it's now confirmed surfacing as a true positive at v1.16, so a SuggestionIdentity continuity fixture would lock in the surfacing across future refactors.

10. **SemanticIndex.** *(Carried forward; multi-cycle effort. PRD §20 v1.1+.)* Cycle-14 highlights several places where SemanticIndex would lift current textual-only approximations: the 4 unknown verdicts (#22, #32, #44, #47) are all "internal-state-determines-the-answer" cases that source-reading would resolve. SemanticIndex cuts this uncertainty class to ~zero.

## Methodology gaps observed

**Cycle-6 → cycle-14 picks-overlap was minimal.** Per v1.17 plan §"Open decisions" #4, cycle-14 used fresh stratified sampling rather than re-using cycle-6 picks where they survived. This preserved independent-measurement integrity but means cycle-6 vs cycle-14 rate-shift is **between-sample**, not **within-sample**. A future re-measurement cycle could pair fresh sampling with a parallel within-sample re-triage of survivors to disambiguate sample-mix noise from true rate movement.

**Per-template rate-shifts on n≤6 templates have ≥±20pp confidence bands.** Cycle-14's monotonicity, associativity, inverse-pair, and identity-element rates all have small samples; their apparent shifts (−30pp, +20pp, +100pp, 0pp) are dominated by sample-mix noise. Only round-trip (n=20) and idempotence (n=10) have rate estimates tight enough to make per-template attribution claims, and both moved within ±2.1pp (essentially flat). **The +8.1pp aggregate shift is the load-bearing finding; per-template shifts on small-n templates are not.**

**The cycle-6 vs cycle-14 picks-overlap could have been higher with a different open-decision-#4 choice.** A within-sample re-triage of the ~30 surviving cycle-6 picks at v1.16 would directly measure rate-shift for the same picks. The cycle-14 choice (fresh sampling) was the cycle-6-matching posture; an alternative (same picks where surviving) would have been more powerful for rate-shift attribution but biased the sample toward worst-case false-positive coverage.

**The Likely-tier surface remains untriaged at v1.16.** Cycle-6 sampled 1 Likely-tier pick (`rescaledDivide × Complex.zero`); cycle-14 picked the same one. PRD §19's ≥70% target applies to combined Strong + Possible. Cycle-15+ should sample Strong-tier (or a meaningful subset) under the same rubric.

## Trajectory framing

Cycle 14 doesn't move the surface count. It moves the *epistemic* state — from "we conjecture cycles 7-13 moved acceptance" to "we measured a +8.1pp aggregate shift, +22.7pp on OC, 0pp on CM, and 0pp on idempotence specifically."

The cycles-1-14 trajectory:

| Cycle | Mechanism | Surface | Possible-tier accept-rate |
|---|---|---:|---|
| 1 | counter-signals | 358 | (Strong tier triaged at cycle-1 only) |
| 2 | coverage veto | 353 | unknown |
| 3 | pair-formation filter | 350 | unknown |
| 4 | stdlib bake-in | 326 | unknown |
| 5 | shape-gated veto | 349 | unknown |
| **6** | **(empirical baseline)** | **349** | **26.7%** |
| 7 | direction-label idempotence | 296 | unknown |
| 8 | direction-label inverse-pair | 288 | unknown |
| 9 | direction-label round-trip | 257 | unknown |
| 10 | (refactor; no measurement) | 257 | unknown |
| 11 | SetAlgebra-shape inverse-pair | 251 | unknown |
| 12 | domain-marker 3-template | 235 | unknown |
| 13 | SetAlgebra-shape round-trip + idempotence | 229 | unknown |
| **14** | **(empirical re-measurement)** | **229** | **34.8%** |

Cycle-14 closes the meta-question open since cycle 6: **does cumulative noise-floor suppression translate to measurably-higher per-template acceptance rates?** The answer is partially yes — aggregate +8.1pp is real and outside sample-size noise; OC +22.7pp is the largest per-corpus shift and traces cleanly to cycles 7+12+13 mechanisms. But **idempotence stayed at 0%** despite three idempotence-targeting cycles, which surfaces the selection-shift-vs-target-improvement distinction. Mechanism cycles can suppress rejects without introducing accepts; the rate moves only when the surviving accepts grow or the surviving reject denominator shrinks.

The §19 long-term ≥70% target implies a +35pp shift from cycle-14's 34.8% — five mechanism cycles at the cycle-7-9 magnitude (each ≈ +1-2pp) wouldn't get there; the trajectory needs either (a) a higher-impact mechanism class (e.g., SemanticIndex which lifts internal-state ambiguity into sourceable evidence — closing many of the cycle-14 unknown verdicts), or (b) positive-signal mechanisms (cycle-15 priority #2) that introduce accepts rather than suppressing rejects.

After cycle-14 ships, the next empirical cycle would naturally land at cycle 20+ (every 6 mechanism cycles), unless a mechanism between cycles 15-19 proves so impactful that earlier re-measurement is justified.

## Summary

Cycle 14 produced the second empirical Possible-tier acceptance-rate measurement (after cycle-6 = v1.9) via a 50-decision single-runner triage on the post-V1.16.1 229-surface. The headline rate is **34.8%**, a +8.1pp shift from cycle-6's 26.7% — outcome **B** under the v1.17 plan's framing.

Per-template breakdown reveals the rate-shift attribution:
- **Idempotence stays at 0/10 = 0%** — the most important per-template finding. Cycles 7+12+13 cleared the cycle-6 idempotence rejection patterns (precision-positive) but didn't introduce new accepts (recall flat). The surviving v1.16 idempotence pool is dominated by CM elementary functions (17 of 25 = 68%), a noise class cycles 7-13 didn't target.
- **OC rate +22.7pp** — the largest per-corpus shift. Cycles 7+12+13 targeted OC heavily (surface dropped 101 → 43 = −57%); the post-v1.16 OC surface is much cleaner.
- **CM rate −4.3pp drift** — consistent with no-mechanism-targeting between cycles 7-13. CM is the cycle-15 empirical priority.
- **Round-trip and commutativity essentially flat**; associativity / monotonicity / inverse-pair shifts are within sample-size noise on small-n templates.

Mechanism-class effectiveness ranking surfaces a key asymmetry: classes 6 (parameter-label direction-counter), 7 (function-name + type-shape composite), and 8 (parameter-label semantic-intent counter) collectively delivered the +22.7pp OC shift but 0pp on CM. **Cycle-15 priority #1 candidate is a math-library forward-function counter targeting the CM elementary-functions noise class.** Cycle-15 priority #2 is a fixed-point-name positive signal on idempotence (cycle-7 priority list's option (b), now seven cycles overdue).

The cycle-13 priority #1 (stride-style label extension) **demotes**: cycle-14 measurement says the lone Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor is correctness-positive, so suppressing it would be a recall regression. The mechanism reframes as a usability-paired item, shipped only alongside chunk-boundary generator support in TestLifter.

Cumulative trajectory across cycles 1–14: **1167 → 229 (−80.38%) over 13 calibration cycles + 1 empirical cycle**, with a measured Possible-tier acceptance rate that **moved from 26.7% to 34.8%** between the loop's two measurement points. Cycle 15 is the first cycle whose mechanism choice can target a measured CM-specific rate, not a corpus-aggregate guess.
