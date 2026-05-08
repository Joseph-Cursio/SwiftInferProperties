# v1.9 Calibration Cycle 6 — Findings

Captured: 2026-05-08. swift-infer at `d006deb` (v1.8.0 release tag). The sixth execution of PRD §17.3's empirical-tuning loop and the **first cycle to produce empirical Possible-tier acceptance-rate data** rather than infer it from suppression deltas.

This document is the cycle-6 record: what we ran, what we learned, what shipped, what's deferred. Cycle 7 reads this to decide where to perturb next, with *data* this time — five prior cycles operated on conjecture about per-template false-positive rates.

## Headline

**Cycle 6 shipped no structural rules — only empirical data.** A single-runner triage of 50 stratified samples from the 349-surface yields the first measured per-template Possible-tier acceptance rate.

| Metric | Value |
|---|---:|
| Total triaged | 50 |
| Accept | 12 |
| Reject | 33 |
| Unknown | 5 |
| **Acceptance rate** (accept / (accept + reject)) | **26.7%** |
| Uncertainty rate (unknown / total) | 10.0% |

**26.7% Possible-tier acceptance rate is the headline number.** Far below PRD §19's ≥70% long-term target — but the §19 target applies to the *entire* surface (Strong-tier + Possible-tier weighted), not Possible-tier alone. Possible-tier is by-design the noisier, lower-confidence band; cycles 1-5's structural rules suppress higher-confidence false positives. The 26.7% rate gives cycle-7+ a quantitative starting point for scoring weight tuning rather than the conjecture-only guidance prior cycles relied on.

## Caveat scope: single-runner triage

This data is one rater's view (Claude), based on:
- Public API + commit history evidence only.
- No test execution, no internal-implementation reading beyond public surfaces.
- No multi-rater consensus.

The rubric ([`cycle-6-triage-rubric.md`](cycle-6-triage-rubric.md)) explicitly mandates `unknown` for ambiguous cases rather than forced binary calls; 5 of 50 (10.0%) decisions are `unknown` because the rater couldn't determine without internal-source reading.

Multi-rater triage and automated property-test verification of the accept-decisions are the natural next-cycle methodology improvements.

## Per-template breakdown

| Template | Sample | Accept | Reject | Unknown | Rate (excl unknowns) |
|---|---:|---:|---:|---:|---:|
| round-trip | 16 | 6 | 8 | 2 | 6/14 = **42.9%** |
| idempotence | 12 | 0 | 10 | 2 | 0/10 = **0.0%** |
| commutativity | 5 | 1 | 4 | 0 | 1/5 = **20.0%** |
| associativity | 5 | 2 | 3 | 0 | 2/5 = **40.0%** |
| monotonicity | 6 | 4 | 1 | 1 | 4/5 = **80.0%** |
| inverse-pair | 5 | 0 | 5 | 0 | 0/5 = **0.0%** |
| identity-element | 1 | 0 | 1 | 0 | 0/1 = **0.0%** |
| **All** | **50** | **12** | **33** | **5** | **12/45 = 26.7%** |

### Key per-template observations

**Idempotence (0/10): zero acceptance.** All 10 of the rejected idempotence claims are `(T) -> T` shapes where `T` is an Int / Index family; the function is a *direction* (next, after, scale-to-capacity, etc.), not a fixed-point. The Score 30 type-symmetry signal fires unconditionally on any `(T) -> T` signature, which over-surfaces direction-style operations as idempotence candidates. This is the **strongest scoring-weight tuning signal in cycle-6**: type-symmetry alone is too permissive for idempotence.

**Inverse-pair (0/5): zero acceptance.** The OC SetAlgebra-shaped pairs (intersection / subtracting / etc.) and Algo Index ops (offsetBy / distance) all reject — these are *related* binary ops, not strict inverses. Type-symmetry `(T, T) -> T` × 2 is again the only signal, and it doesn't capture the inverse-pair semantic.

**Monotonicity (4/5 = 80%): highest acceptance.** The four OC HashTable functions (`minimumCapacity` / `maximumCapacity` / `scale` / `walkCap`) are genuinely monotonic by construction. The PLK `format` reject is correct (String lex order ≠ enum semantic order). Monotonicity's `+25` ordered-codomain signal appears to be calibrated tightly enough that surfacing happens almost only when the property actually holds.

**Round-trip (6/14 = 42.9%): mixed.** The Collection-protocol `index(after:) ↔ index(before:)` pairs (4 of the accepts) are textbook inverses. The 2 ComplexModule transcendental-pair accepts (log/exp, sin/asin) hold on principal-branch domains. The 8 rejects are mostly:
- HashTable `(Int) -> Int` cross-products (OC #1-3): the cycle-5 V1.7.1-re-emergence cases — V1.8.1 correctly handed them back, and the rater correctly rejects them. **The shape-gated veto worked as designed.**
- Cross-product elementary-functions noise on Complex (CM #7-10): unrelated forward-direction pairs.

**Commutativity (1/5 = 20%) + Associativity (2/5 = 40%).** Both rates are dragged down by the OC `index(_:offsetBy:)` / `distance(from:to:)` Int-op pairs which are directional. The CM `_relaxedAdd` / `_relaxedMul` family accepts at the abstract math level (commutativity / associativity hold modulo FP rounding) — correctly identified as cycle-7 FP-template-arm targets.

**Identity-element (0/1).** Single sample, the cycle-5 ComplexModule `rescaledDivide × Complex.zero` Score 70 Likely-tier pick. Cycle-7 priority candidate: extend V1.6.1's curated math-library op-name gate to include `rescaledDivide` (and likely the `_relaxed*` family).

## Per-corpus breakdown

| Corpus | Sample | Accept | Reject | Unknown | Rate |
|---|---:|---:|---:|---:|---:|
| OC | 22 | 6 | 16 | 0 | 6/22 = 27.3% |
| CM | 15 | 4 | 7 | 4 | 4/11 = 36.4% |
| Algo | 10 | 2 | 7 | 1 | 2/9 = 22.2% |
| PLK | 3 | 1 | 1 | 1 | 1/2 = 50.0% |

CM has the highest uncertainty (4/15 = 27%) — Complex transcendental-function pair semantics are domain-expert territory; without principal-branch knowledge, several pairs flagged unknown rather than forced-rejected.

OC's 27.3% rate is dominated by the V1.7.1-re-emergence rejection pattern (the shape gate works; the surface still has noise from non-Codable-shape duplicates).

## What v1.9 ships (the data)

Three artifacts:
- **[`cycle-6-triage-rubric.md`](cycle-6-triage-rubric.md)** — methodology document defining accept/reject/unknown per template.
- **[`calibration-cycle-6-data/sample-manifest.md`](calibration-cycle-6-data/sample-manifest.md)** — 50 picks stratified by template × corpus.
- **[`calibration-cycle-6-data/triage-decisions.json`](calibration-cycle-6-data/triage-decisions.json)** + **[`calibration-cycle-6-data/triage-notes.md`](calibration-cycle-6-data/triage-notes.md)** — per-decision verdict + rationale.

No code changes; no test changes; no §13 budget changes. v1.9 is binary-equivalent to v1.8.

## Cycle-7 priority list (data-driven, in expected impact order)

The first cycle whose priority list is anchored in measurement, not conjecture:

1. **Idempotence template `(T) -> T` weight tightening.** *(NEW priority #1; surfaced by cycle-6 0/10 rate.)* The strongest scoring signal: 0% Possible-tier acceptance on idempotence. The `+30` `typeSymmetrySignature` on `(T) -> T` over-surfaces directional ops (`index(after:)`, `bucket(after:)`, etc.). Two options:
   - (a) Add a counter-signal `-15` (or similar) for functions whose name matches a curated *direction-pattern* set: `{after, before, next, prev, advance, succ, pred}`. Idempotence type-symmetry stays at +30, but direction names drop the score below the Possible threshold (effective threshold drops from 30 to 15). Estimated effect: most of the OC + Algo idempotence rejections suppress.
   - (b) Add a positive-signal `+10` when the function name suggests fixed-point (`normalize`, `canonicalize`, `dedupe`, `simplify`, `clamped`, `flattened`). Net effect: only well-named idempotence candidates surface above the threshold.
   - Recommendation: **(a) is more conservative.** Cycle-7 ships (a); cycle-8+ can add (b) on top if the surface still has noise after (a).

2. **Inverse-pair template tightening.** *(NEW priority #2; surfaced by cycle-6 0/5 rate.)* Similar shape to idempotence: type symmetry over-fires on related-but-not-inverse ops. The fix is structurally similar to (1) but on the pair shape — counter-signals for direction names + positive signals for explicit inverse-pair-named patterns. ~half a day.

3. **FP approximate-equality template arm.** *(Carried forward from cycles 2-5 priority #2.)* Cycle-6 confirms: Complex `_relaxedAdd` / `_relaxedMul` accept at abstract math level but FP-exact equality fails. A `KitFloatingPointTemplate` emitting `checkFloatingPointPropertyLaws(for: T.self, using: gen)` stubs converts these correctly. Cycle-6 sample #33 + #38 are the textbook example. ~1 day.

4. **Math-library op-name gate extension to user-named ops.** *(Carried forward from cycle-4 priority #5; sharpened by cycle-6 #50.)* Add `rescaledDivide` (and likely `_relaxedAdd` / `_relaxedMul` / `_relaxed*`) to V1.6.1's `IdentityElementPairing.stdlibBinaryOperators`. ~1 hour.

5. **Round-trip template `(Int) -> Int` weight tightening.** *(NEW; sharpened by cycle-6 round-trip OC rejects.)* Even with V1.8.1's shape gate, `(T) -> T` round-trip pairs on stdlib-typed carriers surface heavily and reject at high rates. A counter-signal on direction-named `(T) -> T` round-trip pairs (similar to idempotence priority #1) would suppress most HashTable-style noise. ~half a day.

6. **`surfacedAt` plumbing.** *(Carried forward from cycle-1 priority #4.)* Now the cycle-6 acceptance-rate baseline exists, time-to-adoption metrics will mean something. ~half a day.

7. **Multi-rater triage methodology.** *(NEW from cycle-6 single-runner caveat.)* The 26.7% acceptance rate is one rater's view. Cycle-7+ should run a small multi-rater experiment (rater agreement on a 20-decision overlap sample) to surface the rater-variance noise floor. ~1 day if a second rater is available.

8. **Codec set broadening.** *(Carried forward from cycle-5 priority #5; cycle-6 surfaced no `[UInt8]` examples in the sampled subset.)* Defer to a future cycle if a corpus example surfaces.

9. **SuggestionIdentity continuity verification fixture.** *(Carried forward from cycle-5 priority #6.)*

10. **SemanticIndex.** *(Carried forward; multi-cycle effort. PRD §20 v1.1+.)*

## Methodology gaps observed

**Single-runner triage is the most acute methodology gap.** 50 decisions × 1 rater is a small sample; rater-variance is unknown. Multi-rater would tighten the 26.7% confidence interval.

**Some `unknown` flags are recoverable with more time.** ID #13, #16, #23, #44 could likely be re-classified with a few minutes per case of source reading. Cycle-7 may want to budget a follow-up pass to convert unknowns into accept/reject if the rater can re-engage.

**ComplexModule transcendental functions need domain-expert review.** Several CM accepts (log/exp, sin/asin) carry "principal-branch" caveats that a numerical-mathematician rater would qualify more sharply. Cycle-7+ may want to consult swift-numerics maintainers.

**Strong-tier was not sampled.** PRD §19's 70% target applies to combined Strong + Possible. Cycle-1 already triaged Strong-tier; the cycle-6 sample focused on the noisier Possible band. Cycle-7+ should sample Strong-tier under the same rubric to get a comparable rate.

## Trajectory framing

Cycle 6 doesn't move the surface count. It moves the *epistemic* state: from "we conjecture cycle-N's structural change reduces noise" to "we measured the residual noise-rate at 73.3% reject + 10% unknown after five structural cycles."

The cycles-1-5 trajectory:

| Cycle | Mechanism | Surface | Possible-tier accept-rate |
|---|---|---:|---|
| 1 | counter-signals | 358 | (Strong tier triaged at cycle-1 only — Possible unknown) |
| 2 | coverage veto | 353 | unknown |
| 3 | pair-formation filter | 350 | unknown |
| 4 | stdlib bake-in | 326 | unknown |
| 5 | shape-gated veto | 349 | unknown |
| **6** | **(empirical baseline)** | **349** | **26.7%** |

After cycle-6, every prior cycle's hypothesis ("X mechanism removes Y false positives") has a measurable test ground for the first time. Cycle-7's priority #1 is data-derived ("idempotence rejects at 0/10, suggests counter-signal on direction names"), not conjectural ("we suspect idempotence weights are off").

## Summary

Cycle 6 produced empirical Possible-tier acceptance-rate data via a 50-decision single-runner triage. The headline rate is **26.7%** — far below PRD §19's combined ≥70% target but a starting baseline for the *Possible-tier band specifically*. Per-template breakdown reveals strong patterns:
- **Idempotence rejects 100%** of sampled `(T) -> T` directional ops — the strongest scoring-tuning signal in the cycle.
- **Inverse-pair rejects 100%** of sampled SetAlgebra/Index ops — same shape.
- **Monotonicity accepts 80%** — calibrated tightly.
- **Round-trip accepts 43%** — V1.8.1's shape gate works but `(Int) -> Int` directional surface remains.

Cycle 7's priority list is data-driven for the first time: idempotence direction-name counter-signal + inverse-pair tightening + FP template arm + math-library op extension + round-trip directional counter-signal. The five prior cycles' conjectural priority lists become testable once cycle-7+ ships changes against this baseline.

The cumulative trajectory across cycles 1-6: surface 1167 → 349 (−70.1%) AND a measured Possible-tier rate of 26.7%. Cycle 7's structural changes will be the first to *target* a measurable rate-improvement.
