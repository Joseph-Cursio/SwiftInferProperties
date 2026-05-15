# v1.81 Calibration Cycle 78 — Findings (V2.0.M6: Referential Integrity template)

Captured: 2026-05-15. swift-infer at v1.81.

## Headline

**Fourth interaction-template family ships.** v1.80 demonstrated the
one-cycle-per-family cadence; v1.81 extends it to PRD §5.5's
referential-integrity family with the same shape. Three new types in
SwiftInferTemplates plus the now-routine engine + stub-emitter
wiring:

- `ReferentialIntegrityWitness` — pairs a "selected" Optional ID
  field with an array collection.
- `ReferentialIntegrityWitnessDetector` — SwiftSyntax pass; selected
  field = Optional whose name starts with `selected`
  (case-insensitive); collection = array literal `[T]`. Cartesian-
  product pairing across the State struct.
- `ReferentialIntegrityInteractionTemplate` — predicate
  `state.<selected> == nil || state.<collection>.contains { $0.id == state.<selected> }`.
  Score 30 / `.possible`.

State-level boolean predicate → fits M4.D's per-step embedding
directly. The `unsupportedFamily` error now names only
`.biconditional` (M7) — the last family before §5's full scope ships.

Cycle-66's **52/103 = 50.5% measured-execution** carries forward —
v1.81 still touches no v1 emitter/resolver/carrier path.

## What M6 detects

| Side | Pattern | Constraint |
|---|---|---|
| Selected Optional | Name starts with `selected` (case-insensitive) + type is `T?` / `Optional<T>` / `Swift.Optional<T>` | Stored property; not computed/static |
| Collection | Type is `[T]` (array literal) | Stored property; dictionary `[K: V]` excluded |

**Cartesian-product pairing**: every selected-Optional × every array
in the State produces one witness. Two selecteds + three arrays = six
witnesses. Calibration will narrow.

**Predicate shape**: `state.<selected> == nil || state.<collection>.contains { $0.id == state.<selected> }`.
The `$0.id` reference requires the element type to conform to
`Identifiable` (or expose a comparable `id` property); non-conforming
types surface as `.architecturalCoveragePending` per M3.E.3's
outcome mapping. The `whyMightBeWrong` block names this caveat.

**What's deferred**:
- **Type-relationship resolution.** v0.0 is name-based — every
  `selected*` Optional pairs with every array. PRD §5.5 names the
  canonical shape as `selectedX: T.ID?` paired with `xs: [T]`; the
  refined detector would resolve `T.ID` to `T` and only pair
  matching element types. Calibration may make this the threshold.
- **Route / NavigationPath / Destination enums** (PRD §5.5 second
  witness shape) — needs enum-case-payload type analysis beyond
  state-field scanning. A future M6 refinement.
- **Reducer-body strengthening signal** (PRD §5.5 third witness:
  `.select` writes to ID + `.delete` clears collection without
  clearing selection). Same body-walking deferral as M5.
- **Stale-by-design counter-signal** (PRD §5.5: "selection may be
  allowed to be stale, e.g., the View interprets a missing
  selection as 'show empty state'"). Surfaced as a caveat in the
  why-might-be-wrong block, not auto-vetoed — calibration will tell
  us whether it should become an explicit suppression mechanism.

## One-cycle-per-family cadence holds

M4 sprawled across A/B/C/D/E because each piece introduced new
infrastructure (data model → first template → second template →
stub-emitter integration → CLI surface). M5 collapsed to one cycle
(witness + detector + template + engine dispatch + stub-emitter
arm). M6 holds the same shape:

- One feat commit (the four files + engine update + stub emitter
  arm + test files)
- One chore commit (version bump + cycle findings)

M7 (Biconditional) should be the same shape. After M7, PRD §5's
full v2.0 in-scope family set is covered (Conservation +
Idempotence lifted from v1 at M4.B/C; Cardinality + Referential
Integrity + Biconditional newly designed at M5/M6/M7).

## Test count

**2802 → 2825 (+23):**

- `ReferentialIntegrityWitnessDetectorTests` (+14):
  - Happy: basic selectedID + items, nested Inbox.State,
    Optional<T> sigil form, Cartesian-product 2×2, case-insensitive
    selected-prefix.
  - Negatives: no array / no selected / non-Optional /
    dictionary / computed / static / target-not-found.
  - Helper extractor: `nameLooksLikeSelected`.
- `RefIntegrityTemplateTests` (+10):
  - Empty / single witness emission
  - Predicate shape (selected + collection name substitution,
    `$0.id ==` form)
  - Score in `.possible` band
  - Explainability content (whySuggested names + caveats)
  - Identity stability + varies-by-witness
- `ActionSequenceStubEmitterInvariantTests` (no count change):
  swapped the `.referentialIntegrity throws` test for `.biconditional
  throws` + a positive `.referentialIntegrity embeds precondition`
  test.

§13 budgets unchanged.

## Drive-by trims

Two SwiftLint frictions surfaced from the M6 additions:

1. **ActionSequenceStubEmitter.swift went over 400 lines again**
   (was 402 lines pre-M6 trim; the `.referentialIntegrity` arm
   pushed it back over to 406). Compacted the long opening doc
   comment (35 lines → 17 lines). File now 391 lines — comfortable
   margin for M7's addition.
2. **`ReferentialIntegrityInteractionTemplateTests` was 44 chars**
   (lint cap 40). Renamed to `RefIntegrityTemplateTests` (25
   chars). Suite name unchanged — only the Swift type identifier
   shortened.

## What's next — M7

Biconditional / iff (PRD §5.6). Two State fields that should be
either both-set or both-unset:

> Witnesses: `(isLoadingX: Bool, taskX: Task<_, _>?)` or
> `(isShowingX: Bool, dataX: T?)` pair. Predicate:
> `state.isLoading == (state.activeTask != nil)`.

PRD §5.6 calibration note: this family is the trickiest of the five
because the two sides often live in different state layers (view-
state vs model-state) and drift out of sync — exactly where SwiftUI
race conditions show up. Expect cycles 3-5 worth of calibration to
dial precision.

PRD §5.6 framing nuance: the canonical biconditional pair contains a
`Task<_, _>?` or `AnyCancellable?` field, neither of which is
`Equatable`. The verifier doesn't require whole-State equality for
biconditional verify — the predicate is checked via *projected*
fields (`state.isLoading` Bool ↔ `state.activeTask != nil` Bool)
which are always Equatable.

M7 should fit the same one-cycle shape:
1. `BiconditionalWitness` — pair (boolField, optionalField)
2. `BiconditionalWitnessDetector` — pair Bool fields matching
   `is(Loading|Showing|Presenting).*` with Optional fields whose
   stem matches (e.g. `isLoadingX` ↔ `taskX?` or `dataX?`)
3. `BiconditionalInteractionTemplate` — predicate
   `state.<bool> == (state.<optional> != nil)`
4. Engine dispatch + stub emitter `.biconditional` arm
5. Tests

After M7, the v2.0 family-template surface is complete. Remaining
PRD §5.8 arc: M8 (subprocess verify for effect-bearing reducers),
M9 (InteractionInvariantBridge — kit-side `InteractionInvariant`
protocol family), M10 (drift mode for interaction invariants).

## Artifacts

- v1.81 sources:
  - `Sources/SwiftInferTemplates/ReferentialIntegrityWitness.swift`
  - `Sources/SwiftInferTemplates/ReferentialIntegrityWitnessDetector.swift`
  - `Sources/SwiftInferTemplates/ReferentialIntegrityInteractionTemplate.swift`
- Prior cycle: `docs/calibration-cycle-77-findings.md` (M5 —
  Cardinality template).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
