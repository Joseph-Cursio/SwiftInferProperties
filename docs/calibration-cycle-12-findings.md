# Calibration Cycle 12 Findings — v1.15 (post-v1.14)

**Cycle 12 = v1.15.** Twelfth execution of PRD §17.3's empirical-tuning loop. **Fifth data-driven cycle** (after cycles 7-9 + 11; cycle 10 was the v1.13 hoist refactor with no measurement). v1.15 closes post-v1.14 priority #1 (domain-mismatch family on idempotence + inverse-pair + round-trip simultaneously) and is the **first cycle to ship a single mechanism applied to three templates simultaneously** — compresses cycles 7-9's three-release direction-counter cadence into a single release.

Captured: 2026-05-09. swift-infer at `eb92975` (V1.15.1 — domain-marker counter on three templates).

## Headline

**Aggregate 251 → 235 (−16, −6.4%) — third consecutive plan-vs-actual exact match.**

Per-corpus delta:
- swift-collections / OrderedCollections: 65 → 49 (**−16**)
- swift-numerics / ComplexModule: 166 → 166 (0; byte-identical)
- swift-algorithms / Algorithms: 13 → 13 (0; byte-identical)
- SwiftPropertyLaws / PropertyLawKit: 7 → 7 (0; byte-identical)

Per-template suppression (all on OC):
- **OC round-trip 12 → 3 (−9)** — both-sides domain-marker pairs.
- **OC idempotence 13 → 6 (−7)** — single-function domain-marker labels.
- OC inverse-pair: no candidates (V1.14.1 already cleared all pre-cycle-11 candidates).

Cumulative across cycles 1-12: **1167 → 235 (−79.86%)** — narrow miss on the V1.15.0 plan's "first cycle to cross 80%" framing (overoptimistic by 0.14 percentage points; needed ≤ 233 to cross). Cycle-13 will cross unambiguously.

## Cycle-12 mechanism class: parameter-label counter (semantic-intent variant)

V1.15.1 ships one structural rule deployed across three templates simultaneously: a `domainMarkerCounterSignal(for:)` extension method on each of `IdempotenceTemplate`, `RoundTripTemplate`, and `InversePairTemplate`. All three consume `SwiftInferCore.DomainMarkerLabels.curated = {forScale, forCapacity, forBucketContents}` and emit a `-15` weight signal on the existing `Signal.Kind.directionLabel` case.

**Why it's a new mechanism class.** Cycles 7-9's direction-label counter family (`DirectionLabels.curated = {after, before, next, prev, ...}`) targeted *spatial-sequence iteration* labels — positional anchors in an ordered space. v1.15's domain-marker counter targets *semantic-intent* labels — named-domain markers (scale-domain, capacity-domain, bucket-contents-domain). The two label sets are textually disjoint by intent; they fire on structurally different cause-of-noise patterns even though both consume the same `Signal.Kind` case.

**Why all three templates fire on the same set.** The semantic argument "any function with parameter label `forScale:` produces output in a *different* domain than its input" applies uniformly:
- **Idempotence**: `f(f(x))` requires `f`'s output to match `f`'s input domain; `forScale:` declares scale-domain input but typed-Int output is semantically capacity/wordCount domain.
- **Round-trip with both sides labeled**: each side crosses domains; the round-trip property requires `reverse(forward(x)) = x`, but cross-domain functions form chains, not inverses.
- **Inverse-pair (defensive scaffold)**: same cross-domain-chain argument; no current candidates on cycle-1...11 corpora but wired for symmetry + future-proofing.

**First cycle to compress three-template deployment into one release.** Cycles 7-9 deployed the direction-label counter family across three releases: V1.10.1 introduced the mechanism on idempotence, V1.11.1 replicated on inverse-pair, V1.12.1 completed the family on round-trip. v1.15.1 deploys the analogous semantic-intent counter on all three templates in a single commit. The compression is justified because:
1. The mechanism is uniform across templates (same curated set, same weight, same first-param-label check).
2. The cycles 7-9 pattern established the per-template integration shape.
3. The v1.13 hoist precedent removes the cross-template-reach-during-introduction concern.

## Corpus selection

Same four cycle-1..11 corpora at the V1.15.1 commit. No new corpora added; the priority is depth on existing corpora (V1.15.1 targets a specific OC HashTable noise pattern).

## What v1.15 ships (the mechanism)

| File | Role |
|---|---|
| `Sources/SwiftInferCore/DomainMarkerLabels.swift` | Curated 3-element semantic-intent set, `public enum DomainMarkerLabels { public static let curated: Set<String> }`. Canonical-from-cycle-1 per the V1.13.1 + V1.14.1 precedents. |
| `Sources/SwiftInferTemplates/IdempotenceDomainMarkerCounter.swift` | Single-function detection (mirrors V1.10.1 shape). Weight `-15`. |
| `Sources/SwiftInferTemplates/RoundTripDomainMarkerCounter.swift` | Both-sides detection (V1.15.0 open decision #2 default). Weight `-15`. |
| `Sources/SwiftInferTemplates/InversePairDomainMarkerCounter.swift` | Both-sides detection (defensive scaffold). Weight `-15`. |

**Detection-mode asymmetry.** Idempotence is single-function (no pair). The two pair templates use **both-sides** detection per V1.15.0 plan open decision #2 — the asymmetric `_value(forBucketContents:) ↔ _bucketContents(for:)` candidate is preserved as a likely true-positive round-trip pair (`for:` is the unlabeled-domain "given X" carrier; only the forward side has the explicit semantic-intent marker). Either-side detection would have suppressed it for −1 net aggregate gain.

**Score arithmetic.** Uniform `-15` weight across all three templates per V1.15.0 plan open decision #1:
- Round-trip / idempotence (baseline `+30`): bare → `+15` Suppressed; with curated verb (`+40`) → `+55` Likely (preserved).
- Inverse-pair (baseline `+25`): bare → `+10` Suppressed; with curated name (`+10`) → `+20` boundary-Possible.

The inverse-pair boundary case is unlikely to fire in practice — curated names like `parse/format` don't coincide with HashTable domain labels.

## Per-corpus suppression breakdown

### swift-collections / OrderedCollections

| Template | Cycle-11 | Cycle-12 | Δ |
|---|---:|---:|---:|
| **round-trip** | **12** | **3** | **−9** |
| **idempotence** | **13** | **6** | **−7** |
| inverse-pair | 0 | 0 | 0 |
| associativity | 10 | 10 | 0 |
| commutativity | 10 | 10 | 0 |
| monotonicity | 20 | 20 | 0 |

**16 of 16 V1.15.1-targeted candidates suppressed.** All round-trip suppressions are HashTable Constants conversions (`minimumCapacity / maximumCapacity / scale / wordCount` and their underscore-prefixed variants). All idempotence suppressions are the same set viewed as single functions.

**3 round-trip survivors preserved by design:**
- `_value(forBucketContents:) ↔ _bucketContents(for:)` — asymmetric labeling per open decision #2 (likely true-positive).
- 2 × `intersection(_:) ↔ subtracting(_:)` (Self -> Self) — V1.14.1's SetAlgebra-shape veto only fires on inverse-pair, not round-trip; cycle-13 priority #1 candidate.

**6 idempotence survivors preserved**: 2 `_description(type:)` / `firstOccupiedBucketInChain(with:)` (non-domain labels), 4 SetAlgebra `intersection`/`subtracting` (Self -> Self) idempotence claims (also cycle-13 territory).

### swift-algorithms / Algorithms

| Template | Cycle-11 | Cycle-12 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 13 | 13 | 0 |

Algorithms has zero domain-marker-labeled candidates on V1.15.1's three target templates. Byte-identical to cycle-11 (`diff` returns empty). The 1 remaining `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor uses stride-style anchors, not domain markers; cycle-13 priority #2 (stride-style label extension) closes this.

### swift-numerics / ComplexModule

| Template | Cycle-11 | Cycle-12 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 166 | 166 | 0 |

ComplexModule's binary ops use `_:` (unlabeled) parameters per Swift API conventions for arithmetic operators. Byte-identical to cycle-11.

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-11 | Cycle-12 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 7 | 7 | 0 |

PLK has no domain-marker-labeled candidates. Byte-identical to cycle-11.

## Cycle-11 priority-#1 candidate-set verification

The cycle-11 findings' priority-#1 candidate set (12 OC round-trip + 7 OC idempotence) is now fully accounted for at v1.15:

| Candidate class | Cycle-11 count | Cycle-12 outcome | Mechanism |
|---|---:|---|---|
| OC round-trip with both-sides domain markers | 9 | **all suppressed** | V1.15.1 round-trip counter |
| OC round-trip with one-side domain marker | 1 | **preserved** | V1.15.0 open decision #2 default (both-sides) |
| OC round-trip with SetAlgebra shape | 2 | preserved (out of scope) | cycle-13 priority #1 |
| OC idempotence with domain markers | 7 | **all suppressed** | V1.15.1 idempotence counter |
| OC idempotence non-domain | 4 | preserved (different cause-of-noise) | (not targeted) |
| OC idempotence with SetAlgebra shape | 2 | preserved (out of scope) | cycle-13 priority #1 |

**16 of 16 V1.15.1-targeted candidates suppressed; 3 of 3 deliberately-preserved candidates remain surfaced.** The both-sides design choice from open decision #2 paid off — preserves the asymmetric `_value(forBucketContents:) ↔ _bucketContents(for:)` candidate as a possible true-positive for human triage at zero aggregate cost.

## Trajectory across all 12 cycles

| Cycle | Mechanism | Surface | Δ from prior | Cumulative Δ |
|---|---|---:|---:|---:|
| 1 (pre-tune) | none | 1167 | — | — |
| 1 (post-tune V1.4.3) | FP-storage + cross-type counter-signals | 358 | −809 | −69.3% |
| 2 (V1.5.2) | textual-only protocol-coverage suppression | 353 | −5 | −69.7% |
| 3 (V1.6.1) | identity-element pair-formation skip-list | 350 | −3 | −70.0% |
| 4 (V1.7.1) | stdlib-conformance bake-in | 326 | −24 | −72.1% |
| 5 (V1.8.1) | shape-gated Codable veto on round-trip | 349 | +23 | −70.1% |
| 6 (empirical-only) | (no surface change; baseline measured) | 349 | 0 | −70.1% |
| 7 (V1.10.1) | idempotence direction-label counter | 296 | −53 | −74.6% |
| 8 (V1.11.1) | inverse-pair direction-label counter | 288 | −8 | −75.3% |
| 9 (V1.12.1) | round-trip direction-label counter | 257 | −31 | −78.0% |
| 10 (V1.13.1) | hoist refactor (no surface change) | 257 | 0 | −78.0% |
| 11 (V1.14.1) | SetAlgebra-shape veto on inverse-pair | 251 | −6 | −78.5% |
| **12 (V1.15.1)** | **domain-marker counter on three templates** | **235** | **−16** | **−79.86%** |

**−79.86% cumulative reduction** with twelve calibration cycles (11 mechanism + 1 refactor). Cycle-12's −16 is the largest single-cycle structural-rule delta since cycle 9's −31. Largest "smallest-effort-per-template" delta in the loop's history: V1.15.1 ships ~250 lines of source + ~600 lines of tests across three templates and produces −16 suppressions; cycles 7-9 took ~750 lines of source across three releases for an aggregate −92 suppressions (−53 + −8 + −31).

## What v1.15 demonstrates

**Compression of three-template deployment.** The direction-counter family taught us that uniform parameter-label rules generalize cleanly across templates with different baselines. v1.15 leverages that lesson: V1.15.1 ships in one commit what cycles 7-9 needed three commits for. The compression is sustainable when (a) the mechanism is uniform, (b) the curated set is canonical-from-day-one, and (c) the cross-template integration pattern has prior precedent.

**Mechanism-class taxonomy expands to eight.** The calibration loop's vocabulary now includes:
1. **Cycle 1 (V1.4.3)**: textual type-name counter (FP-storage); cross-type pair counter.
2. **Cycle 2 (V1.5.2)**: protocol-coverage veto via curated `KnownProperty` × conformance map.
3. **Cycle 3 (V1.6.1)**: pair-formation skip-list (op-name × identity-name × type-shape filter).
4. **Cycle 4 (V1.7.1)**: stdlib-conformance bake-in (extends V1.5.2's substrate).
5. **Cycle 5 (V1.8.1)**: shape-gated veto.
6. **Cycles 7-9 (V1.10.1-V1.12.1)**: parameter-label counter — **direction-label sub-class** (spatial-sequence iteration).
7. **Cycle 11 (V1.14.1)**: function-name + type-shape composite.
8. **Cycle 12 (V1.15.1, this release)**: parameter-label counter — **semantic-intent sub-class** (named-domain markers).

The parameter-label counter family now has two empirically-validated sub-classes. Future cycles can frame new label-based mechanisms against this taxonomy.

**Both-sides detection has a name.** V1.15.0 open decision #2's both-sides default produced a measurably better outcome than either-side (preserved 1 likely true-positive at zero aggregate cost). Future label-based pair-template counters can default to both-sides when the false-positive risk on asymmetric candidates is non-trivial.

**`DomainMarkerLabels.curated` lives in core from day one.** Mirrors V1.14.1's `SetAlgebraShape.binaryOps` factoring posture. The v1.13 hoist lesson applied preemptively for the second consecutive cycle — shared template-agnostic curated sets ship at `SwiftInferCore.<Namespace>.curated` from cycle 1.

## Plan-vs-actual

The V1.15.0 plan f-bullet predicted:
> Algorithms: 13 → 13 (0; byte-identical)
> OrderedCollections round-trip: 12 → 3 (−9, both-sides default)
> OrderedCollections idempotence: 13 → 6 (−7)
> ComplexModule: 166 → 166 (0; byte-identical)
> PropertyLawKit: 7 → 7 (0; byte-identical)
> Aggregate 251 → 235 (−16, −6.4%)

**Actual outcome:**
- Algo: 13 → 13 (0). ✓
- OC round-trip: 12 → 3 (−9). ✓ **Exact.**
- OC idempotence: 13 → 6 (−7). ✓ **Exact.**
- ComplexModule: 166 → 166 (0). ✓
- PropertyLawKit: 7 → 7 (0). ✓
- Aggregate: 251 → 235 (−16, −6.4%). ✓ **Exact.**

**Third consecutive cycle in the loop's history with point-for-point projection match across all four corpora** (after v1.12 → v1.14 → v1.15, with v1.13 being a no-measurement refactor cycle). The cycle-8 methodology fix (per-suggestion `^Template:` line counts via Python regex) continues to deliver projection accuracy now confirmed across three consecutive measurement cycles.

**80% near-miss.** The V1.15.0 plan's "first cycle to cross 80% cumulative reduction" framing was overoptimistic by 0.14 percentage points: 1167 → 235 = −79.86%, needed ≤ 233 (1167 × 0.20 = 233.4) to cross. The both-sides default (−16) and either-side variant (−17 → 234) both missed by 1-2 candidates. Cycle-13 will cross unambiguously when the SetAlgebra-shape extension to round-trip + idempotence ships (−4 → 231 by minimum projection).

## Methodology gaps observed

**No new methodology gaps.** The cycle-9 + cycle-11 gaps carry forward unchanged:
- Possible-tier acceptance rate not re-measured at v1.10 / v1.11 / v1.12 / v1.14 / v1.15. The cycle-6 0/5 inverse-pair rate is now stale (rejected pool empty post-v1.14); the cycle-6 idempotence + round-trip pools have all rejection picks suppressed at v1.15. **Re-sampling now overdue across five mechanism cycles.**
- `surfacedAt` plumbing still pending (cycle-1 priority #4 territory).
- Multi-rater triage still pending (cycle-6 follow-up territory).

**The 80% near-miss is a calibration-precision lesson.** The plan's "would cross" projection treated 1167 × 0.20 as the bar, but rounding 233.4 down to 234 (the either-side variant) still doesn't cross — needs ≤ 233. Future cycle plans should use floor(N × 0.20) when projecting threshold-crossing claims, and call out the 1-2 candidate margin if applicable. Recorded as an open methodology refinement rather than a structural gap.

## Cycle-13 priority list (rotated post-v1.15)

The cycle-13 priority list rotates to drop the shipped domain-marker mechanism. Post-v1.15 ordering:

1. **SetAlgebra-shape veto extension to round-trip + idempotence** — *(was carried forward; PROMOTED to post-v1.15 priority #1.)* Closes the 4 remaining OC SetAlgebra survivors (2 round-trip + 2 idempotence; same `intersection / subtracting` Self-typed shape that V1.14.1 catches on inverse-pair). Mechanism class: function-name + type-shape composite (cycle-11 family) extended to two more templates. Could ship as one extension to V1.14.1's existing helpers at `Sources/SwiftInferTemplates/InversePairSetAlgebraShapeGate.swift` plus two new analogous helpers — paralleling the V1.15.1 three-template compression pattern. ~half a day. **Cycle-13 will unambiguously cross 80% cumulative reduction** (235 → 231 by minimum projection).

2. **Stride-style label extension** — *(was post-v1.14 priority #2; carried forward as #2.)* Add `startingAt`, `endingAt`, `from`, `until`, `offset` to a new `SwiftInferCore.StrideAnchorLabels.curated` set. Closes the 1 Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor on round-trip + inverse-pair simultaneously. ~1 hour to half a day. Re-evaluate after #1 ships.

3. **Possible-tier re-sampling on the post-v1.15 surface (235 across 4 corpora)** — *(was post-v1.14 priority #3; carried forward as #3.)* Re-running the cycle-6 rubric on a fresh 50-decision sample at v1.15 should produce a measurably higher acceptance rate (cycle-7+8+9+11+12 combined noise-floor reductions: 349 → 235 = −32.7% across five mechanism cycles). Quantifies cycle-6 → cycle-12 trajectory's measurable rate-improvement. **Now overdue across five mechanism cycles.** ~half a day.

4. **Reference-type carrier counter-signal** — *(was post-v1.14 priority #4; carried forward as #4.)* `Signal.Kind.referenceTypeCarrier` counter on idempotence + round-trip + inverse-pair when carrier resolves to `kind == .class` or `kind == .actor`. Empirical effect projected small on cycle-1..12 corpora (struct+enum dominant). ~1 day.

5. **FP approximate-equality template arm** — *(carried forward from cycles 2-9.)* Real `KitFloatingPointTemplate`. ~1 day.

6. **Math-library op-name gate extension** — *(carried forward from cycle-4.)* Add `rescaledDivide` / `_relaxedAdd` / `_relaxedMul` to V1.6.1's stdlib operator gate. ~1 hour.

7. **`surfacedAt` plumbing** — *(carried forward from cycle-1 priority #4.)* ~half a day.

8. **Multi-rater triage methodology** — *(carried forward from cycle-6.)* ~1 day if a second rater is available.

9. **Codec set broadening + SuggestionIdentity continuity fixture** — *(carried forward.)*

10. **SemanticIndex** — *(carried forward; multi-cycle effort.)*

## Summary

Cycle 12 shipped one structural rule deployed across three templates simultaneously: the domain-marker counter on idempotence + round-trip + inverse-pair (V1.15.1) — the **first cycle to compress three-template deployment into a single release** (cycles 7-9 took three releases for the analogous direction-counter family). Mechanism class: parameter-label counter (semantic-intent sub-class) — extends the cycles 7-9 family with `DomainMarkerLabels.curated = {forScale, forCapacity, forBucketContents}`.

The empirical effect was −16 of 251 surfaced suggestions (−6.4% aggregate) — the largest single-cycle structural-rule delta since cycle 9. All −16 suppressions are on the OC corpus (HashTable Constants conversions). Other three corpora byte-identical to cycle-11.

The cycle-11 priority-#1 candidate set is fully accounted for: 16 of 16 V1.15.1-targeted candidates suppressed; 3 of 3 deliberately-preserved candidates (1 asymmetric true-positive + 2 SetAlgebra round-trip pairs as cycle-13 territory) remain surfaced.

Plan-vs-actual was a point-for-point exact match across all four corpora **for the third consecutive measurement cycle** (v1.12 → v1.14 → v1.15). The 80% cumulative-reduction milestone was a near-miss at 79.86% — overoptimistic by 0.14 percentage points; cycle-13 crosses unambiguously.

Cumulative trajectory across cycles 1–12: **1167 → 235 (−79.86%)** with twelve calibration cycles (11 mechanism + 1 refactor) and **eight distinct mechanism classes** documented in the loop's vocabulary. Cycle-13's priority list rotates to promote the SetAlgebra-shape extension to round-trip + idempotence to priority #1 — paralleling V1.15.1's three-template compression pattern.
