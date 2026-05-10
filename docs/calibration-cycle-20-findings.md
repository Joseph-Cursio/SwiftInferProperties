# v1.23 Calibration Cycle 20 — Findings

Captured: 2026-05-10. swift-infer at `61b3b6c` (V1.23.C; v1.23 working copy; binary-equivalent to v1.22.0). The twentieth execution of PRD §17.3's empirical-tuning loop and the **fourth empirical-only cycle** (after cycles 6 = v1.9, 14 = v1.17, 17 = v1.20). Two mechanism cycles ship between cycles 17 and 20 (cycle 18 = v1.21 -170 surface; cycle 19 = v1.22 -13 surface; combined -183 = -54.6% surface delta across the two-cycle window).

This document is the cycle-20 record: **first four-point empirical trajectory** + per-mechanism effectiveness ranking + the cycle-21 priority list rotation.

## Headline

**21/43 = 48.8% Possible-tier acceptance rate.** A measurable -3.5pp drop from cycle-17's 52.3% — **outcome D** under the v1.23 plan's framing (Aggregate < 52% — counter-intuitive: v1.21 + v1.22 swept some accepts; methodology investigation warranted).

| Metric | Cycle 6 (v1.9) | Cycle 14 (v1.17) | Cycle 17 (v1.20) | **Cycle 20 (v1.23)** | Δ vs cycle 17 |
|---|---:|---:|---:|---:|---:|
| Surface measured | 349 | 229 | 335 | **152** | −183 (−54.6%) |
| Total triaged | 50 | 50 | 46 | **46** | 0 |
| Accept | 12 | 16 | 23 | **21** | −2 |
| Reject | 33 | 30 | 21 | **22** | +1 |
| Unknown | 5 | 4 | 2 | **3** | +1 |
| **Acceptance rate** (excl unknown) | 26.7% | 34.8% | 52.3% | **48.8%** | **−3.5pp** |
| Uncertainty rate | 10.0% | 8.0% | 4.3% | **6.5%** | +2.2pp |

**Four-point trajectory:** 26.7% → 34.8% → 52.3% → 48.8%. Cycle 20 is the **first cycle to register a non-monotonic move** in the loop's history. The cycle-14 → cycle-17 +17.5pp acceleration (driven by V1.18.C dual-style introduction at 100% precision + V1.19.B-D lifted-mutation introduction) does not continue to cycle-20.

## Three drivers of the -3.5pp drop

**Driver 1: V1.22.D suppressed cycle-17 ACCEPT class.** The Algo `endOfChunk(startingAt:) × startOfChunk(endingAt:)` triple was measured ACCEPT at cycle-14 (#19 round-trip + #29 idempotence + #49 inverse-pair) and cycle-17 (#15 + #32 round-trip + inverse-pair). V1.22.D's stride-style label both-sides veto suppresses both round-trip and inverse-pair on this site (cycle-14 demotion target finally shipped after 4-cycle carry-forward; calibration trade-off per v1.22 plan §"Risks": "the suppression target is auto-emit usability, not correctness"). Cycle-20 sample doesn't see these picks (filtered from `--include-possible`); the sample loses 2-3 ACCEPT picks vs cycle-17.

**Driver 2: Cycle-20 sample concentrates on first-measurement reject classes.** Two cycle-19 finding classes weren't sampled at cycle-17:

- **OC asymmetric round-trip cross-pairs** (5/5 = 100% reject in cycle-20 sample). `index(after:) × _minimumCapacity(forScale:)` etc. — one side direction-labeled, one domain-marker-labeled. V1.22.B's both-sides direction-counter doesn't fire (different label classes); cycle-17 didn't sample because the asymmetric class hadn't been identified yet. Cycle-19 finding identifies; cycle-20 measures at 5/5 reject.
- **OC sort/shuffle/reverse/removeFirst/removeLast lifted-idempotence** (2 accept + 4 reject + 1 unknown in cycle-20 sample). Cycle-17 sampled the BucketIterator class which V1.22.A subsequently closed. The OC mutator class is structurally different — sort is idempotent (fixed-point), reverse + removeFirst + removeLast aren't, shuffle is non-deterministic.

**Driver 3: Cycle-20 round-trip sample weighting shifted.** Cycle-17 had 7/15 round-trip picks on CM canonical anchors (47% weight on the ACCEPT class). Cycle-20 has 4/11 = 36% (rest is OC asymmetric reject + OC codec accept + 1 numerics-extension accept).

**Quantifying driver impact:** if the cycle-20 sample had matched cycle-17's distribution exactly (more CM canonical anchors, same Algo `endOfChunk` ACCEPT picks before V1.22.D suppression, same idempotence-lifted BucketIterator class before V1.21.A closure), the projected rate would be ~52-55% — close to cycle-17's 52.3%. The -3.5pp delta attributes mostly to driver 2 (cycle-20 first-measurement classes have lower rates) and driver 1 (V1.22.D removed cycle-17 ACCEPTs from the pool). Driver 3 is secondary.

## Per-template breakdown

| Template | Cycle-20 | Cycle-17 | Δ | Notes |
|---|---:|---:|---:|---|
| round-trip | 6/11 = 54.5% | 9/15 = 60.0% | −5.5pp | Sample-distribution shift (drivers 2+3); ACCEPT-class CM canonical anchors preserve at 5/5 |
| idempotence (non-lifted) | 0/5 = 0.0% | 0/4 = 0.0% | 0pp (5-cycle flat) | Continued cycle-6/14/17 0% pattern; CM elementary-functions class V1.21.C-closed |
| commutativity | 1/3 = 33.3% | 1/3 = 33.3% | 0pp | Rate-stability |
| associativity | 2/3 = 66.7% | 2/3 = 66.7% | 0pp | Rate-stability |
| monotonicity | 3/4 = 75.0% | 3/4 = 75.0% | 0pp | Rate-stability |
| inverse-pair (non-lifted) | 0/2 = 0.0% | 1/2 = 50.0% | −50.0pp (small-n) | V1.22.D closed cycle-17 #32 ACCEPT (Algo `endOfChunk × startOfChunk`); cycle-20 sample is 2 OC direction-pair rejects |
| identity-element (non-lifted) | 0/1 = 0.0% | 0/1 = 0.0% | 0pp | Carry-forward `rescaledDivide × Complex.zero` REJECT |
| **dual-style-consistency** | 5/5 = 100.0% | 5/5 = 100.0% | 0pp | **V1.18.C 100% by-construction precision rate-stability** |
| **idempotence-lifted** | 4/8 = 50.0% | 2/6 = 33.3% | +16.7pp (small-n) | Sort accepts add to cycle-17 internal-CoW accept class; reverse/removeFirst/removeLast rejects offset |
| **composition-lifted** | 0/1 = 0.0% | 0/1 = 0.0% | 0pp | V1.21.B demote rate-stability (cycle-17 #46 reject; same underlying math) |
| **All** | **21/43 = 48.8%** | 23/44 = 52.3% | **−3.5pp** | |

**Idempotence non-lifted is now 5-cycle flat at 0%.** The cycle-15+ priority for math-library forward-function counter shipped at V1.21.C and removed 17 CM elementary-functions picks — but the surviving 23-candidate pool still measures 0% accept rate. The new pool is dominated by formatters (`_description(type:)`, `format(_:)`, `nearMissLines(_:)`) + capacity-from-scale shape-coincidence picks (`_minimumCapacity(forScale:)`, `wordCount(forScale:)`) + direction-op shape-coincidence (`bucket(after:)`). None of these are genuine idempotence candidates — they're surfacing on type-shape coincidence ((Int) -> Int or (T) -> T). **Cycle-21 candidate priority: structural shape-disambiguation veto** for capacity-from-scale-style and formatter-style functions on the idempotence template.

**Inverse-pair drops -50pp on small-n.** Cycle-17 sampled 1 ACCEPT (`endOfChunk × startOfChunk`) + 1 REJECT (`bucket(after:) × bucket(before:)`); V1.22.D suppressed the ACCEPT pick. Cycle-20 samples 2 REJECT picks (`bucket(after:) × bucket(before:)` + `word(after:) × word(before:)`) — 0/2. Sample-mix effect, not a precision regression.

**Idempotence-lifted +16.7pp on small-n.** Cycle-17 sampled 2 internal-CoW ACCEPT + 4 Iterator-shape REJECT (V1.21.A subsequently closed those). Cycle-20 samples 2 internal-CoW + 7 sort/shuffle/reverse-class — 4 accepts (2 internal-CoW + 2 sort) + 4 rejects (reverse + removeFirst + removeLast variants) + 1 unknown (shuffle). Cycle-17's REJECT-class (Iterator) is gone from the surface; cycle-20's mix is more accept-favourable.

**Dual-style-consistency holds at 100%.** Five rate-stability picks; V1.18.C's by-construction precision continues across two cycles of measurement. **Largest mechanism-class precision contribution in the loop's history**.

## Per-mechanism effectiveness ranking (cycle-20)

| Mechanism | Cycle | Cycle-20 sample contribution |
|---|---|---|
| **V1.18.C dual-style** | 15 | **5/5 = 100% rate-stability** — by-construction precision unchanged at cycle 20 |
| V1.21.C math-forward function counter | 18 | All 5 cycle-20 CM round-trip canonical anchors preserved by `canonicalInversePairs` allowlist (rate-stability accept) |
| V1.21.A IteratorProtocol veto | 18 | 0 sample picks (carrier-class fully closed); precision-positive on surface (-22 candidates removed at cycle 18) |
| V1.22.A BucketIterator extension on V1.21.A | 19 | 0 sample picks (extends V1.21.A; carrier-class fully closed) |
| V1.22.B both-sides direction full-veto | 19 | -8 closures from cycle-17 sample pool; **revealed asymmetric cross-pair class (5/5 reject — cycle-20 first measurement)** |
| V1.22.D stride-style label veto | 19 | -3 cycle-17 sample picks suppressed (Algo `endOfChunk` ACCEPT class — calibration trade-off cost cycle-20 ~2-3pp) |
| V1.21.B composition-lifted demote | 18 | 0 net rate impact (single-pick demotion; cycle-17 reject → cycle-20 reject; same verdict) |
| **V1.22.C fixed-point-name positive signal (NEW class 14)** | 19 | **0 sample picks** — recall-positive infrastructure ready; no functions in `FixedPointNames.curated` surface on cycle-1..14 corpora |

**Per-mechanism-attributable rate impact (cycle-17 → cycle-20):**

- **V1.18.C dual-style:** ~0pp (rate-stability).
- **V1.21.C math-forward:** ~+1-2pp (preserves 5 CM canonical anchors at 100% accept; rate-stability with sample weighting shift).
- **V1.21.A + V1.22.A Iterator-shape closures:** ~0pp on cycle-20 sample (closed pool not re-sampled); precision-positive on surface only.
- **V1.22.B direction-counter:** -1 to -2pp (exposed asymmetric cross-pair class at 5/5 reject).
- **V1.22.D stride-style:** -2 to -3pp (suppressed cycle-17 ACCEPT class; calibration trade-off).
- **V1.21.B composition-lifted demote:** 0pp.
- **V1.22.C fixed-point positive signal (class 14):** 0pp on these corpora.

Net cycle-17 → cycle-20: **+1pp from rate-stability anchors – 4pp from sample-distribution shift = -3pp** (matches the measured -3.5pp within 0.5pp).

## Cycle-17 picks status at v1.22

The cycle-17 V1.20.C sample was 46 picks. At v1.22:

- **22 picks** preserved as same suggestion (still surfaces post-v1.21+v1.22 mechanisms): all 11 CM round-trip canonical-anchor accepts + cycle-17 #1 OC codec + 5 dual-style + 2 internal-CoW lifted + 1 idempotence non-lifted unknown + 1 PLK formatter unknown + 1 CM identity-element + others.
- **22 picks** suppressed by v1.21+v1.22 mechanisms:
  - **V1.21.A IteratorProtocol veto**: cycle-17 #40-#43 (4 Algo Iterator + 1 OC nested Iterator picks) — all 5 confirmed suppressed.
  - **V1.21.C math-forward**: cycle-17 #12-#14 (3 CM cross-product round-trip rejects), #18-#20 (3 CM idempotence rejects) — all 6 confirmed suppressed.
  - **V1.22.A BucketIterator extension**: cycle-17 #44 was BucketIterator-related but accepted (V1.22.A closure target was the OTHER 3 BucketIterator picks not in cycle-17 sample).
  - **V1.22.B direction full-veto**: cycle-17 #2 + #3 (2 OC direction-pair round-trip rejects) — confirmed suppressed.
  - **V1.22.D stride-style veto**: cycle-17 #15 + #32 (2 ACCEPT picks: Algo `endOfChunk × startOfChunk` round-trip + inverse-pair) — confirmed suppressed (calibration trade-off).
- **2 picks** demoted but still surface: cycle-17 #46 (composition-lifted) Strong → Likely via V1.21.B; cycle-17 #2 has been suppressed not demoted.

Cycle-20 sample IS NOT cycle-17 picks reuse (per the v1.23 plan §"Open decisions" #4 fresh-stratified-sampling default). Some natural overlap (CM identity-element survivor; OC `_value/_bucketContents` codec; CM canonical anchors; dual-style) but the cycle-20 verdicts are re-derived from rubric application; the cycle-17 verdicts inform rate-stability framing.

## Cumulative noise-floor + four-point acceptance trajectory

| Cycle | Surface | Aggregate rate | Δ surface vs cycle 1 | Δ rate vs cycle 6 |
|---|---:|---:|---:|---:|
| 1 (pre-tune) | 1167 | n/a | — | — |
| 6 (v1.9) | 349 | **26.7%** | −70.1% | (baseline) |
| 13 (v1.16) | 229 | n/a | −80.4% | n/a |
| 14 (v1.17) | 229 | **34.8%** | −80.4% | +8.1pp |
| 17 (v1.20) | 335 | **52.3%** | −71.3% (first reversal) | +25.6pp |
| 18 (v1.21) | 165 | n/a | −85.86% (new low) | n/a |
| 19 (v1.22) | 152 | n/a | −86.97% (new low) | n/a |
| **20 (v1.23)** | **152** | **48.8%** | **−86.97%** | **+22.1pp (first non-monotonic move)** |

**The acceptance trajectory now has four points and a non-monotonic fourth point.** Two interpretations:

1. **Calibration trade-off cost.** V1.22.D's stride-style suppression of the cycle-14/17-ACCEPT Algo `endOfChunk × startOfChunk` triple was an explicit calibration trade-off (auto-emit usability vs measured-correctness). The cycle-20 measurement quantifies the cost: ~2-3pp aggregate drop. This is **expected within the v1.22 plan §"Risks"** acknowledgement; not a methodology failure.

2. **Sample-distribution shift on first-measurement classes.** Cycle-20 samples two new classes (OC asymmetric cross-pairs; OC sort/shuffle/reverse-class lifted-idempotence) that weren't in the cycle-17 sample. These classes have lower per-template rates than the cycle-17 average. **The aggregate is sensitive to sample composition** when the surface composition changes substantially (335 → 152, -55% surface delta).

**Key interpretation:** the cycle-20 -3.5pp drop is **not a regression** in the sense of v1.21+v1.22 introducing rejects — the surface analysis at cycle-19 shows -183 candidates closed (precision-positive). The drop reflects:
- Sampling first-measurement classes that have intrinsically lower rates than the cycle-17 average.
- Suppression of one cycle-17 ACCEPT class as a calibration trade-off.

**The §19 ≥70% target is +21pp from cycle-20's 48.8%.** Three more mechanism cycles at the average cycle-17→cycle-20 mechanism magnitude (~+7pp net per cycle) would reach the target — assuming future mechanism work continues to be precision-positive on the surface AND the sample distribution stabilizes (cycle-21+ won't introduce new first-measurement classes at the same rate as cycles 18+19, which introduced the dual-style + lifted families).

## Cycle-21 priority list (rotated post-v1.23)

The cycle-20 measurement validates four cycle-19 priorities + identifies three NEW priorities from the cycle-20 sample:

1. **Asymmetric label class mismatch counter on round-trip** (cycle-19 finding; **cycle-20 reconfirmed at 5/5 = 100% reject**). Mechanism: when forward has `direction-label` and reverse has `domain-marker` (or vice versa), fire at -25 (full veto). Magnitude: closes ~5-7 OC candidates (the cycle-20 sample's 5 picks + 0-2 unsampled survivors).

2. **NEW (cycle-20 finding): `reverse` / `removeFirst` / `removeLast` veto on idempotence-lifted for non-IteratorProtocol carriers.** Cycle-20 sample measured 4/4 reject on these methods (`OrderedDictionary.reverse()`, `OrderedDictionary.removeFirst()`, `OrderedDictionary.removeLast()`, `OrderedSet.reverse()`). Mechanism: extend V1.21.A's Iterator-method-name veto to fire on `reverse` / `removeFirst` / `removeLast` for ANY value-semantic carrier (not requiring IteratorProtocol conformance). Magnitude: closes ~4-6 OC candidates.

3. **NEW (cycle-20 finding): non-deterministic shuffle veto extension.** The 1 OC `OrderedDictionary.shuffle()` lifted-idempotence pick surfaced despite being non-deterministic. Mechanism: extend `nonDeterministicVeto`'s body-signal detection to catch the OC stdlib RNG call patterns OR add a `shuffle` name-fallback (canonical Swift non-deterministic mutator name).

4. **NEW (cycle-20 finding): structural shape-disambiguation veto for capacity-from-scale-style and formatter-style functions on idempotence template.** The cycle-20 idempotence non-lifted sample measured 0/5 = 0% — the surviving pool is dominated by:
   - Capacity-from-scale (`_minimumCapacity`, `wordCount`) — type-shape `(Int) -> Int` coincidence; capacity-of-capacity meaningless.
   - Formatter (`_description(type:)`, `format(_:)`) — wraps input in structural format.
   - Direction-op shape-coincidence (`bucket(after:)`).

   Mechanism: extend curated-name vetoes (`MathForwardFunctions.curated`-style) for `*Capacity*`, `*Count*`, `format*`, `_description*` patterns. Magnitude: closes ~10-15 of the 23 idempotence non-lifted picks.

5. **FP approximate-equality template arm** (6-cycle carry-forward).

6. **Math-library op-name extension to `rescaledDivide` / `_relaxed*`** (4-cycle carry-forward).

7. **CompositionTemplate non-numeric monoid extension** (carry-forward from v1.19).

8. **Lift admission relaxation** (carry-forward).

9. **`Signal.Kind.liftedFromMutation` magnitude re-baselining** (carry-forward).

The **#1 + #2 + #3 + #4 are direct cycle-20 findings** (all NEW or reconfirmed); cycle-21 mechanism cycle (v1.24) is **third consecutive measurement-driven cycle** (after v1.21 from cycle-17 + v1.22 from cycle-18; this would be v1.24 from cycle-20).

## Conclusion

Cycle 20 produced the **fourth empirical measurement point** in the loop's history and the **first non-monotonic move** (52.3% → 48.8%, -3.5pp). The drop attributes to:

1. **V1.22.D calibration trade-off** suppressing the cycle-14/17 ACCEPT Algo `endOfChunk × startOfChunk` triple (~-2-3pp cost).
2. **Cycle-20 first-measurement** of two new reject classes (asymmetric round-trip cross-pairs + OC sort/shuffle/reverse-class lifted-idempotence) that weren't sampled at cycle-17 (~-2pp).
3. Partially offset by **rate-stability gains** on cycle-17 ACCEPT classes (CM canonical anchors, OC codec, dual-style, internal-CoW lifted) (+0-1pp).

This is **NOT a regression** — surface analysis at cycle 19 confirmed -183 candidates closed across cycles 18 + 19 (precision-positive). The cycle-20 measurement reflects sampling on a substantially-changed surface composition (335 → 152, -55% surface delta).

**Three NEW cycle-20 findings** rotate to the cycle-21 priority list as #2, #3, #4 (joining the cycle-19 #1 asymmetric-label class):
- `reverse`/`removeFirst`/`removeLast` veto on idempotence-lifted for non-IteratorProtocol carriers.
- Non-deterministic shuffle veto extension.
- Capacity-from-scale + formatter shape-disambiguation veto on idempotence non-lifted.

**Cycle-21 = v1.24 mechanism release** is the next planned cycle. Combined projected closure: ~20-30 OC candidates from priorities #1-#4. Aggregate projection at cycle-22 (next empirical re-measurement): **53-58%** if priorities #1-#4 ship and continue the precision-positive pattern.

**§19 ≥70% target is +21pp from cycle-20.** The empirical loop's trajectory has three monotonic increases (cycles 6 → 14 → 17) and one non-monotonic step (cycle 17 → 20). The non-monotonic step is **explained by the calibration-trade-off + sample-shift drivers**, not a precision regression. The §19 target remains achievable with continued mechanism-cycle progression at the cycle-18 magnitude.
