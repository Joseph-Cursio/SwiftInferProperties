# v1.6 Calibration Cycle 3 — Findings

Captured: 2026-05-08. swift-infer at `1bc7039` (v1.5.0 tag) + the V1.6.0–V1.6.2 working copy. The third execution of PRD §17.3's empirical-tuning loop.

This document is the cycle-3 record: what we ran, what we learned, what shipped, what's deferred. Cycle 4 reads this to decide where to perturb next.

## Headline

**Cycle 3 shipped one structural rule: pair-formation skip-list filter on `IdentityElementPairing`.** A curated `(kit-blessed-constant, stdlib-operator)` skip-list (V1.6.1) drops cross-product mismatched pairs at pair-formation, *complementary* to v1.5's coverage veto: where v1.5 suppressed pairs the kit already verifies, v1.6 suppresses pairs whose op has no kit-published identity law for the paired constant.

| Tuning | Type | Where | Empirical effect |
|---|---|---|---|
| `IdentityElementPairing.skipsKnownMismatched(...)` | structural | IdentityElementPairing pair-emission loop | −3 of 353 surfaced (−0.85% aggregate); 100% of suppressions on swift-numerics/ComplexModule identity-element template |

After v1.6: total `--include-possible` surface across the 4 corpora went **353 → 350** (−3, −0.85%). All three suppressions are on ComplexModule identity-element, where the cycle-2 surviving cross-product noise (`(zero, -)`, `(zero, /)`, `(zero, *)`) is exactly what V1.6.1's filter targets.

**Notable plan deviation: the v1.6 plan projected "5 → 0" on ComplexModule identity-element; the actual outcome is 5 → 2.** Two user-named ops (`pow`, `rescaledDivide`) survive because they fall outside V1.6.1's `{+, -, *, /, %}` stdlib-operator gate. The plan's projection assumed the filter would reach all 5 cycle-2 survivors; in practice, only the 3 stdlib-operator pairs match. This is the v1.6 plan's documented preserve-recall trade-off (open decision #1 — skip-list, not allow-list) showing up empirically. Cycle 4 has a clear extension target.

## Corpus selection

Same four cycle-1 + cycle-2 targets — re-running on the cycle-2 baseline lets the suppression delta attribute cleanly to v1.6's single new rule:

| Corpus | Target | Cycle-2 post-rule total | Cycle-3 post-filter total | Δ |
|---|---|---:|---:|---:|
| swift-numerics | ComplexModule | 170 | 167 | **−3** |
| swift-collections | OrderedCollections | 101 | 101 | 0 |
| swift-algorithms | Algorithms | 75 | 75 | 0 |
| SwiftPropertyLaws | PropertyLawKit | 7 | 7 | 0 |
| **Total** | | **353** | **350** | **−3 (−0.85%)** |

Per-corpus pre/post snapshots committed to `docs/calibration-cycle-3-data/post-filter-*.discover.txt`. Diff target is `docs/calibration-cycle-2-data/post-rule-*.discover.txt`.

## What v1.6 ships (the mechanism)

One piece, in `Sources/SwiftInferTemplates/IdentityElementPairing.swift`:

- **Two curated sets + one private skip helper.** `kitBlessedIdentityConstants: Set<String>` = `{zero, one, empty, identity}` (the constants whose pairing with stdlib operators *should* match a kit-published identity law via V1.5.2's `identityCoverageCandidate`). `stdlibBinaryOperators: Set<String>` = `{+, -, *, /, %}` (the operators with kit-published identity laws on `Numeric` / `AdditiveArithmetic` / `SetAlgebra`). `skipsKnownMismatched(identityName:opName:)` returns `true` when *all three* conditions hold:
  1. `identityName` is in `kitBlessedIdentityConstants`
  2. `opName` is in `stdlibBinaryOperators`
  3. V1.5.2's `identityCoverageCandidate(...)` returns `nil` for the `(name, op)` pair
- **Wired into `IdentityElementPairing.candidates(...)`'s pair-emission loop.** Pairs satisfying the three-conjunct skip predicate are dropped before reaching the scorer; the existing `(T, T) -> T` type-shape gate is preserved as the upstream filter.

The mechanism reuses V1.5.2's `IdentityElementTemplate.identityCoverageCandidate(identityName:opName:)` directly (already `internal` by Swift's default access for static functions on a public enum). No new `Signal.Kind`, no new `KnownProperty`, no template-side changes — V1.5.2's scoring layer is unchanged.

## Per-pair filtering breakdown (ComplexModule)

All 3 ComplexModule suppressions are identity-element pairs that hit V1.6.1's three-conjunct skip predicate:

| Filtered pair | Identity name in kit-blessed? | Op in stdlib-operators? | `identityCoverageCandidate` returns? | Skip |
|---|:---:|:---:|---|:---:|
| `(zero, -)` × `Complex.zero` | yes | yes | `nil` (no kit identity law for `(zero, -)`) | **yes** |
| `(zero, /)` × `Complex.zero` | yes | yes | `nil` | **yes** |
| `(zero, *)` × `Complex.zero` | yes | yes | `nil` (kit's `*` identity is `.one`) | **yes** |

The two survivors on ComplexModule:

| Surviving pair | Skipped? | Why |
|---|:---:|---|
| `(zero, pow)` × `Complex.zero` | no | `pow` not in `stdlibBinaryOperators`; second-conjunct fails → emit |
| `(zero, rescaledDivide)` × `Complex.zero` | no | `rescaledDivide` not in `stdlibBinaryOperators`; emit |

This is the v1.6 plan's open-decision #1 trade-off in action: the skip-list deliberately excludes user-named / math-library ops to preserve recall (a user *might* have a custom `combine` op named `pow` whose `.zero` identity is genuine — though for ComplexModule's actual `pow`, it's noise). Cycle 4 priority #1 extends the gate.

## Cumulative trajectory across cycles 1–3 on ComplexModule identity-element

The v1.5 coverage veto + v1.6 pair-formation filter are *complementary* mechanisms targeting different cause-of-noise classes:

| Cycle | Surfaced | Mechanism | Δ |
|---|---:|---|---:|
| 1 (pre-tune) | 6 | none | — |
| 2 (V1.5.2 coverage veto) | 5 | `+ × .zero` suppressed because `Complex: AdditiveArithmetic` covers the additive identity law | −1 |
| 3 (V1.6.1 pair-formation filter) | 2 | `(zero, -)`, `(zero, /)`, `(zero, *)` filtered as `(kit-blessed, stdlib-op)` cross-product mismatches | −3 |
| **Cumulative** | **6 → 2** | | **−66.7%** |

The 1+3 split is informative: v1.5 caught the *one* genuinely kit-covered case (where the kit's check function would have verified the law); v1.6 caught the *three* structurally-mismatched cases (where the kit publishes no law for that op). The remaining 2 (`pow`, `rescaledDivide`) are op-name-shaped noise that neither cycle's mechanism is designed to reach — they need a curated extension to the stdlib-operator gate.

## What v1.5 + v1.6 demonstrate together

The cycle-2 findings doc framed v1.6 as the *complementary* mechanism to v1.5: v1.5 = "kit covers it"; v1.6 = "structurally mismatched." Cycle 3 confirms this empirically:

- **Mutually exclusive coverage.** No suggestion gets caught by both rules. Each cycle-3 filtered pair is one v1.5 *would not* veto (no kit law applies), and each cycle-2 vetoed pair is one v1.6 *would not* skip (the identity law applies, just not from this template's surface).
- **Decreasing returns per cycle.** Cycle 1 cut surface −69.3% (the single highest-leverage round); cycle 2 cut −1.4% (kit-covered cases); cycle 3 cut −0.85% (cross-product mismatches). The remaining surface is genuinely harder to suppress without expanding curation or introducing SemanticIndex.
- **The remaining ComplexModule identity-element noise (2 pairs) is now characterized.** Both survivors are kit-blessed-constant × user-named-op patterns. Cycle 4 has a single concrete target: extend `stdlibBinaryOperators` to include curated math-library names (`pow`, `**`, possibly `rescaledDivide` if user-curated).

## Why the other 3 corpora show 0 delta — same v1 textual-only limit, different mechanism

OrderedCollections + Algorithms + PropertyLawKit produced 0 suppressions at cycle 3, identical to cycle 2. The reason differs slightly from cycle 2's textual-only-coverage finding:

- **Cycle 2's 0-delta was a *coverage-reach* limit** — the corpora have suggestions on stdlib-typed (`Int`) or generic (`Element`) carriers whose conformance set isn't in the corpus's `typeDecls`, so v1.5's coverage map can't reach them.
- **Cycle 3's 0-delta is a *pair-formation-input* limit** — these three corpora had **0 identity-element pairs** in cycle 2 (per the cycle-2-data per-template breakdown). v1.6's filter operates on identity-element pairs only; with 0 input, it has nothing to filter regardless of correctness.

In other words: cycle 2's mechanism could *theoretically* fire on these corpora (the carrier types just aren't in `typeDecls`); cycle 3's mechanism *can't fire* because there are no identity-element candidates at all. Different reasons, same outcome.

This actually validates the v1.5 plan's open-decision #1 ("single-priority release vs bundled"): bundling cycle-3 priorities #1 + #2 (pair-formation filter + stdlib-conformance bake-in) into one release would have made the empirical effects unattributable. Cycle 3 isolates priority #1's effect cleanly: the only thing that changed is identity-element pair-formation, and the only suppressions are identity-element. Cycle 4 will isolate priority #2's effect against this clean baseline.

## Methodology gaps

**The v1.6 plan's empirical projection ("5 → 0") missed by 2.** The plan author predicted the filter would catch all 5 cycle-2 survivors; the implementation correctly preserved recall for user-named ops, leaving 2 survivors. This is a documented *design choice* (plan open-decision #1) but not adequately surfaced in the plan's empirical-effect projection. Future calibration plans should distinguish "design-bound projection" (what the rule *can* catch given its scope) from "aspirational projection" (what we'd want to catch if the rule's scope were broader). Cycle-4 priorities sized accordingly.

**Citation determinism still unfixed (cycle-2 finding).** `firstCoveringProtocol(...)` walks `Set<String>` non-deterministically. Suppressed suggestions still don't appear in stdout, so user-visible byte-stability holds, but Decisions records remain non-deterministic on the cited-protocol field. Trivial sort fix; cycle-4 priority #6.

**Single-runner triage carryover.** Same gap from cycle-1 + cycle-2 carries forward unchanged. v1.6 ships zero new triage decisions (structural-only change).

**`surfacedAt` plumbing still pending.** Carries forward from cycle-1 + cycle-2.

**Possible-tier sampling on the post-v1.6 surface (350 across 4 corpora) still pending.** With cycle-4 priority #2 (stdlib bake-in) likely cutting another ~20-50 from the surface, the resulting ~300 is genuinely tractable for sampling.

## Cycle-4 priority list (in expected impact order)

1. **Curated stdlib-conformance bake-in.** *(Priority #1 in cycle-2 findings doc; promoted because cycle-3 priority #1 has shipped.)*

   Cycle 2's headline 0-delta finding: textual-only protocol-coverage match misses stdlib-typed candidates (`Int`-typed `+` / `*` ops on OrderedCollections, etc.). Mirror `EquatableResolver.curatedEquatableStdlib`'s posture — add a curated `[TypeName: Set<String>]` of stdlib types' known conformances merged into `inheritedTypesIndex(...)`'s output:

   ```swift
   private static let stdlibConformances: [String: Set<String>] = [
       "Int":    ["BinaryInteger", "FixedWidthInteger", "Numeric",
                  "AdditiveArithmetic", "Comparable", "Hashable", "Codable"],
       "Double": ["BinaryFloatingPoint", "FloatingPoint", "Numeric",
                  "AdditiveArithmetic", "SignedNumeric", "Comparable",
                  "Hashable", "Codable"],
       // … Int8/16/32/64, UInt*, Float, Float80, Bool, String, …
   ]
   ```

   Empirical-effect estimate: the 10 commutativity + 10 associativity OrderedCollections suggestions on `(Int, Int) -> Int` ops would split into stdlib-operator pairs (suppressed) + user-named-op pairs (preserved). Combined with v1.6's identity-element pair-formation filter, the resulting cycle-4 surface should drop noticeably across all three currently-0-delta corpora.

   Estimated cycle-4 scope: ~half a day.

2. **Extend the v1.6 stdlib-operator gate to math-library op names.** Cycle 3 left 2 user-named-op survivors on ComplexModule (`pow`, `rescaledDivide`). Adding `pow` (and possibly `**`) to `stdlibBinaryOperators` would close the remaining identity-element noise on Complex. Risk: false-positive suppression if a user defines `pow` with monoid-style identity semantics. Mitigation: keep the curated list short and well-justified. ~30 min if scope stays at `pow` only.

3. **Approximate-equality template arm for FP types.** *(Carried forward from cycle-2 priority #3.)* Real `KitFloatingPointTemplate` emitting `checkFloatingPointPropertyLaws(for: T.self, using: gen)` stubs. Synergy with v1.5 + v1.6 + cycle-4 priority #1 — once stdlib-conformance bake-in suppresses Numeric-covered FP suggestions, FP-conforming-but-not-kit-checked types are the natural target. ~1 day.

4. **Possible-tier sampling on the post-v1.6 surface (350 across 4 corpora).** *(Carried forward from cycle-2 priority #4.)* With cycle-4 priorities #1 + #2 likely cutting another ~30-50, the resulting ~300 is genuinely tractable for a 20-30-decision sample. Closes the loop on cycle-1+2+3 hypotheses with empirical accept/reject data.

5. **`surfacedAt` plumbing.** *(Carried forward from cycle-1 priority #4.)* Unblocks PRD §17.2's time-to-adoption metric. ~half a day.

6. **Citation-determinism fix.** *(Carried forward from cycle-2 priority #6.)* Sort `inheritedTypes` before `firstCoveringProtocol` scans. ~30 min; bundle with priority #5.

7. **§13 Row 2 / Row 1d budget widening.** *(New from the v1.5 push CI flake-finding.)* The 3.0s / 5.0s perf budgets are tight on GitHub Actions hardware vs local Apple M1. Match v1.1's "flake-resistant 3.0s" precedent for Row 1c by widening Row 2 → 4.0s and Row 1d → 6.0s, OR add a CI-aware multiplier. ~30 min; bundle with priority #6.

8. **SemanticIndex.** *(Carried forward; multi-cycle effort. PRD §20 v1.1+.)* Resolves `Int: Numeric` etc. authoritatively, lifting both the cycle-2 textual-only-coverage limit and the cycle-3 stdlib-operator-name limit. Cycle-4 priority #1 (stdlib bake-in) is the cheap pre-SemanticIndex approximation; SemanticIndex is the proper fix.

## Summary

Cycle 3 shipped one structural rule: a `(kit-blessed-constant, stdlib-operator)` skip-list filter on `IdentityElementPairing` (V1.6.1). The empirical effect was −3 of 353 surfaced suggestions (−0.85% aggregate), all on swift-numerics/ComplexModule identity-element template. The 3 suppressions are exactly the cross-product mismatches V1.6.1's filter targets — v1.5's coverage veto couldn't reach them because no kit law applied; v1.6's pair-formation filter catches them via syntactic op-class match.

The plan-vs-actual deviation (5 → 0 projected; 5 → 2 actual) is informative: the v1.6 plan's open-decision #1 (skip-list, not allow-list) deliberately preserved recall for user-named ops, which means the 2 user-named-op survivors (`pow`, `rescaledDivide`) require a separate curated-list extension to address. Cycle 4 priority #2 sizes that extension as a 30-minute tuning opportunity.

The cumulative trajectory on ComplexModule identity-element is the headline result: **6 → 2 (−66.7%) over two calibration cycles**, with v1.5 and v1.6 catching mutually exclusive cause-of-noise classes (kit-covered vs structurally-mismatched). The remaining surface is now small enough to characterize precisely: 2 user-named-op pairs that a 30-minute curated extension could close.

The 0-delta on the other three corpora carries forward from cycle 2 unchanged — those corpora had 0 identity-element pairs at cycle-2 input, so v1.6's filter has nothing to filter. Cycle 4 priority #1 (curated stdlib-conformance bake-in) is the matching mechanism for those corpora's suggestions.

Cycle 4 has a concrete priority list with two ~half-day items (priorities #1 + #2 + #3 stacked) plus a 30-min math-library-op extension and a 30-min citation-determinism + perf-budget bundle. After cycle 4, the §19 acceptance-rate target should be measurable on a meaningfully-narrowed surface.
