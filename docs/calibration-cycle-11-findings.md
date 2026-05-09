# v1.14 Calibration Cycle 11 — Findings

Captured: 2026-05-09. swift-infer at `27b615e` (V1.14.1 — SetAlgebra-shape veto on inverse-pair). The eleventh execution of PRD §17.3's empirical-tuning loop and the **first cycle to ship a function-name + type-shape composite mechanism**.

This document is the cycle-11 record: what we ran, what we learned, what shipped, what's deferred.

## Headline

**Cycle 11 shipped one structural rule: SetAlgebra-shape veto on inverse-pair.** V1.14.1 lands a new mechanism class — distinct from cycles 7-9's parameter-label-based class — that consults curated *function-name* patterns alongside *type shape*. The new helper emits `-25` weight when both pair sides have `(Self) -> Self` shape AND both function names are in `SetAlgebraShape.binaryOps = {union, intersection, symmetricDifference, subtracting}`.

| Tuning | Type | Where | Empirical effect |
|---|---|---|---|
| `InversePairTemplate.setAlgebraShapeVeto` (V1.14.1) | scoring veto (non-veto-weight counter) | function-name + type-shape composite gate | **−6 / −2.3% aggregate** (−6 OrderedCollections); 0 ComplexModule + 0 Algorithms + 0 PropertyLawKit |

After v1.14: total `--include-possible` surface across the 4 corpora went **257 → 251** (−6, −2.3%). **First cycle to fully eliminate a template's per-corpus surface** (OrderedCollections inverse-pair **6 → 0**, 100%).

## Cycle-11 mechanism class: function-name + type-shape composite

Earlier cycles surfaced these distinct mechanism classes:

```
Cycle 1 (V1.4.3):  textual type-name counter (FP-storage)
                   cross-type pair counter
Cycle 2 (V1.5.2):  protocol-coverage veto via curated KnownProperty × conformance map
Cycle 3 (V1.6.1):  pair-formation skip-list (op-name × identity-name × type-shape filter)
Cycle 4 (V1.7.1):  stdlib-conformance bake-in (extends V1.5.2's substrate)
Cycle 5 (V1.8.1):  shape-gated veto (combines V1.5.2 with type-shape detection)
Cycles 7-9 (V1.10.1-V1.12.1): parameter-label counter family
Cycle 10 (V1.13):  refactor (no new mechanism — hoist of V1.10.1's curated set)
Cycle 11 (V1.14.1, this cycle): function-name + type-shape composite ← NEW class
```

The cycle-11 mechanism's defining property: it consults curated *function-name* patterns paired with *type shape* (parameter type + return type), without protocol-conformance lookup. This is structurally different from:
- **Parameter-label counters** (cycles 7-9): consult curated *argument-label* patterns on the first parameter.
- **Protocol-coverage vetos** (cycles 2, 4, 5): consult curated *property* patterns × inheritance-clause membership.
- **Shape-gated vetos** (cycle 5): combine protocol-coverage with type-shape, but still root-cause via inheritance.

Function-name + type-shape composite covers the case where:
- The *names* identify a structural pattern (here, SetAlgebra binary ops).
- The *type shape* (`(Self) -> Self`) confirms the structural pattern is in scope.
- *No conformance lookup needed* — the structural argument holds regardless of declared conformance.

This is important because `OrderedSet` itself doesn't declare `: SetAlgebra` directly (only has `Partial SetAlgebra` extension splits); a conformance-based mechanism would miss 4 of 6 cycle-9 OC survivors. Shape-only catches all 6.

## Corpus selection

Same four cycle-1+...+9 targets. Diff target is `docs/calibration-cycle-9-data/post-roundtrip-direction-counter-*.discover.txt` (the 257-surface):

| Corpus | Target | Cycle-9 total | Cycle-11 total | Δ |
|---|---|---:|---:|---:|
| swift-numerics | ComplexModule | 166 | 166 | 0 |
| swift-collections | OrderedCollections | 71 | 65 | **−6** |
| swift-algorithms | Algorithms | 13 | 13 | 0 |
| SwiftPropertyLaws | PropertyLawKit | 7 | 7 | 0 |
| **Total** | | **257** | **251** | **−6 (−2.3%)** |

Per-corpus pre/post snapshots committed to `docs/calibration-cycle-11-data/post-setalgebra-veto-*.discover.txt`.

(Cycle-10 was the v1.13 hoist refactor with no measurement; cycle-11 is the next mechanism cycle.)

## What v1.14 ships (the mechanism)

Two pieces:

1. **`Sources/SwiftInferCore/SetAlgebraShape.swift`** — canonical home for the curated 4-element binary-op set as `public enum SetAlgebraShape { public static let binaryOps: Set<String> }`. Lives in core from cycle 1 (canonical-from-day-one per the v1.13 hoist precedent; no per-template intermediate, no future hoist needed). Companion to `DirectionLabels.curated` (V1.13.1) — both factored as `public enum <Name> { public static let <subset>: Set<String> }` for consistent template-agnostic-curated-data ergonomics.

2. **`Sources/SwiftInferTemplates/InversePairSetAlgebraShapeGate.swift`** — `setAlgebraShapeVeto(for:)` private static helper. File-split per the V1.6.1 / V1.8.1 / V1.10.1 / V1.11.1 / V1.12.1 file-length precedent (keeps each calibration mechanism in a self-contained file for attribution clarity). Wired into `InversePairTemplate.suggest(...)`'s signal-aggregation pipeline between the direction-label counter and `protocolCoverageVeto`.

The mechanism reuses the existing `Signal.Kind.protocolCoveredProperty` case for the veto (no new enum case). Score arithmetic for inverse-pair (baseline `+25` typeSymmetry):
- Bare typeSymmetry `+25` − 25 = `0` → Suppressed (clean margin from `+20`).
- typeSymmetry + curated/project name (`+10`) `− 25` = `+10` → Suppressed (still suppressed; curated `parse/format`-style names are unlikely to coincide with SetAlgebra ops, but if they do the structural argument still wins).

## Per-corpus suppression breakdown

### swift-collections / OrderedCollections

| Template | Cycle-9 | Cycle-11 | Δ |
|---|---:|---:|---:|
| **inverse-pair** | **6** | **0** | **−6** |
| associativity | 10 | 10 | 0 |
| commutativity | 10 | 10 | 0 |
| idempotence | 13 | 13 | 0 |
| monotonicity | 20 | 20 | 0 |
| round-trip | 12 | 12 | 0 |

**100% of OC inverse-pair surface eliminated** — first cycle to drop a template's per-corpus surface to zero. The 6 suppressed claims:

| # | Forward signature | Reverse signature |
|---|---|---|
| 1 | `intersection(_:) (Self) -> Self` (OS Partial SetAlgebra intersection.swift) | `subtracting(_:) (Self) -> Self` (OS Partial SetAlgebra subtracting.swift) |
| 2 | `intersection(_:) (Self) -> Self` (OS Partial SetAlgebra intersection.swift) | `intersection(_:) (Self) -> Self` (OS UnorderedView.swift) |
| 3 | `intersection(_:) (Self) -> Self` (OS Partial SetAlgebra intersection.swift) | `subtracting(_:) (Self) -> Self` (OS UnorderedView.swift) |
| 4 | `subtracting(_:) (Self) -> Self` (OS Partial SetAlgebra subtracting.swift) | `intersection(_:) (Self) -> Self` (OS UnorderedView.swift) |
| 5 | `subtracting(_:) (Self) -> Self` (OS Partial SetAlgebra subtracting.swift) | `subtracting(_:) (Self) -> Self` (OS UnorderedView.swift) |
| 6 | `intersection(_:) (Self) -> Self` (OS UnorderedView.swift) | `subtracting(_:) (Self) -> Self` (OS UnorderedView.swift) |

All 6 fit V1.14.1's two-condition gate: both pair sides have `(Self) -> Self` shape AND both names in `SetAlgebraShape.binaryOps`.

### swift-algorithms / Algorithms

| Template | Cycle-9 | Cycle-11 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 13 | 13 | 0 |

The 1 surviving Algo inverse-pair (`endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)`) has labels `startingAt` / `endingAt` — neither in `DirectionLabels.curated` nor would they be in any plausible SetAlgebra extension. Stride-style label extension (post-v1.13 priority #3, now post-v1.14 priority #2) will close this in v1.15+.

### swift-numerics / ComplexModule

| Template | Cycle-9 | Cycle-11 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 166 | 166 | 0 |

ComplexModule has zero `(Self) -> Self`-shape inverse-pair candidates. Complex's binary ops are `(Complex, Complex) -> Complex` (free-function shape on a non-self carrier), not the SetAlgebra protocol-extension Self shape. Byte-identical to cycle-9.

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-9 | Cycle-11 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 7 | 7 | 0 |

PLK has no inverse-pair candidates. Byte-identical to cycle-9.

## Cycle-6 picks coverage closes at v1.14

The cycle-6 single-runner triage's 5 inverse-pair rejections are now fully accounted for:

| # | Cycle-6 pick | Cycle-9 outcome | Cycle-11 outcome | Mechanism |
|---|---|---|---|---|
| 45 | OS `intersection ↔ subtracting` (OC) | still surfaces | **suppressed** | V1.14.1 SetAlgebra veto |
| 46 | OS (same pattern) (OC) | still surfaces | **suppressed** | V1.14.1 SetAlgebra veto |
| 47 | OS (same pattern) (OC) | still surfaces | **suppressed** | V1.14.1 SetAlgebra veto |
| 48 | Algo Index ops (Algo) | suppressed (V1.11.1) | (already suppressed) | V1.11.1 direction-label |
| 49 | Algo Index ops (Algo) | suppressed (V1.11.1) | (already suppressed) | V1.11.1 direction-label |

**5 of 5 cycle-6 inverse-pair rejections now suppressed**, distributed across two complementary mechanisms:
- 2/5 by V1.11.1 direction-label counter (cycle 8) — parameter-label class.
- 3/5 by V1.14.1 SetAlgebra-shape veto (cycle 11) — function-name + type-shape composite class.

The cycle-6 inverse-pair acceptance rate (0/5 = 0%) now has **all five rejection picks suppressed**. The "0/5" rate is no longer measurable because the rejected pool is empty — all rejections at v1.14 are mechanism-suppressed before triage. A cycle-12+ Possible-tier re-sampling on the post-v1.14 surface would measure whether the per-template rate has moved up on the surviving inverse-pair candidates (now down to 1: the Algo `endOfChunk/startOfChunk` stride survivor).

## Trajectory across all 11 cycles

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
| **11 (V1.14.1)** | **SetAlgebra-shape veto on inverse-pair** | **251** | **−6** | **−78.5%** |

**−78.5% cumulative reduction** with eleven calibration cycles (10 mechanism + 1 refactor). Cycle-11's −6 is a precision-targeted suppression — the structural pattern was so specific that the projection landed exactly. Compare with cycles 7-9's parameter-label cycles where the surface effect was bigger but plan-actual deviation was wider; cycle-11's narrower target had narrower variance.

## What v1.14 demonstrates

**Function-name + type-shape composite is a new mechanism class.** The calibration loop's mechanism vocabulary now spans seven distinct shapes (textual type-name counter, cross-type counter, protocol-coverage veto, pair-formation skip-list, stdlib-bake-in, parameter-label counter, function-name + type-shape composite). Each class targets a structurally different cause-of-noise; cycles 1-11 demonstrate that the calibration loop scales by accumulating mechanism classes as new noise patterns surface.

**Shape-only check catches more than a conformance check.** The V1.14.0 plan's open decision #3 weighed shape-only vs combined "shape + conformance" detection. Empirically, shape-only catches all 6 OC survivors; a conformance check would catch 2/6 (only the `OrderedSet.UnorderedView` ones, where `: SetAlgebra` is declared directly). The 4 OrderedSet-side survivors live on `Partial SetAlgebra` extensions that don't satisfy SetAlgebra's full method surface — `inheritedTypesByName["OrderedSet"]` doesn't contain `SetAlgebra`. The structural argument "SetAlgebra ops aren't inverses" doesn't depend on conformance, so the conformance gate is incorrectly restrictive.

**`SetAlgebraShape.binaryOps` lives in core from day one.** V1.13's hoist refactor demonstrated that template-agnostic curated sets belong in `SwiftInferCore`. V1.14 applies the lesson preemptively: the curated 4-element set ships at `SwiftInferCore.SetAlgebraShape.binaryOps` from V1.14.1 commit, without a per-template intermediate. Future templates that consume this set (e.g., a hypothetical commutativity arm that recognizes SetAlgebra `intersection`/`union` as commutative) consume directly from core.

**First cycle to fully eliminate a template's per-corpus surface.** OC inverse-pair 6 → 0 means the OC corpus has zero surviving inverse-pair candidates. This isn't because the template is broken; it's because the corpus's inverse-pair candidates were all SetAlgebra-shape (and the cycle-7-9 + cycle-11 combination surfaces them as non-inverse). The metric "per-template per-corpus surface" can now hit zero; the framing for cycle-12+ should account for that.

## Plan-vs-actual

The v1.14 plan f-bullet predicted:
> Algorithms inverse-pair: 1 → 1 (0; stride-style survivor)
> OrderedCollections inverse-pair: 6 → 0 (−6; 100% of OC inverse-pair surface)
> ComplexModule: 166 → 166 (byte-identical; no SetAlgebra-shape candidates)
> PropertyLawKit: 7 → 7 (byte-identical; no inverse-pair candidates)
> Aggregate 257 → 251 (−6, −2.3%)

**Actual outcome:**
- Algo inverse-pair: 1 → 1 (0). Expected 0. ✓
- OC inverse-pair: 6 → 0 (−6). Expected −6. ✓ **Exact.**
- ComplexModule: 166 → 166 (0). Expected unchanged. ✓
- PropertyLawKit: 7 → 7 (0). Expected unchanged. ✓
- Aggregate: 257 → 251 (−6, −2.3%). Expected −6. ✓ **Exact.**

**Second cycle in the loop's history with point-for-point projection match across all four corpora** (after v1.12 → v1.14, with v1.13 being a no-measurement refactor cycle in between). The methodology fix from cycle-8 (per-suggestion `^Template:` line counts via Python regex) continues to deliver projection accuracy now confirmed across two consecutive measurement cycles.

## Methodology gaps observed

**No new gaps unique to v1.14.** The cycle-9 gaps carry forward unchanged:
- Stride-style label extension still pending (carried over from cycle-8 / cycle-9 / cycle-10).
- Domain-mismatch family still pending (now affects 12 OC round-trip + 7 OC idempotence = 19 candidates; OC inverse-pair previously had 0 domain-mismatch candidates and is now at 0 inverse-pair total).
- Possible-tier acceptance rate not re-measured at v1.10 / v1.11 / v1.12 / v1.14. The cycle-6 0/5 inverse-pair rate is now stale (rejected pool is empty post-v1.14).

**Mechanism-class taxonomy stabilized.** Cycle-11 added a new mechanism class to the calibration loop's vocabulary; future cycles can be classified against the seven shapes documented above. This makes priority-list rotation easier — the cycle-12 priority list can now be sorted by mechanism class as well as expected impact.

## Cycle-12 priority list (rotated post-v1.14)

The cycle-12 priority list is now anchored on cycle-6's measurements + cycle-7's verification + cycle-8's cross-template replication + cycle-9's three-consumer family completion + the v1.13 hoist + cycle-11's first-of-class composite mechanism. Post-v1.14 rotation drops the shipped SetAlgebra mechanism:

1. **Domain-mismatch family on idempotence + inverse-pair + round-trip simultaneously** — *(was post-v1.13 priority #2; PROMOTED to post-v1.14 priority #1.)* ~19 candidates aggregate (12 OC round-trip + 7 OC idempotence + 0 inverse-pair). Could ship as a single mechanism applied to three templates simultaneously, paralleling the direction-counter family's three-cycle deployment cadence but compressed into a single release. Mechanism class: parameter-label counter (cycles 7-9 family) but for *semantic-intent* labels (`forScale` ↔ `forCapacity`) rather than directional labels. Likely a new `Signal.Kind.domainMismatchLabel` and a curated mapping-pairs set in core (paralleling `DirectionLabels` and `SetAlgebraShape` factoring). ~1 day.

2. **Stride-style label extension** — *(was post-v1.13 priority #3; PROMOTED to post-v1.14 priority #2.)* Add `startingAt`, `endingAt`, `from`, `until`, `offset` to either a new `SwiftInferCore.StrideAnchorLabels.curated` set (paralleling V1.14.1's `SetAlgebraShape` factoring) or extend `DirectionLabels.curated` with adjusted count tests. Closes the 1 Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor on both round-trip + inverse-pair templates. ~1 hour if extending the set; ~half a day if creating a separate set.

3. **Possible-tier re-sampling on the post-v1.14 surface (251 across 4 corpora)** — *(was post-v1.13 priority #4; PROMOTED to post-v1.14 priority #3.)* Re-running the cycle-6 rubric on a fresh 50-decision sample at v1.14 should produce a measurably higher acceptance rate (cycle-7+8+9+11 combined noise-floor reductions: 349 → 251 = −28.1% across four mechanism cycles). Quantifies the cycle-6 → cycle-11 trajectory's measurable rate-improvement. ~half a day.

4. **Reference-type carrier counter-signal** — *(was post-v1.13 priority #5; carried forward.)* Add a `Signal.Kind.referenceTypeCarrier` counter on idempotence + round-trip + inverse-pair when the carrier resolves to a `TypeDecl` with `kind == .class` or `kind == .actor`. Empirical effect projected small on the four cycle-1..9 corpora (struct+enum dominant); likely lands behind the higher-impact priorities #1-#3. ~1 day.

5. **FP approximate-equality template arm** — *(carried forward from cycles 2-9.)* Real `KitFloatingPointTemplate`. ~1 day.

6. **Math-library op-name gate extension** — *(carried forward from cycle-4.)* `rescaledDivide` / `_relaxedAdd` / `_relaxedMul` to V1.6.1's stdlib operator gate. ~1 hour.

7. **`surfacedAt` plumbing** — *(carried forward from cycle-1 priority #4.)* ~half a day.

8. **Multi-rater triage methodology** — *(carried forward from cycle-6.)* ~1 day if a second rater is available.

9. **Codec set broadening + SuggestionIdentity continuity fixture** — *(carried forward.)*

10. **SemanticIndex** — *(carried forward; multi-cycle effort.)*

## Summary

Cycle 11 shipped one structural rule: a SetAlgebra-shape veto on inverse-pair (V1.14.1) — the **first function-name + type-shape composite mechanism** in the calibration loop. The empirical effect was −6 of 257 surfaced suggestions (−2.3% aggregate) — the **first cycle to fully eliminate a template's per-corpus surface** (OC inverse-pair 6 → 0).

The cycle-6 picks coverage closes at v1.14: all 5 inverse-pair rejection picks are now suppressed across V1.11.1 (2/5, parameter-label class) + V1.14.1 (3/5, function-name + type-shape composite class). The "0/5 acceptance rate" framing from cycle-6 is no longer measurable because the rejected pool is empty post-v1.14.

Plan-vs-actual was a point-for-point exact match across all four corpora — second consecutive measurement cycle (v1.12 → v1.14) with this property. The cycle-8 methodology fix continues to deliver projection accuracy.

Cumulative trajectory across cycles 1–11: **1167 → 251 (−78.5%)** with eleven calibration cycles (10 mechanism + 1 refactor) and seven distinct mechanism classes documented in the loop's vocabulary. Cycle-12's priority list rotates to promote the domain-mismatch family on idempotence + inverse-pair + round-trip simultaneously to priority #1 — the next mechanism-class expansion target. The natural cadence stays at one mechanism per release; v1.13's refactor-only release remains the canonical refactor pattern between mechanism cycles.
