# v1.80 Calibration Cycle 77 — Findings (V2.0.M5: Cardinality template)

Captured: 2026-05-15. swift-infer at v1.80. SwiftPropertyLaws at v2.2.0.

## Headline

**First non-lifted interaction-template family ships.** Conservation
(M4.B) + Idempotence (M4.C) were lifted from v1's algebraic surface;
Cardinality (M5) is the first family designed natively for the v2.0
interaction-invariant taxonomy. Three new types in SwiftInferTemplates
+ wired through the existing engine + stub-emitter pipeline:

- `CardinalityWitness` + `CardinalityFieldKind` — value type pairing
  ≥ 2 presentation-shaped State fields. One witness per State; the
  invariant is "across ALL of these, at most one is active
  simultaneously."
- `CardinalityWitnessDetector` — SwiftSyntax pass with two field
  matchers: Bool fields containing `Showing`/`Presenting`
  (case-sensitive Swift camelCase), Optional fields whose
  lowercased name contains `sheet`/`alert`/`fullscreencover`/
  `popover`.
- `CardinalityInteractionTemplate` — emits suggestions with predicate
  `(<indicator-1> ? 1 : 0) + ... + (<indicator-n> ? 1 : 0) <= 1`.
  Score 30 (`.possible` band per PRD §3.5 corollary).

Cardinality fits M4.D's per-step embedding because the predicate
is a state-level boolean — same shape as Conservation. No new
stub-emitter loop needed; `makePerStepCheck` just gained a
`.cardinality` arm alongside `.conservation`.

Cycle-66's **52/103 = 50.5% measured-execution** carries forward —
v1.80 still touches no v1 emitter/resolver/carrier path.

## Why one cycle (not five)

M4 sprawled across A/B/C/D/E because each piece introduced new
infrastructure: data model (M4.A), first template (M4.B), second
template + predicate-format decision (M4.C), stub-emitter integration
(M4.D), CLI surface (M4.E). M5 reuses every one of those —
adding a new family is now a single-commit operation:

1. Witness value type + detector
2. Template + scoring
3. Engine dispatch entry
4. (Sometimes) stub-emitter `makePerStepCheck` arm

That collapse is the M4 infrastructure paying off — adding M6
(Referential integrity) and M7 (Biconditional) should now be the
same one-cycle shape as M5.

## What M5 detects

| Field shape | Name pattern | Indicator |
|---|---|---|
| `Bool` stored property | Contains `Showing` or `Presenting` (case-sensitive) | `state.<name>` |
| `T?` / `Optional<T>` stored property | Lowercased name contains `sheet` / `alert` / `fullscreencover` / `popover` | `state.<name> != nil` |

Both can mix in one State — the witness's `fields` array stores them
all and the predicate sums them via `(indicator ? 1 : 0)` ternaries.

**Filters applied at detection:**
- Computed properties skipped (no invariant to verify — the State
  doesn't track an enforceable cardinality if the value is recomputed
  per read).
- Static / class properties skipped (instance-level cardinality
  only).
- Fewer than 2 matching fields → no witness emitted (cardinality
  needs ≥ 2 by construction).

**Not yet detected (calibration scope):**
- **Reducer-body strengthening signal** (PRD §5.4 third witness):
  walking `.show*` action handlers for "writes true to one without
  clearing the others." Adding this would bump the score above the
  default 30 and earn the suggestion `.likely` or `.strong` tier.
  Deferred to a future M5 refinement.
- **Threshold tuning.** PRD §5.4 calibration note: the "≥ 2 fields"
  heuristic is deliberately crude. First calibration cycles may
  raise the threshold or refine name patterns.

## Architectural choices

**Predicate shape: state-level boolean.** Cardinality fits the
Conservation-shape rather than the Idempotence-shape. M4.D's
`makePerStepCheck` got a `.cardinality` arm; `makePostLoopCheck`
left `.cardinality` returning empty (no post-loop work needed).
`validateInvariant` allows `.cardinality` through. The
`unsupportedFamily` error now names Referential integrity (M6) +
Biconditional (M7).

**File-scope `CardinalityFieldKind` enum.** Initially nested
inside `CardinalityWitness.Field`, but that triggered SwiftLint's
1-level nesting cap. Hoisted to file scope; `Field.kind` references
the file-scope enum. Trade-off: slightly more verbose at the call
site (`CardinalityFieldKind.boolFlag` instead of
`CardinalityWitness.Field.Kind.boolFlag`), but the lint rule is
load-bearing — matches the `VerifyError` / `AcceptCheckResult`
hoisting pattern elsewhere in the codebase.

**One witness per State (not Cartesian-product).** Conservation
pairs aggregates × collections by Cartesian product; Cardinality
collects all matching fields into a single witness. Reason: the
Cardinality invariant is mutually-exclusive-across-all-fields, not
per-field-pair. One field set → one predicate → one suggestion.

## Test count

**2777 → 2802 (+25):**

- `CardinalityWitnessDetectorTests` (+15): detection paths (2
  Optionals, 2 Bools, mixed kinds, fullScreenCover + popover),
  negatives (single field, name mismatch, computed/static skipped,
  target not found), helper extractors (isBoolType /
  isOptionalType / matchesBoolPattern / matchesOptionalPattern).
- `CardinalityInteractionTemplateTests` (+10): empty/single
  witness, predicate shape (Optional / Bool / mixed kinds),
  score in `.possible` band, why-suggested / why-might-be-wrong
  content, identity stability + varies-by-fields.
- `ActionSequenceStubEmitterInvariantTests` adjustments:
  swapped the now-obsolete "cardinality throws" test for a
  "referentialIntegrity throws" test + a positive "cardinality
  embeds precondition" test.

§13 budgets unchanged.

## What's next — M6 / M7

M6 — **Referential integrity** (PRD §5.5). State has a "selected
ID" field referencing an entity in a collection:

> Witnesses: `selectedX: T.ID?` field paired with `xs: [T]` field
> where `T: Identifiable`. A route/path enum carrying an ID-typed
> payload. Reducer handlers for `.select(_:)` write to the ID field
> but `.delete(_:)` clears the collection without clearing the
> selection.

M6 is structurally similar to Conservation (paired stored
properties in State) but adds the `Identifiable.ID` type-matching
constraint. The detector walks for `selectedX: T.ID?` + `xs: [T]`
pairs where the ID types match. Predicate:
`state.selectedX == nil || state.xs.contains { $0.id == state.selectedX }`.

M7 — **Biconditional / iff** (PRD §5.6). Two State fields that
should be either both-set or both-unset:

> Witnesses: `(isLoadingX: Bool, taskX: Task<_, _>?)` or
> `(isShowingX: Bool, dataX: T?)` pair where reducer handlers may
> clear only one of the two. Predicate:
> `state.isLoading == (state.activeTask != nil)`.

Both are state-level boolean predicates → fit Conservation/Cardinality
per-step embedding directly. M6 + M7 should each be one-cycle ships
mirroring M5's shape.

After M7, the four families plus M4's lifted Conservation +
Idempotence cover PRD §5's full v2.0 in-scope set. Remaining
arc:

- **M8** — Subprocess verify path for effect-bearing reducers.
- **M9** — InteractionInvariantBridge (kit-side `InteractionInvariant`
  protocol family).
- **M10** — Drift mode for interaction invariants.

## Artifacts

- v1.80 sources:
  - `Sources/SwiftInferTemplates/CardinalityWitness.swift`
  - `Sources/SwiftInferTemplates/CardinalityWitnessDetector.swift`
  - `Sources/SwiftInferTemplates/CardinalityInteractionTemplate.swift`
- Prior cycle: `docs/calibration-cycle-76-findings.md` (M4 — first
  interaction-template families).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
