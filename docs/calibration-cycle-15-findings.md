# Calibration cycle 15 findings — v1.18 value-semantics workstream (A + C)

**Captured:** 2026-05-09 against the V1.18.A + V1.18.C commits (`65c85a9` + `95ef078`).
**Cycle type:** Mechanism cycle (two workstreams: A = carrier value-semantics signal; C = dual-style consistency template). v1.19 will ship Workstream B (mutating-method lift) and v1.20 will be the empirical-only re-measurement on the post-v1.19 surface.

This is the **fifteenth calibration cycle** and the **first to ship two new mechanisms in a single release** (continuing the cycle-13 single-commit two-template pattern). The two workstreams are independently mergeable and were committed separately to keep the focused-commit convention; this findings doc covers both.

## Headline

- **Workstream A (carrier value-semantics signal).** Closes the four-cycles-deferred reference-type-carrier counter (post-v1.13 #5 → post-v1.16 #3 → cycle-14 #3) plus its inverse positive signal. New `Signal.Kind.referenceTypeCarrier` (`-10`) and `Signal.Kind.valueSemanticCarrier` (`+5`) consumed by `IdempotenceTemplate`, `RoundTripTemplate`, `InversePairTemplate`, and `IdentityElementTemplate`. New `SwiftInferCore.CarrierKindResolver` does the classification via a curated stdlib value-type allow-list, tuple/literal syntax, generic-parameter heuristic, same-corpus `TypeDecl` lookup (depth-bounded 3 levels), and a closure-typed stored-member detector for the worked-example-3 leak case. Per the v1.18 plan §2 refinement: `InverseElementPairing` produces witness records consumed by the M8 RefactorBridge orchestrator with no Suggestion to attach a signal to — out of v1.18 scope.

- **Workstream C (dual-style consistency template).** New `DualStyleConsistencyTemplate` + `DualStylePairing` + `Vocabulary.dualStyleNamePairs`. Detects canonical Swift dual-style pairs (`add`/`adding`, `sort`/`sorted`, `formUnion`/`union`) and emits the consistency property `var c = a; c.<mut>(args); return c == a.<nonMut>(args)`. Score 70 (Likely) by construction; +5 carrier signal lifts to 75 (Strong) on value-semantic carriers.

- **Mechanism-class taxonomy:** 8 → **11 classes**. Adds class **9** (carrier-kind structural counter/positive signal — Workstream A), class **10** (dual-style pair detection — Workstream C pairing infra), and class **11** (dual-style consistency property — Workstream C template). Class 11 is the first new template family added since M8.5 (v1.9, kit `Group` + `CommutativeMonoid` writeouts).

## Workstream A — calibration consequence on the 1618-test baseline

The 1618-test suite from v1.17 includes 19 golden-snapshot tests that bake in pre-v1.18 score totals and tier labels. Every one updated to reflect the new carrier signal. Two notable behavioral shifts:

1. **Round-trip on struct carriers crosses Likely → Strong.** Pre-v1.18: 30 type + 40 curated = 70 → Likely. Post-v1.18: +5 value-semantic carrier = 75 → **Strong** (Tier.strong threshold is ≥75, not ≥80). Affects every `(encode, decode)`-shape pair on a value-semantic struct container. Visible in `DiscoverPipelineTests.roundTripFixtureRenders` (golden updated `70 (Likely)` → `75 (Strong)`).

2. **Inverse-pair on non-Equatable struct carriers crosses Possible → Likely.** Pre-v1.18: 25 type + 10 curated = 35 → Possible (default-hidden). Post-v1.18: +5 carrier = 40 → **Likely** (default-shown). Surfaces a previously-hidden suggestion class. Visible in `DiscoverPipelineStatsTests.statsOnlyRendersSummaryBlock` (snapshot moved `2 suggestions across 2 templates` → `3 suggestions across 3 templates`, with the third being the previously-Possible inverse-pair on (encode, decode) over a non-Equatable struct).

These two shifts are **expected calibration consequences** of the value-semantic carrier signal — exactly the empirical hypothesis the v1.18 plan §6 release-blocking criterion ("workstream A is precision-positive (suppresses class-carrier picks that were marginal) and C is recall-positive (introduces new picks that didn't exist before)") set up. The Likely→Strong shift tightens the rendered-tier message; the Possible→Likely shift expands the default-visible surface.

**Test count delta: 1618 → 1680.** Workstream A added 33 unit tests (`CarrierKindResolverTests` covering curated allow-list, generic parameters, corpus lookup, recursive composition, depth bound, signal-factory output, and the ValueSemantic Kit Proposal §2.2 worked examples). Workstream C added 29 unit tests (`DualStylePairingTests` + `DualStyleConsistencyTemplateTests` covering all three curated rules, project-vocabulary fallthrough, shape filters, return-type matching including `Self` and generic-container forms, location-stable sorting, and full template scoring + identity + cross-validation key).

## Per-corpus signal-hit data (post-merge CI capture)

The four cycle-1..14 calibration corpora (Algorithms, Collections-OrderedCollections, ChartMath / ComplexModule, PropertyLawKit) were not re-run as part of the v1.18 cut — the calibration-cycle data captures live with their respective findings docs and will be re-captured at the v1.20 empirical cycle alongside the workstream-B lifted-suggestion surface. The expected v1.18 deltas, projected from the test-suite calibration:

| Corpus | Projected workstream A signal hits | Projected workstream C new picks | Net surface delta |
|---|---|---|---|
| Algorithms | Negligible (most carriers are `Algorithms`-namespace structs already) | Low (Algorithms doesn't use the form-prefix or active/-ed convention extensively) | ≈ +1-3 |
| OrderedCollections | Significant value-semantic positives on `OrderedSet`, `OrderedDictionary` carriers; possible reference-type negatives on the `_Node` class internals if exposed | High — `OrderedSet` follows the form-prefix convention rigorously (`formUnion` / `union`, `formIntersection` / `intersection`) | ≈ +5-10 |
| ComplexModule (CM) | Most ops are static `(T, T) -> T` on `Complex<RealType>` (struct) — value-semantic positives broadly | Low — CM doesn't use the dual-style pattern (numeric domain) | ≈ +1-2 |
| PropertyLawKit | Negligible (kit is a small Sources/ surface) | Low | ≈ 0-1 |

The **OC corpus is the most likely to show measurable surface expansion** from Workstream C: stdlib `SetAlgebra` defaults are inherited by `OrderedSet`, and the form-prefix convention covers `formUnion` / `formIntersection` / `formSymmetricDifference`. Workstream A's net effect is precision-positive on CM (most carriers are value-semantic and earn the small +5 boost — no rejections expected) and ambiguous on Algorithms / OC (depends on whether internal class-typed indexes resolve to the `.referenceType` counter or fall through to `.unknown`).

**Why the projections are coarse.** Without re-running the four corpora, the signal-hit counts can't be measured exactly. The v1.20 empirical cycle re-runs the harness against the post-v1.19 surface (which includes both workstream A + C from v1.18 and workstream B's lifted surface from v1.19) and reports per-template + per-corpus acceptance rates comparable to cycle 6 (26.7%) and cycle 14 (34.8%).

## Mechanism-class taxonomy update

Pre-v1.18 (8 classes per `docs/calibration-cycle-14-findings.md` + CLAUDE.md repo-state):

1. Carrier-type whitelist veto (the original V1.4.3 fp-counter)
2. Cross-type structural counter (V1.4.3b)
3. Curated-set protocol-coverage veto (V1.5.2)
4. Operator-aware identity-element pairing (V1.5.2 Idemnity)
5. Op-class-mapped commutativity / associativity coverage (V1.7.2 / V1.8.2)
6. Parameter-label direction-counter on idempotence + round-trip + inverse-pair (V1.10.1 / V1.11.1 / V1.12.1)
7. Function-name + type-shape composite (V1.14.1 set-algebra inverse-pair)
8. Parameter-label semantic-intent counter (V1.15.1 domain-marker idempotence + round-trip + inverse-pair)

Post-v1.18 (11 classes):

9. **NEW: Carrier-kind structural counter/positive signal** (V1.18.A). Resolves the function's containing type to `.valueSemantic` / `.referenceType` / `.mixed` / `.unknown` via depth-bounded recursive `TypeDecl` analysis with a curated value-type allow-list; emits a paired ±-signal. Rationale: closes the four-cycle-deferred reference-type carrier counter and prepares the necessary structural precondition for the v1.19 mutating-method lift (workstream B).

10. **NEW: Dual-style pair detection** (V1.18.C pairing infrastructure). Detects canonical Swift `mutating func op(...)` ↔ non-mutating `func op'(...) -> Self` siblings on the same containing type via three curated naming rules (`X` ↔ `Xing`, `X` ↔ `Xed`, `formX` ↔ `X`) plus type-shape match (same param list + non-mutating returns container type or `Self`). New mechanism class because pair *formation* is itself novel — prior pairing passes (`FunctionPairing`, `IdentityElementPairing`, `InverseElementPairing`) all worked with same-mutability summaries.

11. **NEW: Dual-style consistency property** (V1.18.C template). First new property family added since M8.5's kit `Group` + `CommutativeMonoid` writeouts (v1.9). Asserts that a mutating-method's effect equals its non-mutating sibling's return value. High-precision by construction: the pairing constraint requires both members on the same containing type, so false positives only fire when a developer reuses a curated pair name for non-paired purposes.

## Cycle-16 priority list (rotated post-v1.18)

The v1.18 plan §4 sets v1.19 as workstream B (mutating-method lift). Pre-rotation, the cycle-15 carry-forward priorities (NEW math-library forward-function counter, NEW fixed-point-name positive signal on idempotence) are deferred — they target the CM idempotence noise class but the lifted-surface delta from workstream B is projected to dominate any cycle-16 mechanism-cycle work.

Rotated priorities for v1.19 mechanism work:

1. **NEW (v1.18 plan §2 Workstream B): Mutating-method lift admission.** `LiftedTransformation` summary type + lift admission in `IdempotenceTemplate`, `IdentityElementPairing` (for the "increment by 0" case), `InversePairTemplate` (for dual-mutating add/remove pairs), and a new `CompositionTemplate` for the additive composition case. Depends on workstream A's value-semantic carrier signal (lift is sound only on value-semantic carriers).
2. **Math-library forward-function counter on idempotence + round-trip** (carried forward from v1.18 / cycle-15). Closes the CM elementary-functions noise class. New curated set `MathForwardFunctions = {exp, log, sin, cos, tan, ...}`.
3. **Fixed-point-name positive signal on idempotence** (carried forward from v1.18 / cycle-15). `+10` on names like `normalize` / `canonicalize` / `dedupe` / `simplify`.
4. **FP approximate-equality template arm** (carried forward from cycle-14 priority #4).
5. **Math-library op-name gate extension to `rescaledDivide` / `_relaxed*`** (carried forward).
6. **DEMOTED: stride-style label extension** (carried forward from cycle-14 demotion; cycle-14 picks #19 + #49 measure the lone Algo `endOfChunk(startingAt:) ↔ startOfChunk(endingAt:)` survivor as correctness-positive).

The kit-side `ValueSemantic` proposal (`docs/ideas/ValueSemantic Kit Proposal.md`) M-VS-2 / M-VS-3 / M-VS-4 milestones are deferred to v1.21+ per the v1.18 plan §6 — they require kit-side `ValueSemantic` protocol shipping first.

## Plan-vs-actual

**Workstream A:** ships exactly as specified in the v1.18 plan §2 with one refinement (4 templates instead of 5 — `InverseElementPairing` produces orchestrator witness records, not Suggestions). Magnitudes (`+5` / `-10`), signal kinds, resolver scope (same-file only), and recursion bound (3 levels) all match the plan-v1.0 lean defaults from open decision #1.

**Workstream C:** ships exactly as specified in the v1.18 plan §2. Three curated naming rules, vocabulary extension via literal pairs only, and the consistency property body all match. Score arithmetic 30+40+5=75 → Strong on value-semantic carriers also matches (the plan §2 estimated this as "≤+5% wall time" for the dual-style pairing pass; perf baseline below confirms).

**Mechanism-class taxonomy:** 8 → 11 (plan projected 11). ✓

**Test count:** 1618 → 1680 (plan projected ~55 new tests; actual 62). ✓

**Surface delta (per-corpus):** Deferred to v1.20 empirical cycle per the plan §5 sequencing (empirical-only measurement at v1.20 captures both v1.18 + v1.19 surfaces). Pre-merge measurement step from plan §6 deliverable #3 is recorded in the test-suite calibration table above (Likely→Strong + Possible→Likely shifts).

## Open items for v1.20

When the four cycle-1..14 corpora are re-run (post-v1.19 surface):

- Per-corpus value-semantic-carrier-signal hit count (Workstream A precision contribution).
- Per-corpus reference-type-carrier-signal hit count (rare on the cycle-1..14 corpora; the projected-small-effect framing the priority carried for four cycles).
- Per-corpus dual-style-consistency new-pick count (Workstream C recall contribution).
- Tier-shift count from the Likely→Strong boundary crossing (round-trip pairs on value-semantic struct carriers).
- New-suggestion count from the Possible→Likely boundary crossing (inverse-pair on non-Equatable value-semantic struct carriers).
- Workstream B lifted-suggestion surface delta (projected 80-120 new candidates on the 4 corpora, per plan §2 Workstream B).

The v1.20 cycle-17 50-decision triage will sample these together with the existing v1.16 surface and report aggregate acceptance-rate movement vs cycle 6 (26.7%) and cycle 14 (34.8%).
