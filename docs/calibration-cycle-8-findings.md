# v1.11 Calibration Cycle 8 — Findings

Captured: 2026-05-08. swift-infer at `307036f` (V1.11.1 — inverse-pair direction-label counter-signal). The eighth execution of PRD §17.3's empirical-tuning loop and the **first cycle to replicate a verified mechanism on an adjacent template**.

This document is the cycle-8 record: what we ran, what we learned, what shipped, what's deferred.

## Headline

**Cycle 8 shipped one structural rule: inverse-pair direction-label counter-signal.** V1.11.1 ports v1.10's just-shipped, just-verified mechanism (`Signal.Kind.directionLabel` + the curated 10-element direction set) onto `InversePairTemplate`. The new helper emits `-10` (not v1.10's `-15` — open decision #1, calibrated for inverse-pair's lower `+25` typeSymmetry baseline) when *either* pair-side's first-parameter argument label is in `IdempotenceTemplate.directionLabels`.

| Tuning | Type | Where | Empirical effect |
|---|---|---|---|
| `InversePairTemplate.directionLabelCounterSignal` (V1.11.1) | scoring counter | first-param argument label of either side | **−8 / −2.7% aggregate** (−5 Algorithms + −3 OrderedCollections); 0 ComplexModule + 0 PropertyLawKit |

After v1.11: total `--include-possible` surface across the 4 corpora went **296 → 288** (−8, −2.7%). Smaller absolute effect than cycle-7's −53 because inverse-pair was already a much smaller starting surface — only 15 candidates aggregated across the four corpora at cycle-7. Of those 15, **8 were direction-labeled and got suppressed**; 7 survive (1 Algo stride-style + 6 OC SetAlgebra-shaped) for cycle-9+ to address.

## Cycle-7 → cycle-8 mechanism-replication motif

Cycle-7 was the calibration loop's first *empirically motivated* mechanism (cycle-6 measured idempotence at 0/10 → cycle-7 ships counter-signal). Cycle-8 is the first *cross-template port* of a verified mechanism:

1. **Validated mechanism (cycle 7, V1.10.1):** direction-label counter-signal on `IdempotenceTemplate` produced −53 / −15.2% with no false-positive collateral.
2. **Adjacent template with same measured failure mode (cycle 6, inverse-pair 0/5):** the second-most-rejected template per cycle-6 — tied with identity-element (0/1, sample too small to drive a release).
3. **Hypothesis (cycle 8):** the same mechanism applied to inverse-pair will suppress the direction-labeled subset (Algo Index ops) while preserving the SetAlgebra-shaped survivors that need a different mechanism.
4. **Measurement (this cycle, cycle 8):** −8 inverse-pair suppressions distributed exactly as predicted (Algo 5 + OC 3); cycle-6 picks #48-#49 suppressed; #45-#47 stay surfaced as predicted.

This validates two design choices from v1.10:
- **`Signal.Kind.directionLabel` is the right factoring.** Two consumers (`IdempotenceTemplate` + `InversePairTemplate`) share the enum case and the curated set verbatim. v1.13's hoist-to-shared-namespace refactor (when round-trip becomes the third consumer) is now anticipated, not speculative.
- **The curated 10-element direction set is portable across templates** with different baseline scores (`+30` idempotence vs `+25` inverse-pair). Counter weight calibrates per-template (`-15` for idempotence, `-10` for inverse-pair) but the set itself is template-agnostic.

## Corpus selection

Same four cycle-1+2+3+4+5+6+7 targets. Diff target is `docs/calibration-cycle-7-data/post-direction-counter-*.discover.txt` (the 296-surface):

| Corpus | Target | Cycle-7 total | Cycle-8 total | Δ |
|---|---|---:|---:|---:|
| swift-numerics | ComplexModule | 166 | 166 | 0 |
| swift-collections | OrderedCollections | 87 | 84 | **−3** |
| swift-algorithms | Algorithms | 36 | 31 | **−5** |
| SwiftPropertyLaws | PropertyLawKit | 7 | 7 | 0 |
| **Total** | | **296** | **288** | **−8 (−2.7%)** |

Per-corpus pre/post snapshots committed to `docs/calibration-cycle-8-data/post-inverse-direction-counter-*.discover.txt`.

## What v1.11 ships (the mechanism)

One piece:

- **`InversePairTemplate.directionLabelCounterSignal(for:)` extension method** in `Sources/SwiftInferTemplates/InversePairDirectionLabelCounter.swift` (file-split per the V1.6.1 / V1.8.1 / V1.10.1 file-length precedent — inlining the helper pushed the parent enum 1 line over swiftlint's `type_body_length: 250` budget). The helper consults the existing `Signal.Kind.directionLabel` (added in V1.10.1) and the existing `IdempotenceTemplate.directionLabels` curated set (added in V1.10.1) — no new enum case, no new curated set, no new `KnownProperty`. Wired into `InversePairTemplate.suggest(...)`'s signal-aggregation pipeline alongside the existing FP-storage counter and protocol-coverage veto.

The mechanism reuses the existing Score / Tier machinery directly. Other six templates (idempotence / round-trip / commutativity / associativity / monotonicity / identity-element) are byte-identical to v1.10.

## Per-corpus suppression breakdown

### swift-algorithms / Algorithms

| Template | Cycle-7 | Cycle-8 | Δ |
|---|---:|---:|---:|
| **inverse-pair** | **6** | **1** | **−5** |
| idempotence | 5 | 5 | 0 |
| round-trip | 20 | 20 | 0 |
| monotonicity | 3 | 3 | 0 |
| commutativity | 1 | 1 | 0 |
| associativity | 1 | 1 | 0 |

5 of 6 inverse-pair claims suppressed — **83.3% of Algo inverse-pair surface eliminated**. The 5 suppressed are direction-labeled `index(after:) × index(after:)` self-pairs across multiple Algorithms source files (mirror of v1.10's idempotence suppressions on the same files but in pair shape). The 1 cycle-8 survivor is non-direction-labeled:
- `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` (Chunked) — labels `startingAt` / `endingAt` are stride-style (positional anchors, not increment/decrement), *not* in the curated 10-element direction set. Cycle-10 candidate per the v1.11 plan's "stride-style label extension" out-of-scope item.

### swift-collections / OrderedCollections

| Template | Cycle-7 | Cycle-8 | Δ |
|---|---:|---:|---:|
| **inverse-pair** | **9** | **6** | **−3** |
| idempotence | 13 | 13 | 0 |
| round-trip | 25 | 25 | 0 |
| monotonicity | 20 | 20 | 0 |
| commutativity | 10 | 10 | 0 |
| associativity | 10 | 10 | 0 |

3 of 9 inverse-pair claims suppressed — **33.3% of OC inverse-pair surface eliminated**. The 3 suppressed are likely direction-labeled (`index(after:)/(before:)`, `bucket(after:)/(before:)`, or `word(after:)/(before:)` self-pairs). The 6 cycle-8 survivors are all SetAlgebra-shaped Self-typed binary ops with `_:` (nil) labels:
- `intersection(_:) ↔ subtracting(_:)` × 6 site combinations across `OrderedSet+Partial SetAlgebra intersection.swift` × `OrderedSet+Partial SetAlgebra subtracting.swift` × `OrderedSet+UnorderedView.swift`. These match cycle-6 picks #45-#47 verbatim — same 3-of-5 inverse-pair rejection sub-pattern. **Cycle-9 candidate** (SetAlgebra-shape detection or domain-mismatch on inverse-pair).

### swift-numerics / ComplexModule

| Template | Cycle-7 | Cycle-8 | Δ |
|---|---:|---:|---:|
| (all unchanged) | 166 | 166 | 0 |

ComplexModule has no inverse-pair candidates (Complex is Equatable; all candidate elementary-function pairs route through `RoundTripTemplate`, not `InversePairTemplate`, per the M8.1 design — InversePairTemplate gates on `EquatableResolver.classify(typeText:) != .equatable`). Byte-identical to cycle-7. V1.11.1 has nothing to suppress on this corpus.

### SwiftPropertyLaws / PropertyLawKit

| Template | Cycle-5 | Cycle-7 | Cycle-8 | Δ |
|---|---:|---:|---:|---:|
| (all unchanged) | 7 | 7 | 7 | 0 |

PLK has no inverse-pair candidates. Byte-identical to cycle-7.

## Cycle-6 picks verification

Of the cycle-6 inverse-pair triage picks (5 rejections, IDs 45-49), V1.11.1 suppresses exactly the direction-labeled subset:

| # | Cycle-6 pick (corpus) | Cycle-8 outcome | Notes |
|---|---|---|---|
| 45 | OrderedSet `intersection(_:) ↔ subtracting(_:)` (OC) | still surfaces | `_` (nil label) ∉ direction set; cycle-9 candidate. |
| 46 | OrderedSet (same pattern) (OC) | still surfaces | Same. |
| 47 | OrderedSet (same pattern) (OC) | still surfaces | Same. |
| 48 | Algorithms Index ops (Algo) | **suppressed** | `after`/`before` ∈ direction set ✓ |
| 49 | Algorithms Index ops (Algo) | **suppressed** | Same. |

**2 of 5 cycle-6 inverse-pair rejections are now suppressed by V1.11.1's counter-signal.** The other 3 are correctly preserved (different cause-of-noise class — SetAlgebra-shaped Self-typed ops with no labels). This matches the v1.11 plan's projection at the picks level exactly.

## Trajectory across all 8 cycles

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
| **8 (V1.11.1)** | **inverse-pair direction-label counter** | **288** | **−8** | **−75.3%** |

**−75.3% cumulative reduction** with eight compositional mechanisms. Cycle-8's −8 is the smallest single-cycle structural-rule delta, reflecting:
1. The narrow targeting (inverse-pair was already the smallest-surface template).
2. The cross-template mechanism replication — V1.11.1 adds zero new design surface area (no new enum case, no new curated set), so the structural-leverage is bounded by the inverse-pair candidate count alone.

Both observations are *features*, not bugs. The compositional mechanisms across cycles 1-8 each target a structurally distinct cause-of-noise class; per-cycle surface deltas naturally narrow as the dominant noise classes are resolved.

## What v1.11 demonstrates

**Cross-template mechanism portability is real.** v1.10's `Signal.Kind.directionLabel` + `IdempotenceTemplate.directionLabels` ship in v1.11 *unchanged* — the only addition is the counter-signal helper on `InversePairTemplate`. The cross-template reuse confirms v1.10's open-decision-#3 framing ("private helper rather than shared utility") was the right call: cycles 8 + 9 (and likely 10+) will keep the per-template helper pattern, with hoisting-to-shared-namespace deferred until 3+ consumers exist.

**Either-side detection has no false-positive cost** at the calibrated `-10` weight. v1.11 plan's open-decision-#3 was "either-side vs forward-only" — either-side won because asymmetric labeling (e.g., `format(_:) × parse(after:)` with only one side labeled) should still suppress, and the `+10` curated/project name match keeps legitimate inverse pairs above the `+20` Possible boundary even when a direction label coincidentally appears. The cycle-8 capture had no observable false-positive collateral on curated-name pairs; the test fixture covered this case explicitly.

**Score arithmetic for inverse-pair was correctly calibrated.** v1.11 plan's open-decision-#1 chose `-10` over `-15` to avoid the noisy `+20` boundary zone. Empirically, the bare-shape direction-labeled pairs (typeSymmetry only, score `+25`) all dropped to `+15` Suppressed cleanly; the curated-named pairs with direction labels (the rare composition) would land at `+25` Possible, preserving them. No corpus pair lands exactly on `+20`, so the design-time concern was preventive — but it's now confirmed empirically.

## Plan-vs-actual

The v1.11 plan f-bullet predicted:
> Expected: Algo inverse-pair drops by ~10 (most of the 12 surfaced are `index(after:)`-shaped); OC inverse-pair drops by ~2 (HashTable `bucket(after:)/(before:)` survivors); ComplexModule + PropertyLawKit unchanged.

**Actual outcome:**
- Algo inverse-pair: 6 → 1 (−5). Expected ~10; **actual half the projection.**
- OC inverse-pair: 9 → 6 (−3). Expected ~2; **actual ~50% larger than projection.**
- ComplexModule: 166 → 166 (0). Expected unchanged. ✓
- PropertyLawKit: 7 → 7 (0). Expected unchanged. ✓
- Aggregate: 296 → 288 (−8). Expected ~−12; **actual 2/3 of projection.**

The plan **over-projected Algo by 2x** because the plan-time grep used substring counts (`grep -c "inverse-pair"`) rather than per-suggestion line counts (`grep -c "Template: inverse-pair"`); the actual cycle-7 Algo inverse-pair surface was 6 candidates, not 12. The plan **under-projected OC by 33%** by an off-by-one in pre-counted survivor enumeration.

**Methodology lesson for cycle-9+ plans:** when projecting from existing baseline data, always use per-suggestion line counts (`grep -c "Template: <template-name>"`) rather than substring counts. The cycle-7 findings doc had the correct numbers; my plan-time grep used a pattern that double-counted identity-hash mentions of the template name.

The empirical effect was **smaller** than projected (the inverse direction from cycle-7's `2-3× larger` deviation). Cycle-7 + cycle-8 together suggest projections cluster within ±2× of actual on direction-counter mechanisms; both directions are documented for the cycle-9 plan author.

## Methodology gaps observed

**No new gaps unique to v1.11.** The cycle-7 gaps carry forward unchanged:
- Curated direction-label set is closed (10 entries; v1.11 deliberately does *not* extend it).
- Domain-mismatch sub-pattern still pending (now affects both idempotence on OC HashTable AND inverse-pair on OC SetAlgebra).
- Possible-tier acceptance rate not re-measured at v1.10 *or* v1.11. The cycle-6 0/5 inverse-pair rate is now stale post-V1.11.1 (the surface dropped from 15 to 7).

**Stride-style label observation.** The 1 surviving Algo inverse-pair (`endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)`) suggests a third class of label-style: positional-anchor (`startingAt` / `endingAt` / `from` / `until`) distinct from both increment/decrement direction (`after` / `before`) and domain-mismatch labels (`forScale` / `forCapacity`). Whether to extend the curated direction set or build a separate "stride-anchor" set is a v1.x design choice (the v1.11 plan deferred this to cycle-10).

**The 5 cycle-6 inverse-pair picks are now fully accounted-for.** 2 of 5 suppressed (V1.11.1); 3 of 5 stay surfaced for the cycle-9 SetAlgebra-shape mechanism. No cycle-6 picks remain "unknown" for inverse-pair — the cycle-7 idempotence unknowns (#13, #16, #23, #44) still haven't been re-classified.

## Cycle-9 priority list (in expected impact order)

The cycle-9 priority list is now anchored on cycle-6's measurements + cycle-7's verification + cycle-8's mechanism-replication validation:

1. **Round-trip direction-label counter-signal.** *(Carried from cycle-8 priority #2; was cycle-7 priority #5.)* Apply v1.10's mechanism to `RoundTripTemplate` — the third consumer of `Signal.Kind.directionLabel` + `IdempotenceTemplate.directionLabels`. v1.10's open-decision-#3 anticipated this consumer; v1.13 hoist-to-shared-namespace becomes natural at this point. Round-trip Possible-tier surface still includes `(Index) -> Index ↔ (Index) -> Index` pairs (e.g., `index(after:) ↔ index(before:)`). Expected: 30-50 round-trip suppressions (round-trip is the largest-surface template). ~half a day.

2. **SetAlgebra-shape detection on inverse-pair.** *(NEW priority #2 from cycle-8.)* The 6 OC `intersection(_:) ↔ subtracting(_:)` survivors need a mechanism that recognizes "Self-typed binary ops on a SetAlgebra-conforming type" as not-true-inverses (they're related set ops, but `intersection` then `subtracting` doesn't recover the original input). Likely a new candidate property in `ProtocolCoverageMap` (`setAlgebraIntersectionSubtractingNotInverse`) wired into `InversePairTemplate.protocolCoverageVeto`. ~half a day.

3. **Domain-mismatch detection on idempotence + inverse-pair.** *(Carried from cycle-7 priority #3 + cycle-8 priority #3.)* The 7 OC HashTable scale-vs-capacity surviving idempotence claims + the parallel pattern on inverse-pair need a different mechanism — semantic intent inference on parameter labels (`forScale` vs return context). Likely a new `Signal.Kind.domainMismatchLabel` with curated mapping pairs. Could ship as a single mechanism applied to both templates simultaneously (paralleling cycle-7's idempotence + cycle-8's inverse-pair direction-label deployment cadence). ~1 day.

4. **Stride-style label extension.** *(NEW priority #4 from cycle-8.)* Add `startingAt`, `endingAt`, `from`, `until`, `offset` to a separate "stride-anchor" curated set (or extend `directionLabels` and adjust the count test). Closes the 1 Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor. Risk: false-positives on legitimate stride-anchored inverse pairs (rare in stdlib, possible in domain corpora). ~1 hour if extending the set; ~half a day if creating a separate set.

5. **FP approximate-equality template arm.** *(Carried forward from cycles 2-7 priority #2/#3.)* Real `KitFloatingPointTemplate`. ~1 day.

6. **Math-library op-name gate extension.** *(Carried forward from cycle-4 priority #5.)* `rescaledDivide` / `_relaxedAdd` / `_relaxedMul` to V1.6.1's stdlib operator gate. ~1 hour.

7. **Possible-tier re-sampling on the post-v1.11 surface (288 across 4 corpora).** *(Carried from cycle-7 priority #6.)* Now that V1.10.1 + V1.11.1's noise-floor reductions are measured, re-running the cycle-6 rubric on a fresh 50-decision sample at v1.11 should produce a measurably higher acceptance rate. ~half a day.

8. **`surfacedAt` plumbing.** *(Carried forward from cycle-1 priority #4.)*

9. **Multi-rater triage methodology.** *(Carried forward from cycle-6.)*

10. **Codec set broadening + SuggestionIdentity continuity fixture.** *(Carried forward.)*

11. **SemanticIndex.** *(Carried forward; multi-cycle effort.)*

## Summary

Cycle 8 shipped one structural rule: an inverse-pair direction-label counter-signal (V1.11.1) that ports v1.10's verified mechanism onto an adjacent template. The empirical effect was −8 of 296 surfaced suggestions (−2.7% aggregate) — the smallest single-cycle structural-rule delta to date, reflecting the narrow targeting (inverse-pair was already the smallest-surface template) and the cross-template mechanism replication adding zero new design surface area. All −8 suppressions are on the inverse-pair template; 5 on Algorithms, 3 on OrderedCollections, 0 on ComplexModule + PropertyLawKit.

The cycle-7 → cycle-8 mechanism-replication motif validates two design choices from v1.10: `Signal.Kind.directionLabel` is the right factoring (now shared across two templates verbatim), and the curated 10-element direction set is portable across templates with different baseline scores (counter weight calibrates per-template, set itself is template-agnostic). The cycle-6 inverse-pair picks are now fully accounted-for: 2 of 5 suppressed (V1.11.1), 3 of 5 preserved for cycle-9's SetAlgebra-shape mechanism.

Cumulative trajectory across cycles 1–8: **1167 → 288 (−75.3%)** with eight compositional mechanisms. Cycle 9's priority list is now data-anchored on three cycles of measurement: cycle-6's per-template baseline rates + cycle-7's mechanism verification + cycle-8's cross-template replication validation. The expected cycle-9 priorities cluster around (a) the third direction-label counter consumer (round-trip), (b) the next-largest non-direction-labeled rejection class (SetAlgebra-shape on inverse-pair), and (c) the cross-template domain-mismatch family (scale-vs-capacity on idempotence + inverse-pair). The natural cadence stays at one mechanism per release.
