# v1.10 Calibration Cycle 7 — Findings

Captured: 2026-05-08. swift-infer at `9bff3a3` (V1.10.1 — direction-label counter-signal). The seventh execution of PRD §17.3's empirical-tuning loop and the **first cycle whose mechanism is empirically motivated** by a measured per-template rate from the prior cycle.

This document is the cycle-7 record: what we ran, what we learned, what shipped, what's deferred.

## Headline

**Cycle 7 shipped one structural rule: idempotence direction-label counter-signal.** V1.10.1 adds a `-15` weight on `IdempotenceTemplate` candidates whose first-parameter argument label is in a curated 10-element direction set (`{after, before, next, prev, previous, advance, succ, pred, successor, predecessor}`). The counter drops Score 30 (typeSymmetry alone) into Suppressed (< 20); curated-verb matches override (`+30 + 40 - 15 = +55` → Likely tier preserved).

| Tuning | Type | Where | Empirical effect |
|---|---|---|---|
| `IdempotenceTemplate.directionLabels` (V1.10.1) | scoring counter | first-param argument label | **−53 / −15.2% aggregate** (39 Algorithms + 14 OrderedCollections); 0 ComplexModule + 0 PropertyLawKit |

After v1.10: total `--include-possible` surface across the 4 corpora went **349 → 296** (−53, −15.2%). This is the **second-largest single-cycle suppression after cycle-1's structural counter-signals** (which dropped the surface 1167 → 358 in v1.4). The data-driven cycle-6 → cycle-7 motif worked exactly as predicted: cycle-6 measured idempotence at 0/10 acceptance; cycle-7 ships a counter-signal targeting the dominant rejection sub-pattern; cycle-7's empirical effect confirms the targeting.

## Cycle-6 → cycle-7 attribution loop closes

Cycle-6 was the calibration loop's first measurement; cycle-7 is the first response to that measurement. The loop demonstrates:

1. **Hypothesis (cycle 6, 0/10 idempotence rate):** type-symmetry alone over-fires on directional `(T) -> T` ops.
2. **Mechanism (cycle 7, V1.10.1):** add a counter-signal for the dominant direction-labeled sub-pattern.
3. **Measurement (this cycle, cycle 7):** −53 idempotence suppressions on the four corpora, distributed exactly where cycle-6 sampled the rejections (Algorithms + OrderedCollections; 0 elsewhere).
4. **Verification:** of the 10 cycle-6 idempotence-template rejections, V1.10.1 suppresses exactly the 5 direction-labeled ones (5 cycle-6 picks: #18, #19, #24, #26, #27). The other 5 stay surfaced because they're different cause-of-noise classes (domain-mismatch / Complex elementary-functions / PropertyLawKit `nearMissLines`).

This is the calibration loop *working as designed* per PRD §17.3 — cycles 1-5 were structural-rule cycles operating on conjecture; cycle 6 measured; cycle 7 closes the first feedback loop with a measurement-anchored fix.

## Corpus selection

Same four cycle-1+2+3+4+5+6 targets — re-running on the cycle-5 baseline (which is byte-identical to cycle-6's, since cycle-6 was empirical-only):

| Corpus | Target | Cycle-5/6 total | Cycle-7 total | Δ |
|---|---|---:|---:|---:|
| swift-numerics | ComplexModule | 166 | 166 | 0 |
| swift-collections | OrderedCollections | 101 | 87 | **−14** |
| swift-algorithms | Algorithms | 75 | 36 | **−39** |
| SwiftPropertyLaws | PropertyLawKit | 7 | 7 | 0 |
| **Total** | | **349** | **296** | **−53 (−15.2%)** |

Per-corpus pre/post snapshots committed to `docs/calibration-cycle-7-data/post-direction-counter-*.discover.txt`. Diff target is `docs/calibration-cycle-5-data/post-tightening-*.discover.txt`.

## What v1.10 ships (the mechanism)

Two pieces:

- **A new `Signal.Kind.directionLabel` enum case in `Sources/SwiftInferCore/Signal.swift`.** Added to the "Negative (non-veto)" group, mirroring `floatingPointStorage`'s posture. Documented inline with cycle-6 motivation.
- **`IdempotenceTemplate.directionLabels: Set<String>` curated set + `directionLabelCounterSignal(for:)` private helper in `Sources/SwiftInferTemplates/IdempotenceTemplate.swift`.** 10-element set covering Swift stdlib's standard direction conventions. Helper checks `summary.parameters.first?.label` membership; emits `-15` weight when matched. Wired into `IdempotenceTemplate.suggest(...)`'s signal-aggregation pipeline.

The mechanism reuses the existing Score / Tier machinery directly. No new template, no new generator path, no accept-flow changes. Other six templates (round-trip / commutativity / associativity / inverse-pair / monotonicity / identity-element) are byte-identical to v1.9.

## Per-corpus suppression breakdown

### swift-algorithms / Algorithms — the headline corpus

| Template | Cycle-5 | Cycle-7 | Δ |
|---|---:|---:|---:|
| **idempotence** | **44** | **5** | **−39** |
| round-trip | 20 | 20 | 0 |
| inverse-pair | 6 | 6 | 0 |
| monotonicity | 3 | 3 | 0 |
| commutativity | 1 | 1 | 0 |
| associativity | 1 | 1 | 0 |

39 of 44 idempotence claims suppressed — **88.6% of Algorithms idempotence surface eliminated**. The 39 suppressed are all `(Index) -> Index` / `(Base.Index) -> Base.Index` increment / decrement ops with `after:` or `before:` argument labels distributed across 11 source files. The 5 cycle-7 survivors are non-direction-labeled:
- `endOfChunk(startingAt:)` / `startOfChunk(endingAt:)` / `sizeOfChunk(offset:)` (Chunked) — `startingAt` / `endingAt` / `offset` ∉ direction set.
- `log(_:)` / `log(onePlus:)` (RandomSample) — `_` / `onePlus` ∉ direction set.

### swift-collections / OrderedCollections

| Template | Cycle-5 | Cycle-7 | Δ |
|---|---:|---:|---:|
| **idempotence** | **27** | **13** | **−14** |
| round-trip | 25 | 25 | 0 |
| monotonicity | 20 | 20 | 0 |
| commutativity | 10 | 10 | 0 |
| associativity | 10 | 10 | 0 |
| inverse-pair | 9 | 9 | 0 |

14 of 27 idempotence claims suppressed. The 14 are `index(after:)` / `index(before:)` / `bucket(after:)` / `bucket(before:)` / `word(after:)` / `word(before:)` from various source files. The 13 cycle-7 survivors are:
- 7× HashTable scale-vs-capacity functions (`minimumCapacity(forScale:)` / `maximumCapacity(forScale:)` / `scale(forCapacity:)` / `wordCount(forScale:)` plus `_` test-shim variants) — the cycle-6-documented domain-mismatch sub-pattern. **Cycle-8 priority candidate.**
- 4× Self-typed SetAlgebra ops (`intersection(_:)` ×2 + `subtracting(_:)` ×2) — `_` label not in direction set; could be a separate cycle-8+ candidate (Self-shape SetAlgebra ops on collections aren't naturally idempotent).
- 2× `_description(type:)`, `firstOccupiedBucketInChain(with:)` — non-direction-labeled.

### swift-numerics / ComplexModule

| Template | Cycle-5 | Cycle-7 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 166 | 166 | 0 |

ComplexModule's 17 idempotence claims are on Complex elementary functions (`exp(_:)`, `log(_:)`, `cosh(_:)`, etc.) with `_` parameter labels — none in the direction set. Byte-identical to cycle-5. V1.10.1 has nothing to suppress on this corpus.

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-5 | Cycle-7 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 7 | 7 | 0 |

PLK's 1 idempotence claim is `nearMissLines(_:)` — `_` label not in direction set. Byte-identical.

## Trajectory across all 7 cycles

| Cycle | Mechanism | Surface | Δ from prior | Cumulative Δ |
|---|---|---:|---:|---:|
| 1 (pre-tune) | none | 1167 | — | — |
| 1 (post-tune V1.4.3) | FP-storage + cross-type counter-signals | 358 | −809 | −69.3% |
| 2 (V1.5.2) | textual-only protocol-coverage suppression | 353 | −5 | −69.7% |
| 3 (V1.6.1) | identity-element pair-formation skip-list | 350 | −3 | −70.0% |
| 4 (V1.7.1) | stdlib-conformance bake-in | 326 | −24 | −72.1% |
| 5 (V1.8.1) | shape-gated Codable veto on round-trip | 349 | +23 | −70.1% |
| 6 (empirical-only) | (no surface change; baseline measured) | 349 | 0 | −70.1% |
| **7 (V1.10.1)** | **idempotence direction-label counter** | **296** | **−53** | **−74.6%** |

**−74.6% cumulative reduction** with seven structural mechanisms (V1.4.3 cross-type / FP-storage counter-signals, V1.5.2 coverage veto, V1.6.1 pair-formation filter, V1.7.1 stdlib bake-in, V1.8.1 shape-gated round-trip veto, V1.10.1 direction-label counter). All seven are *compositional* — none undo any other; each targets a structurally distinct cause-of-noise class.

## What v1.10 demonstrates

**The empirical loop closed for the first time.** The cycle-6 0/10 idempotence rate produced a hypothesis (`(T) -> T` directional ops over-fire); v1.10 produced the targeted mechanism; cycle-7 confirms the mechanism's empirical effect lands exactly where the hypothesis predicted (39 Algo + 14 OC = 53 suppressions on idempotence; 0 on other templates / corpora).

**The −53 / −15.2% effect size exceeds projection.** The v1.10 plan estimated `Algo idempotence drops by ~16, OC idempotence drops by ~5` — actual outcome is `Algo −39, OC −14`. The under-estimation comes from:
- I projected based on "the cycle-6 sampled rejections" which were 5 of 10 (50% of the sample). The full Algorithms surface had 44 idempotence claims; the cycle-6 sample of 4 from Algo represents ~9% of the per-corpus surface. Direction-labeled claims on Algorithms turn out to be 39/44 (88.6%) — much denser than the cycle-6 sample suggested.
- OC's HashTable + Index direction-labeled surface is also denser than the cycle-6 sample suggested.

This is informative: *cycle-6 sampling was a 50-decision sample of 349, ~14% of the surface*. The per-corpus density of any particular noise pattern can be considerably higher than the global sample shows. Cycle-8 sampling should account for this.

**Curated-verb override worked.** No idempotence suggestions named with curated verbs (`normalize`, `canonicalize`, `trim`, `flatten`, `sort`, `deduplicate`, `sanitize`, `format`) were collateral-damaged in cycle-7 — the test suite covers the override behavior, and the cycle-7 capture didn't surface any incorrectly-suppressed verb-named ops.

## Plan-vs-actual

The v1.10 plan f-bullet predicted:
> Expected: Algo idempotence drops by ~16 (most of the 44 are `index(after:) / index(before:)`); OC idempotence drops by ~5; ComplexModule + PropertyLawKit unchanged (no direction labels).

**Actual outcome:**
- Algo idempotence: 44 → 5 (−39). Expected ~16; **actual 2.4× larger.**
- OC idempotence: 27 → 13 (−14). Expected ~5; **actual ~2.8× larger.**
- ComplexModule: 166 → 166 (0). Expected unchanged. ✓
- PropertyLawKit: 7 → 7 (0). Expected unchanged. ✓

The empirical effect was **larger** than projected on the affected corpora. Methodology lesson for cycle-8 plans: when projecting from a small sample, account for per-corpus density variation. Cycle-7's outcome direction (Algo + OC dominate, CM + PLK untouched) was correct; the magnitude was 2-3× larger than the back-of-envelope estimate.

## Methodology gaps observed

**Cycle-6 sampling underrepresented direction-labeled density.** The cycle-6 stratified sample picked 4 idempotence claims from Algo and 4 from OC; the *actual* per-corpus density of the direction-labeled pattern was 88.6% (Algo) and 51.9% (OC). Future sampling cycles should include a "first-N from each per-corpus per-template cluster" pass to detect concentrations.

**Curated direction-label set is closed.** v1.10 fixed `directionLabels` at 10 entries. Cycle-8+ may discover additional direction-conventions (`forward`, `backward`, `clockwise`, etc. — unlikely in stdlib but possible in domain-specific corpora). Adding entries is mechanical (one-line changes); the count test pins the size for forensic-traceability.

**Domain-mismatch sub-pattern still pending.** 7 of OC's 13 surviving idempotence are HashTable `forScale` / `forCapacity` cross-product. Cycle-8 priority candidate: detect functions where parameter-name and return-context-name disagree semantically (`scale → capacity` ≠ same domain). Requires a different mechanism than direction labels.

**The 5 cycle-6 unknowns weren't re-classified.** ID #13, #16, #23, #44 are still unknown; cycle-8 has them as carryover.

**Possible-tier acceptance rate not re-measured at v1.10.** Cycle-7 didn't re-sample. The cycle-6 0/10 idempotence rate is now stale — V1.10.1 raises the bar by suppressing 5 of those 10 rejected, so the effective Possible-tier idempotence acceptance rate at v1.10 is `0 / 5 = 0%` *of what survives*, but the surface itself has shrunk. Cycle-8 priority candidate: re-sample post-V1.10.1 idempotence (now 36 across 4 corpora) and re-measure.

## Cycle-8 priority list (in expected impact order)

1. **Inverse-pair direction-label counter-signal.** *(NEW priority #1 from cycle-7; was cycle-6 priority #2.)* Cycle-6 measured inverse-pair at 0/5 = 0% acceptance. Same shape as v1.10's idempotence work but on the pair `(T, T) -> T` and `(T, T) -> T` shape. Counter-signal on first-param label of either side. ~half a day. Likely effect: −20 to −40 surface drops on Algo + OC inverse-pair surface (15 total cycle-7 surface; expect several to suppress).
2. **Round-trip direction-label counter-signal.** *(NEW priority #2 from cycle-7; was cycle-6 priority #5.)* Apply the same direction-label pattern to `RoundTripTemplate`. Round-trip Possible-tier surface is still ~181 across the 4 corpora; many `(Index) -> Index ↔ (Index) -> Index` pairs exist (e.g., `index(after:) ↔ index(before:)`). Expected: 30-50 round-trip suppressions across the 4 corpora.
3. **Domain-mismatch detection on idempotence.** *(NEW priority #3 from cycle-7; was cycle-6 priority "remaining 3-of-10" carryover.)* The 7 OC HashTable scale-vs-capacity surviving idempotence claims need a different mechanism — semantic intent inference on parameter labels (`forScale` vs return context). Likely a new `Signal.Kind.domainMismatchLabel` with curated mapping pairs (`forScale / capacity`, `forCapacity / scale`, `byteCount / wordCount`, etc.). ~1 day; cycle-9 candidate if cycle-8 doesn't fit.
4. **FP approximate-equality template arm.** *(Carried forward from cycles 2-7 priority #2/#3.)* Real `KitFloatingPointTemplate`. ~1 day.
5. **Math-library op-name gate extension.** *(Carried forward from cycle-4 priority #5.)* `rescaledDivide` / `_relaxedAdd` / `_relaxedMul` to V1.6.1's stdlib operator gate. ~1 hour.
6. **Possible-tier re-sampling on the post-v1.10 surface (296 across 4 corpora).** *(NEW priority #6 from cycle-7.)* Now that V1.10.1's noise-floor reduction confirms the cycle-6 hypothesis, re-running the rubric on a fresh 50-decision sample should produce a measurably higher acceptance rate. ~half a day.
7. **`surfacedAt` plumbing.** *(Carried forward from cycle-1 priority #4.)*
8. **Multi-rater triage methodology.** *(Carried forward from cycle-6.)*
9. **Codec set broadening + SuggestionIdentity continuity fixture.** *(Carried forward.)*
10. **SemanticIndex.** *(Carried forward; multi-cycle effort.)*

## Summary

Cycle 7 shipped one structural rule: an idempotence direction-label counter-signal (V1.10.1). The empirical effect was −53 of 349 surfaced suggestions (−15.2% aggregate) — second-largest single-cycle suppression after cycle-1's structural counter-signals. All −53 suppressions are on the idempotence template; 39 on Algorithms, 14 on OrderedCollections, 0 on ComplexModule + PropertyLawKit (no direction labels in those corpora's idempotence surfaces).

The cycle-6 → cycle-7 attribution loop closed cleanly: cycle-6 measured 0/10 idempotence acceptance, surfaced direction-labeled `(T) -> T` ops as the dominant rejection sub-pattern; cycle-7's V1.10.1 targets that pattern with a counter-signal; cycle-7's empirical capture confirms the targeting. The five cycle-6 picks that V1.10.1 was designed to suppress (5 of 10 idempotence rejects with `after:` / `before:` labels) all suppress correctly. The 5 cycle-6 picks that V1.10.1 doesn't address (3× domain-mismatch + 2× Complex paramless) correctly stay surfaced — they're different cause-of-noise classes.

Cumulative trajectory across cycles 1–7: **1167 → 296 (−74.6%)** with seven compositional mechanisms. Cycle 8's priority list is now data-anchored on cycle-6's measurements *plus* cycle-7's verification — particularly the inverse-pair (0/5) and round-trip-on-`(Index) -> Index` patterns that benefit from the same direction-label-counter mechanism extended to other templates.
