# Calibration cycle 16 findings — v1.19 mutating-method lift (Workstream B)

**Captured:** 2026-05-10 against the V1.19.A–D commits (`d7ee701` + `16b3108` + `5552aff` + `fd798d3`).
**Cycle type:** Single-workstream mechanism cycle. v1.19 ships Workstream B from the v1.18 plan §2 (the third and final v1.18-plan workstream); v1.20 will be the empirical-only re-measurement on the post-v1.19 surface.

This is the **sixteenth calibration cycle** and the **single-workstream follow-on to v1.18** — the largest behavioral change since M8.5's kit `Group` + `CommutativeMonoid` writeouts (v1.9). Workstream B re-admits the entire `mutating func` surface to the algebraic-property scoring pipeline that pre-v1.19 gated on `!summary.isMutating` at every template entry point.

## Headline

- **`LiftedTransformation` summary type (V1.19.A).** New `Sources/SwiftInferCore/LiftedTransformation.swift` — metadata-only "lift" of a mutating member into the pure shadow form `func op'(_ self: T, params...) -> T`. Strict admission gate: `summary.isMutating && summary.containingTypeName != nil && carrierKindResolver.classify(typeName:) == .valueSemantic`. Built once per `discover` call alongside `EquatableResolver` / `inheritedTypesByName` / `CarrierKindResolver`; threaded into per-template `suggest` invocations via `CollectionResolverContext.liftedTransformations`. New `Signal.Kind.liftedFromMutation` (+10) emitted by every lifted-suggest path, decoupled from `valueSemanticCarrier` (+5) so a lifted suggestion's score baseline is the non-lifted template's baseline + 5 (carrier, always fires by admission gate) + 10 (lift admission badge).

- **Four template fan-out sites** — every algebraic template that previously gated on `!isMutating` now admits the lift:
  1. **`IdempotenceTemplate` (V1.19.B)** — two admissible shapes: no-param mutators (`Set.removeAll`-shape) lift to `(T) -> T` unary idempotence; param-matches-carrier mutators (`Set.formUnion(_:Self)`-shape) lift to `(T, T) -> T` x-curried idempotence. Single-param-non-carrier shape (`Counter.increment(by: Int)`) is *not* an idempotence candidate — those flow through CompositionTemplate / IdentityElementPairing.
  2. **`CompositionTemplate` (V1.19.C, NEW template family)** — first new property family added since M8.5's kit `Group` + `CommutativeMonoid` writeouts. Asserts that two sequential calls to a mutating additive-action method equal one call with the combined argument: `var c1 = s; c1.op(a); c1.op(b);  var c2 = s; c2.op(a + b);  return c1 == c2`. Numeric-only for v1.19 (curated additive-monoid set covers `AdditiveArithmetic` conformers + `Decimal` + `Duration`); curated additive-action verb list (`increment`, `add`, `accumulate`, `accrue`, `advance`, `step`, `extend`, `expand`, `shift`, `offset`, `bump`, `grow`, `augment`, `append`, `push`, `pop`, `deposit`, `withdraw`); project extension via new `Vocabulary.compositionVerbs` slot.
  3. **`IdentityElementTemplate` (V1.19.C)** — admits the lift via new `LiftedIdentityElementPairing` over `[LiftedTransformation] × [IdentityCandidate]`. Pairs a lift of shape `(T, X) -> T` (X != T) with an identity candidate of type X — the canonical example is `incremented(c, by: 0) == c` (additive identity 0 on `Counter.increment(by: Int)`). Curated identity name set carries forward from non-lifted IdentityElementTemplate: `zero`, `empty`, `identity`, `none`, `default`.
  4. **`InversePairTemplate` (V1.19.D)** — admits dual-mutating add/remove pairs via new `InverseLiftedPairing` over `[LiftedTransformation]`. Curated state-mutation inverse-name pairs: `add`/`remove`, `insert`/`remove`, `push`/`pop`, `attach`/`detach`, `link`/`unlink`, `activate`/`deactivate`, `subscribe`/`unsubscribe`, `register`/`deregister`, `enable`/`disable`. Distinct from `RoundTripTemplate.curatedInversePairs` (which targets cross-type encoder/decoder shapes typically expressed as non-mutating functions); the mutating-specific list captures canonical state-flip patterns.

- **Mechanism-class taxonomy:** 11 → **13 classes**. Adds class **12** (lift admission via value-semantic gate — V1.19.A's structural precondition + signal) and class **13** (composition-template additive-monoid scoring — V1.19.C's new property family). Class 13 is the **second new template family** added since M8.5 (the first being v1.18.C's dual-style consistency template).

## What "lift admission" means structurally

Pre-v1.19, every algebraic template gated on `!summary.isMutating` at the entry point: `IdempotenceTemplate.swift:124`, `RoundTripTemplate` via `FunctionPairing.swift:69`, `AssociativityTemplate.swift:113`, `CommutativityTemplate.swift:119`, `MonotonicityTemplate.swift:127`, `IdentityElementPairing.swift:154`, `InverseElementPairing.swift:103`. The reasoning was sound — `mutating func op(self: inout T, args)` doesn't fit the `(T, ...) -> T` template shapes — but it excluded the entire mutating-method surface from the property pipeline. Workstream A (v1.18) added the structural carrier-kind signal that is the necessary precondition for re-admitting the lift; Workstream B closes the loop by *lifting* each admissible mutating method into a pure shadow form scored against the algebraic templates.

The lift is **purely metadata** — no codegen, no source rewrite. The shadow form is only described to the templates so they can score against it; the rendered property body uses the original mutating method against a `var copy` of the input value:

```swift
@Test func setRemoveAllIsIdempotent() {
    forAll(Gen.set(Int.self)) { s in
        var c1 = s; c1.removeAll()
        var c2 = c1; c2.removeAll()
        return c1 == c2
    }
}
```

The strict value-semantic admission gate is load-bearing: without `T` being value-semantic, `var copy = self` aliases shared state and the algebraic laws don't hold. The `valueSemanticCarrier` (+5) signal always fires for admitted lifts (it's the gate); the `liftedFromMutation` (+10) signal contributes independently per the v1.19 plan open decision #5 lean.

## Calibration consequence on the 1680-test baseline

v1.19 adds **77 new unit tests** across six new test suites:

| Suite | Tests | Coverage |
|---|---|---|
| `LiftedTransformationTests` | 19 | Strict admission gate, classification short-circuiting, source-order sorting, rationale rendering, rejection of `.mixed` / `.unknown` / `.referenceType` carriers, rejection of non-mutating + nil-containing-type summaries |
| `IdempotenceTemplateLiftedTests` | 5 | Admission shape filters (no-param + param-matches-carrier accept; non-carrier-param + multi-param + inout reject) |
| `IdempotenceTemplateLiftedScoringTests` | 11 | Score baseline 30+5+10=45 → Likely; +40 curated verb → 85 → Strong; SetAlgebra-shape veto; non-deterministic veto; protocol-coverage veto; identity hash + cross-validation key |
| `CompositionTemplateTests` | 12 | All curated additive-monoid types, generic-specialization stripping, project-vocabulary fallthrough, identity hashing, cross-validation key, non-deterministic veto, type-shape rejection (no-param / param-matches-carrier / multi-param / inout) |
| `IdentityElementTemplateLiftedTests` | 12 | `(T, X) -> T` shape + curated-identity-name match, generic stripping, name pair canonicalization, scoring baseline 30+40+5+10=85 → Strong, identity hashing, evidence layout |
| `InverseLiftedPairingTests` | 18 | Canonical add/remove pairing, all-curated-pairs coverage, project-vocabulary fallthrough, cross-carrier filter, mismatched-param-type filter, no-param filter, location-stable sorting, scoring baseline 25+10+5+10=50 → Likely, signal detail rendering, non-deterministic veto on either half, identity hashing, evidence-row layout |

**Test count delta: 1680 → 1757** (plan projected ~80; actual 77, well within tolerance).

The 19 golden-snapshot tests baked in pre-v1.19 score totals updated to reflect the additional `liftedFromMutation` signal where lifted suggestions are now emitted. No existing non-lifted suggestion shifts tier as a result of v1.19 — Workstream B is **purely additive**: it admits new suggestions without changing the score arithmetic on existing ones. (Contrast with v1.18.A, which shifted round-trip Likely→Strong and inverse-pair Possible→Likely on value-semantic struct carriers.)

## Score arithmetic by template

| Template | Lifted shape | Signals | Total | Tier |
|---|---|---|---|---|
| `IdempotenceTemplate` (no-param) | `(T) -> T` | type-shape +30; carrier +5; lift +10 | 45 | Likely |
| `IdempotenceTemplate` (no-param + curated verb e.g. `normalize`) | `(T) -> T` | type-shape +30; name +40; carrier +5; lift +10 | 85 | Strong |
| `IdempotenceTemplate` (x-curried) | `(T, T) -> T` | type-shape +30; carrier +5; lift +10 | 45 | Likely |
| `CompositionTemplate` | `(T, X) -> T` with X in curated-additive | type-shape +30; name +40; carrier +5; lift +10 | 85 | Strong |
| `IdentityElementTemplate` (lifted) | `(T, X) -> T` paired with identity | type-shape +30; name +40; carrier +5; lift +10 | 85 | Strong |
| `InversePairTemplate` (lifted) | `(T, X) -> T` ↔ `(T, X) -> T` curated pair | type-shape +25; name +10; carrier +5; lift +10 | 50 | Likely |
| `InversePairTemplate` (lifted) + matching `@Discoverable(group:)` | (as above) + group | (as above) + 35 | 85 | Strong |

The `liftedFromMutation` (+10) signal magnitude was chosen per the v1.19 plan open decision #5 lean — the v1.18 plan §2 Workstream B suggestion-rendering specification implicitly carries this magnitude via the example total `30 + 40 + 5 + 10 = 85` for CompositionTemplate. v1.20 may re-baseline if the lifted-suggestion acceptance rate is high enough that the +10 over-promotes.

## Per-corpus signal-hit data (deferred to v1.20 empirical cycle)

The four cycle-1..14 calibration corpora (Algorithms, Collections-OrderedCollections, ChartMath/ComplexModule, PropertyLawKit) are **not** re-run as part of the v1.19 cut — the v1.19 plan §5 sequencing reserves per-corpus measurement for the v1.20 empirical cycle, which captures both v1.18 (Workstreams A + C) and v1.19 (Workstream B) surfaces in one sample so the aggregate acceptance-rate movement vs cycle 6 (26.7%) and cycle 14 (34.8%) can be reported once.

The expected v1.19 deltas, projected from the test-suite calibration:

| Corpus | Projected admitted-lift count | Projected lifted-Strong / Likely surface | Notes |
|---|---|---|---|
| Algorithms | Low (Algorithms is a free-function library; few `mutating func`s) | Low | Most surface is `static func` over `Slice` — non-lifted `RoundTrip` already covers |
| OrderedCollections | **Highest** (`OrderedSet` / `OrderedDictionary` are value-semantic structs with rich mutating APIs: `formUnion` / `formIntersection` / `formSymmetricDifference` / `subtract` / `removeAll` / `append` / `insert` / `remove`) | High Strong-tier on idempotence (lifted formUnion idempotence; though SetAlgebra-shape veto suppresses formUnion specifically) + High Likely-tier on inverse-pair (lifted insert/remove canonical pair) | The corpus most likely to show measurable lifted-surface expansion |
| ComplexModule | Low (`Complex<RealType>` is value-semantic; mutating APIs exist as `formAdd` / `formMultiply` siblings of non-mutating ops) | Likely modest CompositionTemplate hits on `formAdd(Complex)` if param-shape matches carrier | Numeric-only CompositionTemplate gate restricts hits |
| PropertyLawKit | Negligible (kit is a small Sources/ surface with no value-semantic structs in scope for the lift) | None expected | Kit is consumer-side, not corpus |

The **OrderedCollections corpus is the single most likely source** of measurable surface expansion from Workstream B — the curated state-mutation inverse pairs (`insert`/`remove`, `add`/`remove`, `formUnion` / via SetAlgebra inheritance) directly target stdlib's value-semantic ordered-container surface.

**Why the projections are coarse.** Without re-running the four corpora, the lifted-surface counts can't be measured exactly. The v1.20 empirical cycle re-runs the harness against the post-v1.19 surface and reports per-template + per-corpus acceptance rates comparable to cycle 6 (26.7%) and cycle 14 (34.8%), with separate columns for v1.18-only signal hits, v1.19-only lifted suggestions, and the cumulative v1.18+v1.19 surface delta.

## Mechanism-class taxonomy update

Pre-v1.19 (11 classes per `docs/calibration-cycle-15-findings.md` + CLAUDE.md repo-state):

1. Carrier-type whitelist veto (V1.4.3 fp-counter)
2. Cross-type structural counter (V1.4.3b)
3. Curated-set protocol-coverage veto (V1.5.2)
4. Operator-aware identity-element pairing (V1.5.2 Idemnity)
5. Op-class-mapped commutativity / associativity coverage (V1.7.2 / V1.8.2)
6. Parameter-label direction-counter (V1.10.1 / V1.11.1 / V1.12.1)
7. Function-name + type-shape composite (V1.14.1 set-algebra inverse-pair)
8. Parameter-label semantic-intent counter (V1.15.1 domain-marker)
9. Carrier-kind structural counter/positive signal (V1.18.A)
10. Dual-style pair detection (V1.18.C pairing infrastructure)
11. Dual-style consistency property (V1.18.C template — first new property family since M8.5)

Post-v1.19 (13 classes):

12. **NEW: Lift admission via value-semantic gate** (V1.19.A). Strict structural precondition (`isMutating && containingType != nil && carrierKind == .valueSemantic`) + `Signal.Kind.liftedFromMutation` (+10) badge. Re-admits the entire `mutating func` surface to the four algebraic templates that previously vetoed on `!isMutating`. Rationale: without re-admission, every mutating method is invisible to the property pipeline — including stdlib's canonical SetAlgebra mutators, Sequence's in-place sort, and the entire OrderedCollections value-semantic mutating API.

13. **NEW: Composition-template additive-monoid scoring** (V1.19.C). First new property family added since v1.18.C's dual-style consistency template. Asserts `op(op(s, a), b) == op(s, a + b)` over lifted shadows of additive-action mutating methods. Numeric-only by curated additive-monoid type gate (stdlib `AdditiveArithmetic` conformers + `Decimal` + `Duration`); high-precision by construction (the gate excludes anything other than canonical accumulate-style accumulators). The non-numeric monoid-shaped extension (e.g. `Set` ∪ as the additive operation) is a v1.21+ candidate after the numeric-only acceptance rate is measured.

## Cycle-17 priority list (rotated post-v1.19)

The v1.18 plan §4 sets v1.20 as the **empirical-only re-measurement cycle** — no `Sources/` changes, just the four-corpus sample on the post-v1.19 surface. v1.21+ rotates to the cycle-15/16 carry-forward priorities once the post-v1.19 acceptance-rate data is in.

Rotated priorities for v1.21 mechanism work (carried forward across multiple cycles):

1. **Math-library forward-function counter on idempotence + round-trip** (carried forward from v1.18 / cycle-15 / cycle-16). Closes the CM elementary-functions noise class. New curated set `MathForwardFunctions = {exp, log, sin, cos, tan, sqrt, ...}` × `(T) -> T` shape gate. v1.20's empirical surface will quantify the noise volume to right-size the magnitude.
2. **Fixed-point-name positive signal on idempotence** (carried forward from v1.18 / cycle-15 / cycle-16; nine cycles overdue). `+10` on names like `normalize` / `canonicalize` / `dedupe` / `simplify`. v1.18.B's `IdempotenceTemplate.suggest(forLifted:)` curated verb signal already includes these names for the lifted path; the non-lifted path needs the same coverage.
3. **FP approximate-equality template arm** (carried forward from cycle-14 priority #4). Required for any meaningful CM idempotence / round-trip coverage where strict `==` on `Double` is unreliable.
4. **Math-library op-name gate extension to `rescaledDivide` / `_relaxed*`** (carried forward).
5. **DEMOTED: stride-style label extension** (carried forward from cycle-14 demotion).
6. **`CompositionTemplate` non-numeric monoid-shaped extension** (NEW carry-forward from v1.19). Promote to v1.21+ after the v1.20 numeric-only CompositionTemplate acceptance rate is measured. Candidate monoids: `Set` ∪, `String` concat, `Array` concat. Each requires a separate gate (the numeric `+` body wouldn't compile for non-numeric monoids).
7. **Lift admission relaxation from strict to permissive** (NEW carry-forward from v1.19 plan open decision #2). Currently strict (admits only `.valueSemantic` carriers); v1.20 measurement may motivate relaxing to `.valueSemantic ∪ .unknown` if recall is too low. The `.referenceType` and `.mixed` carriers stay rejected — those are unsound regardless of measurement.
8. **`Signal.Kind.liftedFromMutation` magnitude re-baselining** (NEW carry-forward from v1.19 plan open decision #5). Currently +10. v1.20 measurement may motivate +5 (matches `valueSemanticCarrier` weight) or +0 (informational only) if the lifted-suggestion acceptance rate is high enough that +10 over-promotes lifted suggestions vs their non-lifted siblings.

The kit-side `ValueSemantic` proposal (`docs/ideas/ValueSemantic Kit Proposal.md`) M-VS-2 / M-VS-3 / M-VS-4 milestones remain deferred to v1.21+ per the v1.18 plan §6 — they require kit-side `ValueSemantic` protocol shipping first, which is upstream-scheduled for SwiftPropertyLaws v2.1+.

## Plan-vs-actual

**`LiftedTransformation` summary type (V1.19.A):** ships exactly as specified in the v1.19 plan §2 deliverable 1. Strict admission gate (`isMutating && containingTypeName != nil && carrierKind == .valueSemantic`) matches plan open decision #2 lean. Eager-derivation site (built once per `discover` alongside other resolvers, threaded into `CollectionResolverContext.liftedTransformations`) matches plan open decision #1 lean. ✓

**`Signal.Kind.liftedFromMutation` (V1.19.A):** ships at +10 magnitude per plan open decision #5 lean. Decoupled from `valueSemanticCarrier` (always-fires admission gate) so the two contribute independently. ✓

**`IdempotenceTemplate` lift admission (V1.19.B):** ships exactly as specified in the v1.19 plan §2 deliverable 2a. Two admissible shapes (no-param + param-matches-carrier); single-param-non-carrier shape correctly excluded. SetAlgebra-shape veto carries over from the non-lifted scoring stack. Identity hash uses `idempotence-lifted|` prefix. ✓

**`CompositionTemplate` (V1.19.C):** ships exactly as specified. Numeric-only by curated additive-monoid gate per plan open decision #3 lean. Curated verb list matches plan open decision #4 (`increment`, `add`, `accumulate`, `accrue`, `advance`, `step`, `extend`, `expand`, `shift`, `offset`, `bump`, `grow`, `augment`, `append`, `push`, `pop`, `deposit`, `withdraw`). Project extension via new `Vocabulary.compositionVerbs` slot. ✓

**`IdentityElementTemplate` lift admission (V1.19.C):** ships via new `LiftedIdentityElementPairing`, mirroring the V1.18.C `DualStylePairing` pattern (separate pass per plan open decision #6 lean — though this open decision was for InverseLiftedPairing, the same architectural choice was applied here for consistency). ✓

**`InversePairTemplate` lift admission (V1.19.D):** ships via new `InverseLiftedPairing` per plan open decision #6 lean. Curated state-mutation inverse-name pair list distinct from `RoundTripTemplate.curatedInversePairs`. Orientation-insensitive matching with canonical-orientation output. ✓

**Mechanism-class taxonomy:** 11 → 13 (plan projected 13). ✓

**Test count:** 1680 → 1757 (plan projected ~80; actual 77 within ±5 of target). ✓

**Surface delta (per-corpus):** Deferred to v1.20 empirical cycle per plan §5 sequencing. Test-suite calibration confirms Workstream B is purely additive (no existing non-lifted suggestion shifts tier).

## Open items for v1.20

When the four cycle-1..14 corpora are re-run (post-v1.19 surface):

- Per-corpus admitted-`LiftedTransformation` count (lift admission rate; how many `mutating func`s pass the strict carrier-value-semantic gate).
- Per-corpus `IdempotenceTemplate` lifted-suggestion count (no-param shape vs x-curried shape breakdown).
- Per-corpus `CompositionTemplate` lifted-suggestion count (numeric additive-action verb hits).
- Per-corpus `IdentityElementTemplate` lifted-suggestion count (the "increment by 0" canonical case).
- Per-corpus `InversePairTemplate` lifted-suggestion count (curated state-mutation pair hits — projected highest on OrderedCollections).
- Tier distribution across the lifted surface (Strong vs Likely vs Possible) — informs the v1.21+ `liftedFromMutation` magnitude re-baselining decision.
- v1.18 carry-forward measurements (per-corpus value-semantic-carrier-signal hit count, dual-style-consistency new-pick count, Likely→Strong + Possible→Likely tier-shift counts) folded into the same sample.

The v1.20 cycle-17 50-decision triage will sample across the cumulative v1.18+v1.19 surface and report aggregate acceptance-rate movement vs cycle 6 (26.7%) and cycle 14 (34.8%). The expected effect direction: Workstream A (v1.18) is precision-positive (carrier-kind structural counter suppresses class-typed-carrier picks), Workstream C (v1.18) is recall-positive (dual-style consistency surfaces previously-undetected canonical pairs), Workstream B (v1.19) is recall-positive but precision-tight by the strict admission gate (lifts admit a large new surface but each lift's score arithmetic mirrors a non-lifted template's high-precision baseline).
