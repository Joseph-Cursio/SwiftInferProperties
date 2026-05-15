# v1.82 Calibration Cycle 79 — Findings (V2.0.M7: PRD §5 full family set complete)

Captured: 2026-05-15. swift-infer at v1.82.

## Headline

**PRD §5's full v2.0 in-scope family set is shipped.** v1.79–v1.81
delivered Conservation + Idempotence (lifted from v1) + Cardinality +
Referential Integrity; v1.82 ships **M7 — Biconditional / iff** as
the fifth and final family for v2.0's in-scope set.

Three new types in SwiftInferTemplates (same one-cycle shape as M5 /
M6):

- `BiconditionalWitness` — pairs a Bool flag with an Optional field
  whose presence should track the flag.
- `BiconditionalWitnessDetector` — Bool fields containing
  `Loading` / `Showing` / `Presenting` / `Active` / `Fetching` /
  `Refreshing` (case-sensitive) × all Optional fields,
  Cartesian-product paired.
- `BiconditionalInteractionTemplate` — predicate
  `state.<bool> == (state.<optional> != nil)`. Score 30 /
  `.possible`.

State-level boolean predicate → fits M4.D's per-step embedding
shape. `ActionSequenceStubEmitter.makePerStepCheck` gains a
`.biconditional` arm. `validateInvariant` no longer throws — all
five families now have an emission path.

Cycle-66's **52/103 = 50.5% measured-execution** carries forward —
v1.82 still touches no v1 emitter/resolver/carrier path.

## PRD §5's family set, complete

| Family | Shipped at | Predicate shape |
|---|---|---|
| Conservation | M4.B (v1.79) | `state.<agg> == state.<coll>.count` (count variant) |
| Idempotence | M4.C (v1.79) | `<dot-shorthand action case>` (post-loop double-apply) |
| Cardinality | M5 (v1.80) | `(<i1> ? 1 : 0) + ... + (<in> ? 1 : 0) <= 1` |
| Referential Integrity | M6 (v1.81) | `state.<sel> == nil \|\| state.<coll>.contains { $0.id == state.<sel> }` |
| Biconditional / iff | M7 (v1.82) | `state.<bool> == (state.<optional> != nil)` |

Four families embed per-step via `precondition(<predicate>)`;
Idempotence uses the post-loop double-apply check. Trap-as-failure
flows through M3.E.3's outcome parser → `.measuredDefaultFails`.

## What M7 detects

| Side | Pattern | Constraint |
|---|---|---|
| Bool flag | Name contains `Loading` / `Showing` / `Presenting` / `Active` / `Fetching` / `Refreshing` (case-sensitive Swift camelCase) | Type is `Bool` / `Swift.Bool`; stored property; not computed/static |
| Optional | Type is `T?` / `Optional<T>` / `Swift.Optional<T>` | Stored property |

**Cartesian-product pairing**: every flag × every Optional in the
State produces one witness. v0.0 deliberately broad; PRD §5.6
calibration note flags this as "trickiest of the five families,"
expecting 3–5 cycles before stable acceptance rate.

**Why no Equatable State requirement** (PRD §5.6 nuance): the
canonical biconditional pair contains `Task<_, _>?` or
`AnyCancellable?`, neither Equatable. The predicate operates on
*projected* Bool fields (`state.<bool>` and `state.<optional> != nil`)
which are always Equatable; State-as-a-whole equality isn't needed.
The Identifiable runtime gate that M6 has doesn't apply here either
— `!= nil` works on any Optional.

**What's deferred**:
- **Stem-matching pairing** (`isLoadingX` ↔ `taskX?`). v0.0 is
  Cartesian; stem-matching would tighten precision but risks
  under-matching valid pairs whose two sides don't follow the
  naming convention.
- **Reducer-body strengthening signal** (PRD §5.6 third witness:
  "`.startX` sets both and `.cancelX` clears both — but at least
  one handler clears only one of the pair"). Same body-walking
  deferral as M5 / M6.

## One-cycle-per-family cadence holds across three families

| Cycle | Family | Sub-cycles | Test delta |
|---|---|---|---|
| 77 | Cardinality | 1 (feat) + 1 (chore) | +25 |
| 78 | Referential Integrity | 1 (feat) + 1 (chore) | +23 |
| 79 | Biconditional | 1 (feat) + 1 (chore) | +23 |

M4's infrastructure investment paid off cleanly. Adding a fifth
family is exactly the shape of adding the fourth — no new
infrastructure decisions, just the family-specific witness +
detector + template + per-step arm.

## Test count

**2825 → 2848 (+23):**

- `BiconditionalWitnessDetectorTests` (+13): happy paths
  (isLoading+activeTask, isShowingSheet+sheet, all the bool
  patterns, Cartesian-product 2×2, nested Inbox.State); negatives
  (unmatched bool name, bool without optional, optional without
  bool, computed/static skipped, case-sensitive); helper extractors.
- `BiconditionalTemplateTests` (+10): empty/single witness,
  predicate shape + name substitution, score in `.possible` band,
  explainability content, identity stability + varies.
- `ActionSequenceStubEmitterInvariantTests` adjustments:
  `biconditionalIsUnsupported` → `biconditionalEmbedsPrecondition`
  (the unsupportedFamily error has no remaining arms — function
  reframed as a forward-compat hook).

§13 budgets unchanged.

## v2.0 surface, end-to-end

A user can now run:

```bash
swift-infer discover-reducers --target MyApp
swift-infer discover-interaction --target MyApp --include-possible
# Output includes Conservation + Idempotence + Cardinality
# + Referential Integrity + Biconditional suggestions.
swift-infer verify-interaction --target MyApp --reducer Inbox.body
# Verifies the chosen reducer against the embedded invariant.
```

All five families produce suggestions at default-`.possible`
visibility per PRD §3.5 corollary. Calibration cycles will refine
the scoring weights, narrow the witness patterns, and earn
promotion to `.likely` / `.strong` per the three-cycles-stable
rule.

## What's next — M8 / M9 / M10

PRD §5.8's remaining arc:

- **M8 — Subprocess verify path** for effect-bearing reducers.
  The synthesized workdir already supports this via
  `WorkdirMode.algebraic` shape (v1.42+). M8's work is routing
  effect-bearing reducers (those that fail M3.A's
  `ReducerPurityAnalyzer`) to the subprocess path with their
  invariant predicates embedded.
- **M9 — InteractionInvariantBridge.** Kit-side
  `InteractionInvariant` protocol family + conformance
  suggestion when ≥ 3 Strong invariants fire on the same
  reducer. Analog of v1's RefactorBridge — cross-repo
  coordination (SwiftPropertyLaws kit minor bump).
- **M10 — Drift mode** for interaction invariants. Per-baseline
  warning on new Strong-tier interaction suggestions added since
  baseline. Mirrors v1's drift mechanism.

Calibration cycles can start in parallel — each new-family
M-milestone needs three cycles of stable acceptance rate before
promotion. M5–M7 are eligible to start their calibration arc now
that detection ships.

## Artifacts

- v1.82 sources:
  - `Sources/SwiftInferTemplates/BiconditionalWitness.swift`
  - `Sources/SwiftInferTemplates/BiconditionalWitnessDetector.swift`
  - `Sources/SwiftInferTemplates/BiconditionalInteractionTemplate.swift`
- Prior cycle: `docs/calibration-cycle-78-findings.md` (M6 —
  Referential Integrity template).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
