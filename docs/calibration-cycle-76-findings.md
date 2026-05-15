# v1.79 Calibration Cycle 76 — Findings (V2.0.M4: first interaction-template families)

Captured: 2026-05-15. swift-infer at v1.79. SwiftPropertyLaws at v2.2.0 (pushed; smoke test in repo).

## Headline

**The v2.0 end-to-end flow is online.** v1.78 closed M3 to consumer-
completeness (kit tag published, repo pin bumped, M2 smoke test in
place). v1.79 ships **M4 — the first interaction-template families**.
Five sub-cycles deliver the layer:

- **M4.A** — `InteractionInvariantSuggestion` data model in Core +
  `InteractionTemplateEngine` namespace stub in Templates.
- **M4.B** — Conservation template (count-shaped variant). Walks the
  State struct for stored count-shaped aggregate + array collection
  pairs; emits one suggestion per pair with predicate
  `state.<aggregate> == state.<collection>.count`.
- **M4.C** — Idempotence template. Walks the Action enum for cases
  whose name matches the curated idempotent-action set (exact-match:
  refresh / reset / clear / dismiss / cancel / close / hide / select;
  prefix-match: set* / select* / show* / present*).
- **M4.D** — `ActionSequenceStubEmitter` learns to embed
  family-specific verifier loops. Conservation embeds
  `precondition(<predicate>)` per step; Idempotence emits a
  post-loop double-apply check.
- **M4.E** — `swift-infer discover-interaction` subcommand surfacing
  tiered suggestions per PRD §3.6 step 2 + §4.5 explainability shape.

After M4, a user can run:

```
swift-infer discover-reducers --target MyApp
swift-infer discover-interaction --target MyApp --include-possible
swift-infer verify-interaction --target MyApp --reducer Inbox.body
```

and get the full discovery → suggestion → verify flow, with real
invariants checked (not just "ran cleanly / trapped").

Cycle-66's **52/103 = 50.5% measured-execution** carries forward
unchanged — v1.79 still touches no v1 emitter / resolver / carrier
path.

## What the five sub-cycles ship

### M4.A — data model + engine namespace

`InteractionInvariantSuggestion` (Core) — value type carrying:
- `identity: SuggestionIdentity` (SHA256-prefix shape — same as v1
  algebraic suggestions; canonical input is
  `<family>::<reducerQualifiedName>::<predicate>`)
- `family: InteractionInvariantFamily` (5 cases — Conservation /
  Idempotence ship at M4.B/C; Cardinality / Referential integrity /
  Biconditional reserve their slots for M5 / M6 / M7)
- reducer metadata mirrored from the source `ReducerCandidate`
- `predicate: String` — Swift-source predicate (Conservation) or
  family-specific data (Idempotence's dot-shorthand action case)
- `score: Int` / `tier: Tier` — same scale as v1
- `whySuggested` / `whyMightBeWrong` — PRD §4.5 explainability
- `firstSeenAt: Date` — §17.2 time-to-adoption anchor

`InteractionTemplateEngine` namespace in Templates with
`analyze(candidates:sourcesDirectory:firstSeenAt:)` dispatch entry.
Drive-by: added `Codable` to `SuggestionIdentity` so the new value's
synthesized Codable works.

### M4.B — Conservation template (count-shaped variant)

Detection scope at v0.0:
- Aggregate name contains `count` (case-insensitive): `count`,
  `itemCount`, `numEntries` (via `count` substring), `Count`-suffix.
- Aggregate type is integer (Int / UInt / Int32 / etc., plus
  `Swift.`-qualified equivalents). Floating-point aggregates
  filtered at detection per PRD §5.2 counter-signal.
- Collection is array literal `[T]`. Dictionary `[K: V]` rejected
  via depth-counted top-level-colon check.
- Stored property only (computed properties skipped); non-static.

Predicate: `state.<aggregate> == state.<collection>.count`.

Score: 30 (lands in `.possible` band per PRD §3.5 corollary —
default-Possible for three calibration cycles before promotion).

Sum/total-shaped aggregates (`total: Decimal` paired with
`items: [LineItem]` summing `\.price`) defer to a later refinement —
they need per-element field detection.

### M4.C — Idempotence template

Detection scope at v0.0:
- Exact-match case names: `refresh`, `reset`, `clear`, `dismiss`,
  `cancel`, `close`, `hide`, `select` (PRD §5.3's `select(id)`
  example).
- Prefix-match case names: `set*`, `select*`, `show*`, `present*`
  (with `select` covered exact, so bare `select` routes through
  exact-match).
- Case-insensitive; multi-element cases (`case foo, bar`) produce
  one witness per matching element.

Predicate format: `predicate` carries the bare action-case
dot-shorthand (`.refresh` / `.setColor`). Different shape from
Conservation's boolean expression — M4.D's stub emitter branches on
`family` to interpret.

Score: 30 (same `.possible` band as Conservation).

Reducer-body-purity check (PRD §5.3 counter-signal: "Action body has
side effects via Effect or async → downgrade to Likely") deferred —
M3.A's `ReducerPurityAnalyzer` is a natural fit when the surface
extends to action-specific body analysis.

### M4.D — family-aware predicate embedding

`ActionSequenceStubEmitter.Inputs.invariant` — optional
`InteractionInvariantSuggestion`. Default `nil` preserves M3.B's
"ran cleanly / trapped" mode (existing tests unmodified).

When supplied, emit branches on `invariant.family`:

- **Conservation** — `precondition(<predicate>, "Conservation
  invariant violated")` after each `state = reduce(state, action)`
  step inside the inner loop.
- **Idempotence** — post-loop double-apply check. Two signature shapes:
  - `(S, A) -> S`: `let once = reduce(state, .X); let twice =
    reduce(once, .X); precondition(once == twice)`
  - `(inout S, A) -> Void`: copy-and-mutate dance via temporary
    `var`s.
- **Cardinality / Ref integrity / Biconditional** —
  `EmitError.unsupportedFamily` (M5–M7 territory).

Trap mechanic: `precondition(_:)` traps in both debug and release
builds. The trap propagates as a non-zero exit code, which M3.E.3's
parser maps to `.measuredDefaultFails` — outcome flow handles
invariant violations naturally.

Drive-by: `emit(_:)` grew past SwiftLint's `function_body_length`
cap with per-step + post-loop blocks. Extracted `assembleStub`,
`makePerStepCheck`, `makePostLoopCheck`, `makeIdempotenceCheck`
helpers.

### M4.E — discover-interaction CLI

Subcommand with three flags: `--target` (required) / `--reducer`
(optional pin) / `--include-possible` (flag, default false). The
pipeline:
1. Walks `Sources/<target>/` via `ReducerDiscoverer.discover`
2. Optional `--reducer` filter via `ReducerPin.parse + matches`
3. Runs `InteractionTemplateEngine.analyze` (Conservation +
   Idempotence dispatch)
4. Renders via `InteractionSuggestionRenderer`

Rendered output per PRD §4.5: family / score+tier / reducer /
location / state / action / predicate, then two-sided
"why suggested" / "why this might be wrong" bullet blocks, then
identity hash.

Calibration-aware sentinel: when all suggestions are `.possible` and
the flag is off, the renderer emits:
> "0 interaction-invariant suggestions shown (N at .possible tier
>  hidden — pass --include-possible to see new-family candidates
>  pending calibration)."

This catches the M4.0 default state (every family is `.possible`) and
points the user at the right flag rather than failing silently.

## Architectural choices baked into M4

**1. `predicate: String` is family-specific.** Conservation
populates it with a Swift boolean expression
(`state.count == state.items.count`); Idempotence populates it with
the bare action-case dot-shorthand (`.refresh`); future families may
populate it with their own shape. M4.D's stub emitter branches on
`suggestion.family` to interpret. Adding a sum-type or per-family
field would have been cleaner; for v2.0 M4 the string-with-family-
routing approach is the smaller, faster ship.

**2. Score 30 / `.possible` tier by construction.** PRD §3.5
corollary: every new family ships at default-Possible visibility
through three calibration cycles before promotion. M4.B/C bake this
in by setting `score: 30` regardless of how many signals fire —
no per-signal weights yet. After three calibration cycles produce
data, the scoring may grow per-signal weights and earn promotion to
`.likely` / `.strong`.

**3. Cartesian-product witness pairing in Conservation.** A State
struct with `itemCount`, `tagCount`, `items`, and `tags` produces
4 witnesses (and hence 4 suggestions). Calibration may want to
tighten this (require name-prefix matches: `itemCount` ↔ `items`),
but at v0.0 the conservative-but-noisy default makes the failure
modes visible.

**4. Tier filtering at the renderer, not the engine.** The engine
emits everything; the renderer filters by `.possible` based on
`--include-possible`. Keeps the calibration loop simple — drop the
flag, see exactly what's surfacing, no engine-side
filtering-by-flag-state.

**5. Trap-as-failure for invariant checking.** `precondition`
traps in both debug and release, propagating as non-zero exit. M3's
outcome parser already maps non-zero exits to `.measuredDefaultFails`.
No new mechanism required — the existing chain handles invariant
violations correctly out of the box.

## Test count

**2691 → 2777 (+86):**

- M4.A (+9) — `InteractionInvariantSuggestionTests` (data model,
  identity canonical input, Codable round-trip) +
  `InteractionTemplateEngineTests` (namespace dispatch).
- M4.B (+21) — `ConservationWitnessDetectorTests` (12: detection
  paths + helper-function shape) +
  `ConservationInteractionTemplateTests` (8: suggestion emission) +
  engine signature update (+1 net).
- M4.C (+21) — `IdempotenceWitnessDetectorTests` (12) +
  `IdempotenceInteractionTemplateTests` (9).
- M4.D (+10) — `ActionSequenceStubEmitterInvariantTests`
  (nil-default backward compat, Conservation per-step,
  Idempotence both signature shapes, unsupported families,
  helper-function shape).
- M4.E (+22) — `InteractionSuggestionRendererTests` (11: sentinels,
  block fields, bullets, tier filtering) +
  `DiscoverInteractionCommandTests` (11: CLI parse, filterCandidates,
  end-to-end runPipeline against Conservation + Idempotence
  fixtures).
- Misc — Codable adoption on `SuggestionIdentity` (+2 round-trip
  tests).

§13 budgets unchanged. M3's per-cycle perf-target test (§15: 1k
action sequences in <100ms) defers to a calibration cycle once a
real corpus is pinned.

## What's next — M5 and beyond

M4 closes the lifted-from-v1 families. Next direction is **M5** —
the first new family (Cardinality) per PRD §5.4:

> Pattern: State has ≥ 2 mutually-exclusive presentation flags /
> optionals.
>
> Witnesses:
>   - ≥ 2 `Bool` fields named `is(Showing|Presenting)...`
>   - ≥ 2 `Optional<T>` fields with names matching
>     `(sheet|alert|fullScreenCover|popover)`
>   - Reducer body for the corresponding `.show*` actions writes
>     true / .some(...) to one without clearing the others.
>
> Emitted property: `at most one transient presentation active`.

M5 is the first family that requires reducer-body walking (the
witness includes a check on `.show*` action handlers). This is the
M3.A `ReducerPurityAnalyzer` extension point — same SwiftSyntax pass
posture, different signal set.

Beyond M5, the §5.8 milestone arc is:
- **M5** — Cardinality (first new family; first body-walking
  detector).
- **M6** — Referential integrity (`selectedX` + `xs` pair detection).
- **M7** — Biconditional / iff (`(isLoadingX, taskX?)` pair).
- **M8** — Subprocess verify for effect-bearing reducers.
- **M9** — InteractionInvariantBridge (kit-side `InteractionInvariant`
  protocol family; conformance suggestion when ≥ 3 Strong invariants
  fire on the same reducer).
- **M10** — Drift mode for interaction invariants.

Each new family naturally is its own sub-cycle plus a calibration
cycle. The Phase 2 acceptance targets are deliberately lower than
Phase 1's 70% (PRD §19) because new templates restart calibration
from zero.

## What's deferred (still out of M4)

- **Score per-signal weights.** Every M4 suggestion gets a flat
  score of 30. Multi-signal scoring (witness shape + action-handler
  coverage + state size + carrier-kind) lands when calibration data
  justifies it.
- **Reducer-body-purity counter-signal for Idempotence** (PRD §5.3:
  "Action body has side effects via Effect or async → downgrade to
  Likely"). The M3.A `ReducerPurityAnalyzer` is the natural surface;
  wiring is its own future commit.
- **Sum/total-shaped Conservation aggregates.** `total: Decimal`
  paired with `items: [LineItem]` summing `\.price` — needs
  per-element field detection that walks into `LineItem`'s
  declaration.
- **Drift mode for interaction invariants** (PRD §11 + §5.8 M10) —
  baseline + warning-on-new-Strong-tier-suggestion.
- **Verify-evidence persistence for interaction outcomes** (PRD §17
  schema v4). M3.E renders; nothing persists to
  `.swiftinfer/decisions.json` yet. M9-adjacent work.
- **TCA `.tca` carrier support in verify-interaction.** M3.B still
  rejects with `unsupportedCarrier` — closure-relative state init is
  the blocker.
- **Multi-corpus calibration runs.** M1.C's
  `docs/calibration-corpus-v2.0.md` is still a skeleton; pin real
  OSS corpora once verify can validate counts (M3 is now live, so
  this is unblocked but not yet started).

## Artifacts

- v1.79 sources (M4.A → M4.E):
  - `Sources/SwiftInferCore/InteractionInvariantSuggestion.swift`
  - `Sources/SwiftInferTemplates/InteractionTemplateEngine.swift`
  - `Sources/SwiftInferTemplates/ConservationWitness.swift` +
    `ConservationWitnessDetector.swift` +
    `ConservationInteractionTemplate.swift`
  - `Sources/SwiftInferTemplates/IdempotenceWitness.swift` +
    `IdempotenceWitnessDetector.swift` +
    `IdempotenceInteractionTemplate.swift`
  - `Sources/SwiftInferCLI/ActionSequenceStubEmitter.swift` (M4.D
    invariant embedding)
  - `Sources/SwiftInferCLI/InteractionSuggestionRenderer.swift`
  - `Sources/SwiftInferCLI/DiscoverInteractionCommand.swift`
- Prior cycle: `docs/calibration-cycle-75-findings.md` (M3.E —
  workdir + build/run loop).
- v2.0 PRD: `docs/SwiftInferProperties PRD v2.0.md`.
