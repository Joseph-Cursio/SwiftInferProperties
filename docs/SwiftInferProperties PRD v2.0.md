# Product Requirements Document

## SwiftInferProperties v2.0: Interaction-Invariant Inference for SwiftUI State Systems

**Version:** 2.0 (draft)
**Status:** Planned (no v2.0 surface has shipped; v1.71.0 is the current release line)
**Audience:** Open Source Contributors, Swift Ecosystem
**Depends On:** SwiftPropertyLaws next minor (additive bump — new `InteractionInvariant` law surface; see §13)

> This document is forward-looking. v1.0 described a shipped surface; v2.0 describes what is *planned*. No claims here should be read as commitments until the corresponding §5–§9 milestones land and a calibration cycle confirms them. Where this document differs from v1.0's "shipped" framing, that is deliberate — the v2.0 surface is conjectural and the calibration record will overrule any prose below that turns out to be wrong.

-----

## 1. Overview

v1.0 mined latent algebraic structure (idempotence, round-trip, monoid, group, semilattice, ring) in **pure functions**. v2.0 extends the same machinery to **interaction invariants** over reducer-shaped functions — predicates that must hold across arbitrary sequences of user actions on `(State, Action) -> State` carriers.

The intellectual debt is to the *interaction-invariant taxonomy* — a shape-based grouping of "what must always be true?" rules into eight families, of which v2.0 targets five (the remaining three are §20 deferred):

| Family | Example | v2.0 status |
|---|---|---|
| **1. Cardinality** | At most one modal presented; exactly one auth state visible | **In scope (new)** |
| **2. Referential integrity** | Selected message ID exists in current list | **In scope (new)** |
| **3. Biconditional / iff** | Spinner visible iff request in flight | **In scope (new)** |
| **4. Conservation** | Cart total = sum of line items; undo restores prior state | **In scope (lifted from v1)** |
| **5. Idempotence / stability** | Pull-to-refresh twice = pull once | **In scope (lifted from v1)** |
| 6. Reachability | Authenticated content unreachable from unauth state | Deferred to v2.1+ (§20) |
| 7. Temporal | Spinner disappears within timeout; cancelled writes never surface | Deferred to v2.1+ (§20) |
| 8. Accessibility | All controls labeled; focus reachable | Out of scope (not PBT) |

v2.0 ships **five new contributions** layered on the v1.0 surface:

- **Contribution 1 — InteractionTemplateEngine.** Five new (or lifted) template families, each scored through the same §4 weighted engine as v1's algebraic templates, surfaced through the same explainability block and triage prompts. The shape-by-shape spec is §5.
- **Contribution 2 — ReducerDiscovery.** SwiftSyntax pass that finds reducer-shaped functions by signature match (`(S, A) -> S`, `(inout S, A) -> Void`, `(S, A) -> (S, Effect<A>)`) plus a TCA-specific path that walks `Reducer.body` declarations (§6.3). Scope is *signature-detectable reducers with a first-class Action enum* — implicit-action carriers (e.g., `@Observable` view-models where actions are method calls) are out of scope. The discovery model accepts any signature shape that fits — at the cost of a louder Daikon-trap risk that §3.5 addresses directly.
- **Contribution 3 — HybridVerifyPipeline.** Pure reducers (Equatable State, no async / Effect in body) verify **in-process** at < 100ms/1k-action-sequence; effect-bearing reducers fall back to the existing v1.42+ **subprocess** harness with the same five-category outcome scheme. Both paths share the `.bothPass` / `.edgeCaseAdvisory` / `.defaultFails` / `.error` / `.architectural-coverage-pending` vocabulary so v1's measured-execution metric extends cleanly to v2.
- **Contribution 4 — ActionSequenceGenerator.** Kit-side extension to `DerivationStrategist`: synthesize `Gen<[Action]>` from an Action enum, with optional stateful guards (don't fire `.delete(id)` after `.delete(id)` on the same id). Sequences are bounded (default ≤ 16 actions); shrinking minimizes a failing trace to its smallest reproducer. Persisted to `Tests/Generated/SwiftInferTraces/` on failure.
- **Contribution 5 — InteractionInvariantBridge.** When the InteractionTemplateEngine accumulates ≥3 Strong-tier suggestions on the same reducer, propose conformance to a kit-defined `InteractionInvariant` protocol so SwiftPropertyLaws verifies the laws on every CI run thereafter. Analog of v1's RefactorBridge.

All five contributions inherit v1's invariants: opt-in, human-reviewed, never auto-applies, never executes Effects in-process, all output is probabilistic suggestion (§16).

-----

## 2. Problem Statement

### 2.1 Interaction Bugs Dominate Real-World UI Failures

Real-world UI failures cluster in *transition bugs*, *temporal bugs*, *stale-state bugs*, and *race conditions* far more often than in rendering or layout bugs. v1.0 covered pure-function correctness; the much larger surface of *state-system correctness* sits in the reducer layer, where mainstream Swift testing tooling stops at scripted action sequences (Point-Free's `TestStore`) and has no `forAll`-over-actions equivalent to QuickCheck / Hypothesis / quickcheck-state-machine.

### 2.2 The Interaction-Invariant Taxonomy

The natural unit isn't "PBT for SwiftUI" but **interaction invariants** — predicates over `(State, Action) -> State` that must hold for any user action sequence. The taxonomy is shape-based (cardinality, ref-integrity, biconditional, conservation, idempotence, reachability, temporal, accessibility), not domain-based (auth, cart, navigation): the same *shape* recurs across domains and each shape has a different cost/tool profile. Lumping them all under "invariants" hides that — and is exactly the mistake the academic LTL/CTL taxonomy (safety vs liveness vs fairness) avoids.

### 2.3 The Scope: Signature-Detectable Reducers

v2.0 detects any function with one of three canonical reducer signatures (§6.2) **plus** TCA `Reducer.body` declarations recognized by a conformance walk (§6.3). This is *signature-based detection*, not full carrier-agnosticism — implicit-action carriers like `@Observable` view-models, where actions are method calls rather than a first-class enum, are out of scope because action-sequence generation requires an enumerable Action type. Three risks the design must mitigate:

1. Discovery-by-shape risks false matches. A non-reducer function that happens to have signature `(S, A) -> S` will be picked up. Mitigation: the user pins target reducers via `--reducer <module>.<typeName>.<funcName>` (§6.4) — the default behavior is to list candidates with carrier-kind labels and exit, never silently picking one.
2. TCA reducers don't match the canonical signatures directly. `var body: some ReducerOf<Self>` is neither `(S, A) -> S` nor `(inout S, A) -> Void` at the source level — the reducer shape is hidden behind the protocol. §6.3 specifies the TCA-specific walk that recovers it.
3. State may not be Equatable. SwiftUI State often contains closures, `AnyView`, `Task`, `AnyCancellable`, or other non-Equatable fields. The in-process verify path tolerates this when the candidate invariant uses *projected* fields (§5.6 biconditional discussion); the subprocess path accepts a user-supplied `state.equals(_:)` instance method (§14).

These risks are addressed by §3.5 (philosophy), §5 (per-family precision targets), and §14 (risk register).

### 2.4 The Gap v2.0 Fills

v1.0 handles: *"given what your pure functions look like, what algebraic laws are you implicitly claiming?"*

v2.0 handles: *"given what your reducer looks like, what interaction invariants are you implicitly claiming, and is there a kit-defined `InteractionInvariant` you should be conforming to so SwiftPropertyLaws can verify them on every action sequence?"*

-----

## 3. Goals and Non-Goals

### Goals

- Identify candidate interaction invariants from reducer signatures + state-struct shape + action-enum shape, without requiring developer annotation
- Surface five shape families (cardinality, ref-integrity, biconditional, conservation, idempotence) on reducer carriers through structural analysis
- Synthesize bounded `Gen<[Action]>` generators from action enums via the kit's `DerivationStrategist`
- Verify candidate invariants by running random action sequences against the reducer — in-process for pure reducers, subprocess for effect-bearing ones
- Suggest conformance to kit-defined `InteractionInvariant` protocols when evidence accumulates (Contribution 5)
- Produce human-reviewable output with shrunk failing-trace traces as a first-class artifact
- Operate as a CLI subcommand `swift-infer discover-interaction` with the same interactive triage / drift modes as v1
- Extend `.swiftinfer/decisions.json` schema (v4) to carry interaction-invariant identity hashes alongside v1's template/function-pair hashes
- Track adoption metrics per family so the scoring engine recalibrates empirically (continues the v1.4–v1.30 calibration practice)

### Non-Goals

- Reachability / temporal families (deferred to v2.1+; see §20)
- View introspection or render-layer testing (ViewInspector et al. — different problem, different tools)
- Snapshot testing
- Accessibility automation
- Automatic action-sequence mining from user trace logs / replay buffers
- TCA-specific TestStore integration (deferred to §20 — keeps v2.0's verify path uniform across carriers)
- Effects / async / cancellation modeling beyond per-step semantics (the verify pipeline calls each `(S, A) -> S` step; downstream Effect resolution is not simulated)
- Concurrency-race detection (in-process verify is single-threaded; concurrency requires a different harness — §14)
- Stateful PBT in the full quickcheck-state-machine sense (bundles, parallel histories) — v2.0 ships sequential action sequences only

-----

## 3.5 Product Philosophy

v2.0 inherits v1.0's conservative-inference philosophy verbatim and adds one corollary:

> **Interaction-invariant precision is expected to be harder than algebraic-law precision.** SwiftUI state graphs have far less structure than function signatures, and the v1 binding-table experience (cycle-58 V1.51.B latent-pair-table bug masking 12 picks for ~13 release cycles; v1.61 dual-style pair fix; v1.69 monotonicity-emitter rework) tells us to plan for the same shape of problem at every new template family. The defaults skew even more aggressively toward suppression than v1's.

Concretely this means:

1. **`Possible` tier is hidden by default in v2.0 just as in v1.0.** No exceptions for new families.
2. **A new family's milestone ships at default `Possible` visibility.** Promotion to default-visible (`Likely` or `Strong`) requires three calibration cycles after the milestone ship date with stable acceptance rate ≥ the §19 Phase 2 target. The §5.8 milestone "Planned" status means *emitter + scoring + verify integration landed*; it does not imply default-visible promotion. Sequence: M5 → M5.cal1 → M5.cal2 → M5.cal3 → promotion (or weight retune, if the rate doesn't stabilize).
3. **The verify pipeline's `.bothPass` outcome is the strongest signal v2.0 emits.** Heuristic-only invariants stay in the lower tiers; only execution evidence promotes to `.verified` (continuing the v1.65 first-class tier introduction).
4. **The Daikon trap is louder.** If calibration shows interaction-template families producing more suggestions than a developer can read in one sitting, raise thresholds — *do not* add filters on top.

-----

## 3.6 Developer Workflow

End-to-end workflow. Each step lists its owning §5–§9 contribution. CLI surface adds flags to v1's existing subcommands (`discover`, `verify`, `drift`) rather than introducing new top-level subcommands.

1. **Reducer discovery.** Developer runs `swift-infer discover --reducers --target MyApp`. Lists detected reducer-shaped functions with a signature shape + carrier inference (TCA `Reducer.body` / generic `(S, A) -> S` / Elm-style). The user pins the target reducer via `--reducer Inbox.body` when ambiguous.
2. **Interaction-invariant discovery.** `swift-infer discover --interaction --reducer Inbox.body` scans the State struct and Action enum, applies the five template families, and produces tiered suggestions (✓ Strong / ~ Likely / ? Possible) using the same §4 explainability block as v1.
3. **Suggestion review.** Each suggestion shows: family, predicate, evidence trail, candidate generator strategy, expected verify path (in-process vs subprocess), and the same "why suggested" / "why this might be wrong" two-sided block.
4. **Adoption.** Accepted suggestions write `@Test` stubs to `Tests/Generated/SwiftInferInteraction/`. InteractionInvariantBridge suggestions (≥3 Strong on the same reducer) propose kit-conformance stubs in `Tests/Generated/SwiftInferRefactors/`.
5. **Verify.** `swift-infer verify --interaction --reducer Inbox.body` runs N action sequences per accepted invariant — in-process if pure, subprocess if effect-bearing. Outcomes flow into the same five-category vocabulary as v1.
6. **Trace replay.** Failing sequences are shrunk and persisted to `Tests/Generated/SwiftInferTraces/<reducer>/<invariant-id>.swift` as deterministic regression tests.
7. **Drift checking.** `swift-infer drift --interaction --baseline .swiftinfer/interaction-baseline.json` warns (non-fatally) about new Strong-tier interaction suggestions added since baseline.
8. **Decision persistence.** Decisions written to `.swiftinfer/decisions.json` (schema v4, extended from v3) keyed by interaction-suggestion-identity hash.

-----

## 4. Confidence Model — Extended Scoring Engine

v2.0 reuses v1.0's §4 weighted scoring model unchanged; the tier mapping (Strong / Likely / Possible / suppressed) and visibility defaults are identical. New signals are added to handle reducer carriers and interaction-shape evidence.

### 4.1 New Signals

| Signal | Weight | Description |
|---|---|---|
| **Reducer-shaped signature** | +30 | Function matches `(S, A) -> S` / `(inout S, A) -> Void` / `(S, A) -> (S, Effect<A>)`. *Necessary* for any interaction-template suggestion. |
| **Equatable State** | +20 | The State type conforms to `Equatable` (enables in-process verify and most invariants). |
| **Sendable State + Action** | +10 | Both types are `Sendable` (cheap signal that the reducer is well-typed for concurrency-clean verify). |
| **Action enum has ≤ 8 cases** | +15 | Small action sets are tractable for combinatorial exploration; large enums signal richer state machines where the Daikon trap is louder. |
| **Action enum has ≥ 20 cases** | -15 | Inverse: very large action enums produce noisy sequence generation; suppress unless other signals fire. |
| **State has @Observation-trackable references** | -10 | State contains stored class references / `@Observable` instances — the reducer may not be pure and in-process verify is unreliable. |
| **Reducer body calls async / Effect / Task** | 0 (routing only) | Detected via type-flow analysis. Does *not* change the score — it routes the suggestion's `verifyPath` (§4.3) from `.inProcess` to `.subprocess`. The subprocess path is slower but still produces the same five-category outcome. |
| **Reducer body has hidden mutability** (global state, static vars, escaped captures) | -∞ | Distinct from the row above: outcomes will be non-deterministic in either verify path, so the suggestion is suppressed. |
| **Cardinality witness: ≥ 2 transient-presentation modifiers** | +25 | State exposes ≥ 2 `Bool` / `Optional` fields that look like sheet/alert/fullScreenCover items. Triggers cardinality-family templates. |
| **Referential-integrity witness: KeyPath into collection** | +25 | State has a `selectedID: T.ID?` field and a `items: [T]` field where `T.ID` matches. Triggers ref-integrity templates. |
| **Biconditional witness: parallel state pairs** | +20 | State has a pair `(isLoadingX: Bool, requestX: Task?)` or `(isShowingX: Bool, dataX: T?)`. Triggers biconditional templates. |
| **Counter-signal: implicit action surface** | -20 | Reducer body switches over an action enum, but the action enum has ≥ 3 cases with unhandled-default routes — the action set is implicit. |
| **Verify outcome: bothPass on action sequences** | +50 | The action-sequence verify pipeline produces `.bothPass` for the invariant across both default and edge generators. Same +50 weight as v1.66. |
| **Verify outcome: defaultFails** | veto (suppression) | Verify pipeline disproved the invariant. Same vetoing semantics as v1.66. |

### 4.2 Tier Mapping

Unchanged from v1: ≥ 75 Strong, 40–74 Likely, 20–39 Possible (hidden by default), < 20 suppressed. The `.verified` tier (v1.65) extends to interaction invariants: a Strong suggestion with `.measuredBothPass` evidence promotes to `.verified` and floats to the head of the discover stream.

### 4.3 Generator Awareness

Every interaction-invariant suggestion's evidence record adds:

- `actionGeneratorSource`: `.derivedFromCaseIterableAction` | `.derivedWithStatefulGuards` | `.registered` | `.todo`
- `actionGeneratorConfidence`: `.high` | `.medium` | `.low`
- `verifyPath`: `.inProcess` | `.subprocess` | `.skipped(reason:)` — chosen by the §4.1 type-flow check; rendered in the explainability block so the user knows which path produced any verify outcome below
- `sequenceLength`: actual `(min, max, p50, p99)` from the verify run, if any
- `samplingResult`: `.passed(trials: N, sequenceCount: M)` | `.failed(seed: S, shrunkTrace: T)` | `.notRun`

A "Strong" interaction suggestion that passed sampling under a `.low`-confidence stateful guard is rendered with an explicit caveat in the explainability block (§4.5).

### 4.4 Explainability — Sample Output

```text
Score:       105 (verified)
Family:      Referential integrity (family 2)
Reducer:     Inbox.body
Invariant:   state.selectedID == nil ||
             state.items.contains { $0.id == state.selectedID }

Why suggested:
  ✓ Reducer-shaped signature (Inbox.swift:42)                    (+30)
  ✓ Equatable State (Inbox.State conforms)                        (+20)
  ✓ Ref-integrity witness: selectedID: Message.ID?,
    items: [Message] where Message.ID matches                     (+25)
  ✓ Verify outcome: bothPass on 256 action sequences,
    in-process path, sequenceLength p99=14                        (+50)
      actionGenerator: .derivedWithStatefulGuards, confidence: .high
      stateful guards: don't .delete(id) after .delete(id)

Why this might be wrong:
  ⚠ Action enum has 22 cases — larger than the ≤8 sweet spot;
    coverage of low-frequency cases (e.g. .deepLinkRestoreState)
    in the sampled sequences was only 12% — use --exhaustive
    to widen.
  ⚠ State contains a Task? field (refreshTask) — the in-process
    verify path does NOT exercise async cancellation; if the bug
    you're worried about is cancellation race, this invariant
    will not catch it.
```

-----

## 5. Contribution 1: InteractionTemplateEngine

### 5.1 Description

SwiftSyntax-based static analysis over reducer-shaped functions. For each detected reducer (Contribution 2), the engine walks the State struct + Action enum + reducer body, matches against the five family-specific patterns, accumulates §4 signals, and emits candidate interaction-invariant test stubs.

### 5.2 Family 4 — Conservation (Lifted from v1)

**Pattern:** State has a *cached* aggregate (a stored property) that should equal the recomputation from a contributing collection in the same State.

**Note on what doesn't qualify:** if `total` is a *computed* property whose definition already says `items.reduce(0, +)`, then `total == items.reduce(0, +)` is true by definition — there's no invariant to verify. Conservation only fires when the aggregate is a stored property whose synchronization with the collection is the reducer's responsibility.

**Witnesses:**
- A stored aggregate-shaped property (`total: Decimal`, `count: Int`, `sum: Double`) paired with a contributing collection (`items: [LineItem]`, `entries: [Entry]`) in the same State struct.
- An Action case writing to the stored aggregate (`.setTotal(Decimal)`, `.recomputeTotal`) or one whose handler updates the aggregate alongside the collection.
- Three or more action handlers that touch both the stored aggregate and the contributing collection — suggesting an invariant `total == items.map(\.price).reduce(0, +)`.

**Counter-signals:** Non-Equatable State (-∞); state contains floating-point sums (downgrade — IEEE-754 round-off makes exact equality fragile; suggest approximate-equality variant per v1.31's FP arm).

**Emitted property:**

```swift
// Template: conservation
// Family: 4 (conservation)
// Confidence: Strong (score 105, verified)
// Invariant: state.total == state.items.map(\.price).reduce(0, +)
@Test func cartTotalConservation() async throws {
    await propertyCheck(input: Gen.actionSequence(Inbox.Action.self, length: 0...16)) { actions in
        var state = Inbox.State()
        for action in actions {
            state = Inbox.body(state, action)
            #expect(state.total == state.items.map(\.price).reduce(0, +))
        }
    }
}
```

### 5.3 Family 5 — Idempotence (Lifted from v1)

**Pattern:** Action enum has a case whose semantics suggest applying-twice equals applying-once.

**Witnesses:**
- Action case names matching `refresh`, `reset`, `clear`, `setX(value)`, `select(id)`, `dismiss`, `cancel`.
- Reducer body for the matching action does not increment counters or push onto unbounded collections.

**Counter-signals:** Action body has side effects via Effect or async — downgrade to `Likely` (the in-process verify will produce a clean idempotence outcome, but the real-world effect chain may not).

**Emitted property:**

```swift
// Template: action-idempotence
// Family: 5 (idempotence)
// Invariant: applying .refresh twice = applying .refresh once
@Test func refreshIsIdempotent() async {
    await propertyCheck(input: Gen.derived(Inbox.State.self)) { initial in
        let once  = Inbox.body(initial, .refresh)
        let twice = Inbox.body(once, .refresh)
        #expect(once == twice)
    }
}
```

### 5.4 Family 1 — Cardinality (New)

**Pattern:** State has ≥ 2 mutually-exclusive presentation flags / optionals.

**Witnesses:**
- ≥ 2 `Bool` fields named `is(Showing|Presenting)...`.
- ≥ 2 `Optional<T>` fields with names matching `(sheet|alert|fullScreenCover|popover)`.
- The reducer body for the corresponding `.show*` actions writes `true` / `.some(...)` to one without clearing the others.

**Emitted property:**

```swift
// Template: cardinality-at-most-one
// Family: 1 (cardinality)
// Invariant: at most one transient presentation active
@Test func atMostOneTransientPresentation() async throws {
    await propertyCheck(input: Gen.actionSequence(Settings.Action.self)) { actions in
        var state = Settings.State()
        for action in actions {
            state = Settings.body(state, action)
            let presentationCount =
                (state.activeSheet  != nil ? 1 : 0) +
                (state.activeAlert  != nil ? 1 : 0) +
                (state.isFullScreen ? 1 : 0)
            #expect(presentationCount <= 1)
        }
    }
}
```

**Calibration note:** The "≥ 2 fields" heuristic is intentionally crude as a starting point. v2.0 ships this with default *Possible*-tier visibility — calibration cycles raise the threshold or refine the witness pattern empirically (see §19 success criteria).

### 5.5 Family 2 — Referential Integrity (New)

**Pattern:** State has a "selected ID" field referencing an entity in a collection.

**Witnesses:**
- A `selectedX: T.ID?` field paired with an `xs: [T]` field where `T: Identifiable`.
- A route/path enum (`NavigationPath` / `Route` / `Destination`) carrying an ID-typed payload.
- Reducer handlers for `.select(_:)` write to the ID field but `.delete(_:)` clears the collection without clearing the selection.

**Emitted property:** see the §4.4 example.

**Counter-signal:** Selection is allowed to be stale by design (e.g., the View interprets a missing selection as "show empty state") — surfaced as a known caveat in the explainability block, not a veto.

### 5.6 Family 3 — Biconditional / iff (New)

**Pattern:** Two State fields that should be either both-set or both-unset.

**Witnesses:**
- A `(isLoadingX: Bool, taskX: Task<_, _>?)` pair where the reducer body for `.startX` sets both and `.cancelX` clears both — but at least one handler clears only one of the pair.
- A `(isShowingX: Bool, dataX: T?)` pair with similar shape.

**Note on Equatable State:** the canonical biconditional pair contains a `Task<_, _>?` or `AnyCancellable?` field, neither of which is `Equatable`. v2.0 does *not* require whole-State equality for biconditional verify — the predicate is checked via *projected fields* (`state.isLoading` and `state.activeTask != nil`, both Bool) at each reducer step. The §4.1 "Equatable State" signal is a generic score contributor; it is not a precondition for the biconditional family specifically.

**Emitted property:**

```swift
// Template: biconditional
// Family: 3 (iff)
// Invariant: state.isLoading <=> state.activeTask != nil
@Test func spinnerVisibleIffRequestActive() async throws {
    await propertyCheck(input: Gen.actionSequence(Search.Action.self)) { actions in
        var state = Search.State()
        for action in actions {
            state = Search.body(state, action)
            #expect(state.isLoading == (state.activeTask != nil))
        }
    }
}
```

**Calibration note:** This family is the trickiest of the five because the two sides often live in different state layers (view-state vs model-state) and drift out of sync — exactly where SwiftUI race conditions show up. Expect cycles 3-5 worth of calibration to dial precision.

### 5.7 Annotation API

Reuses v1's `@CheckProperty` pattern with new arms:

```swift
@CheckProperty(.cardinalityAtMostOne(\.activeSheet, \.activeAlert, \.fullScreen))
@CheckProperty(.referentialIntegrity(selection: \.selectedID, collection: \.items))
@CheckProperty(.biconditional(\.isLoading, equals: { $0.activeTask != nil }))
@CheckProperty(.conservation(\.total, equals: { $0.items.map(\.price).reduce(0, +) }))
@CheckProperty(.actionIdempotent(.refresh))
struct Inbox: Reducer { ... }
```

Macro expansion writes a per-attribute `@Test func ...` peer in the user's source — same pattern as v1's `@CheckProperty`. No runtime dependency on SwiftPropertyLaws at attribute scan time; users wanting compile-time validation import `PropertyLawMacro` themselves.

### 5.8 Milestones

| Milestone | Deliverable | Status |
|---|---|---|
| **M1** | Reducer discovery (§6) with signature shape detection for `(S, A) -> S`, `(inout S, A) -> Void`, `(S, A) -> (S, Effect<A>)`. CLI `swift-infer discover-reducers`. | **Planned** |
| **M2** | Action-sequence generator (§8) via kit's DerivationStrategist extension. Default Gen.array length 0...16. CaseIterable Action enums. | **Planned** |
| **M3** | In-process verify path. Pure-reducer detection (Equatable State, no Effect/async). `swift-infer verify-interaction --in-process`. | **Planned** |
| **M4** | Family 4 + 5 lifted from v1 to reducer carriers. First calibration cycle. | **Planned** |
| **M5** | Family 1 (cardinality) template + emitter + first calibration cycle. | **Planned** |
| **M6** | Family 2 (referential integrity) template + emitter + first calibration cycle. | **Planned** |
| **M7** | Family 3 (biconditional) template + emitter + first calibration cycle. | **Planned** |
| **M8** | Subprocess verify path for effect-bearing reducers. Outcome categories aligned with v1's five-category scheme. Trace persistence to `Tests/Generated/SwiftInferTraces/`. | **Planned** |
| **M9** | InteractionInvariantBridge (§9): kit `InteractionInvariant` protocol family + conformance suggestion when ≥ 3 Strong invariants on the same reducer. | **Planned** |
| **M10** | Drift mode for interaction invariants. `.swiftinfer/interaction-baseline.json`. | **Planned** |

The §4 explainability block ("why suggested" + "why this might be wrong") is a per-family deliverable — every family ships with both blocks populated from active signals plus known caveats. There is no separate "explainability milestone."

**Per-family calibration cadence.** Milestone status `Planned → Planned (in-progress) → Planned (calibrating) → Planned (promoted)`. A new-family milestone (M4–M7 above) is `Planned (calibrating)` when emitter + scoring + verify integration land at default `Possible` visibility. Promotion to default-visible (`Likely` / `Strong`) requires three calibration cycles with stable acceptance rate ≥ the §19 target — at which point the milestone reaches `Planned (promoted)`. The §3.5 policy and these milestone states are the same constraint expressed two ways.

-----

## 6. Contribution 2: ReducerDiscovery

### 6.1 Description

SwiftSyntax pass that scans the target module for reducer-shaped functions. Two detection paths run in parallel: a signature scan over canonical reducer signatures (§6.2), and a TCA-specific conformance walk (§6.3). Both produce reducer candidates with `carrierKind` labels (§6.4) for downstream §5 templates.

### 6.2 Canonical Signatures

| Shape | Example | Detection | In-process verifiable? |
|---|---|---|---|
| `(S, A) -> S` | Elm-style, hand-rolled, free-function reducers | Signature scan | Yes (if S: Equatable, no Effect/async in body) |
| `(inout S, A) -> Void` | Common idiom in TCA reducer closures | Signature scan | Yes (S: Equatable; verify makes a copy and feeds it in) |
| `(S, A) -> (S, Effect<A>)` | TCA pre-2022, ReSwift with thunks | Signature scan | No — routes to subprocess |
| `var body: some ReducerOf<Self>` inside a `Reducer` conformer | TCA post-2022 idiom | Conformance walk (§6.3) | Yes if the resolved `Reduce { state, action in ... }` body is pure |
| `func dispatch(_ action: A)` on a class | @Observable view-models | N/A | Out of scope (§2.3) — no first-class Action enum to enumerate |

### 6.3 TCA-Specific Detection

TCA reducers expose `var body: some ReducerOf<Self>` rather than a function of canonical signature, so signature-scan misses them. The detection path:

1. **Conformance walk.** Recognize any type conforming to `Reducer` by name match against `import ComposableArchitecture` (no runtime dep — same name-match strategy v1 uses for `@Discoverable`).
2. **Body resolution.** Walk the `body` declaration. Recognize standard combinators (`Reduce`, `BindingReducer`, `Scope`, `EmptyReducer`, `CombineReducers`, `Pullback`).
3. **Closure extraction.** For each `Reduce { state, action in ... }` literal encountered during the walk, treat the closure as a reducer body with synthesized signature `(inout Self.State, Self.Action) -> Effect<Self.Action>`. Pure closures (no `Effect` returns, no `.run` / `.send` / `.cancel`) qualify for the in-process path.
4. **Type-flow on the extracted body.** Apply the §4.1 type-flow check (async / Effect / Task references) to the closure body, not to `body` itself.

When `body` composes multiple `Reduce` closures via `CombineReducers`, each closure is detected independently and surfaces as a separate reducer candidate.

### 6.4 Carrier Inference

Each reducer candidate gets a `carrierKind` label (`.tca` / `.elmStyle` / `.generic`) inferred from imports and context. The label is informational; templates fire on all carrier kinds equally. `@Observable` is *not* a valid carrier kind in v2.0 (§2.3).

### 6.5 Disambiguation

When multiple reducer candidates exist in the target, the user pins via `--reducer <module>.<typeName>.<funcName>`. The default behavior (no flag) is to list all candidates with their carrier-kind labels and exit — never silently picking one.

### 6.6 Discovery Performance Budget

| Operation | Target |
|---|---|
| Reducer discovery on 50-file module | < 1 second |
| Reducer discovery on 500-file module | < 5 seconds, < 200 MB resident |

-----

## 7. Contribution 3: HybridVerifyPipeline

### 7.1 Description

Two verify paths sharing one outcome vocabulary. Pure reducers (Equatable State, no Effect/async/Task in body) verify **in-process**; effect-bearing reducers route to the **subprocess** path that v1.42+ built. Both produce outcomes in the same five-category scheme (`.bothPass` / `.edgeCaseAdvisory` / `.defaultFails` / `.error` / `.architectural-coverage-pending`) so v1's measured-execution metric extends without a schema change.

### 7.2 In-Process Path

When the reducer is pure:

1. Generate a sequence of N actions via the action-sequence generator (§8), filtering through any active stateful guards (§8.1).
2. Apply each action in turn, checking the candidate invariant at each step.
3. On failure, shrink the sequence to its minimal reproducer (drop-prefix, drop-suffix, halving — standard QuickCheck shrinking). **Shrinking respects the same stateful guards used during generation** — a shrunk variant that violates a guard (e.g., contains `.select(id: 1)` with no preceding `.insert(id: 1)`) is rejected and the shrinker tries a smaller variant. Termination is guaranteed: shrinking either reaches a guard-valid minimal failing trace or terminates at the empty sequence.
4. Emit outcome.

Performance target: 1k action sequences (default length distribution; ≤ 16 actions each) in < 100ms wall on a 2024 MacBook Air for a 5-case-Action 10-field-State reducer.

### 7.3 Subprocess Path

When the reducer body contains Effect / async / Task references (type-flow detected at scan time):

1. Synthesize a wrapper file containing the action-sequence test stub.
2. Build + run in the throwaway-SwiftPM-workdir per v1.42's architecture.
3. Capture outcomes via the existing v1.64 `.swiftinfer/verify-evidence.json` schema (extended with an `interactionInvariantIdentity` field).

### 7.4 Outcome Routing

| Reducer body signature property | Path | Why |
|---|---|---|
| No Effect/async/Task references | In-process | Fast, deterministic |
| Has Effect/Task but State: Equatable | Subprocess | Effect resolution unknown at scan time; subprocess captures real semantics by building + running the test. Effect-stubbing is a §20 future direction, not v2.0 |
| State: !Equatable | Manual `equals` override required | In-process: requires user-supplied `state.equals(_:)`; subprocess: same |
| Non-Sendable Action | Subprocess only | In-process path is concurrency-clean; non-Sendable Action signals shared state |

### 7.5 Shrinking + Trace Replay

A failing action sequence is shrunk and serialized to `Tests/Generated/SwiftInferTraces/<reducer-id>/<invariant-id>.swift`:

```swift
// Shrunk failing trace
// Reducer: Inbox.body
// Invariant: state.selectedID exists in state.items
// Seed: 0xAB12CD34
@Test func failingTrace_referentialIntegrity_0001() async {
    var state = Inbox.State()
    state = Inbox.body(state, .insert(Message(id: 1, text: "a")))
    state = Inbox.body(state, .select(1))
    state = Inbox.body(state, .delete(1))
    #expect(state.selectedID == nil ||
            state.items.contains { $0.id == state.selectedID })
}
```

Trace files are emitted as deterministic `@Test` cases for replay regression on every CI run thereafter.

-----

## 8. Contribution 4: ActionSequenceGenerator

### 8.1 Kit-Side Extension

The next SwiftPropertyLaws minor (v2.N+1.0 — see §13) extends `DerivationStrategist` with two entry points:

```swift
public extension DerivationStrategist {
    /// Primary entry: build a sequence generator from a per-action generator.
    /// Carrier-agnostic — works for any Action enum whose per-case Gen<A> the caller can supply.
    static func actionSequence<A: Sendable>(
        from actionGen: Gen<A>,
        length: ClosedRange<Int> = 0...16,
        statefulGuards: [any StatefulGuard<A>] = []
    ) -> Gen<[A]>

    /// Convenience: derive Gen<A> for an Action enum by walking the kit's
    /// existing per-case payload strategy chain (.caseIterable / .rawRepresentable /
    /// .memberwise / .codableRoundTrip / .todo).
    /// CaseIterable cases are enumerated directly; cases with payloads are
    /// composed via DerivationStrategist per their payload types.
    /// Returns nil if any case lacks a derivable generator (forces the caller
    /// to either supply a custom Gen<A> or accept the conservative refusal).
    static func actionSequence<A: Sendable>(
        _ actionType: A.Type,
        length: ClosedRange<Int> = 0...16,
        statefulGuards: [any StatefulGuard<A>] = []
    ) -> Gen<[A]>?
}
```

The primary entry deliberately makes no enumerability assumption — the caller supplies a per-action generator. The convenience entry attempts derivation via the kit's existing strategy chain and returns `nil` (rather than emitting `.todo`-placeholder sequences) if any case is underivable. This matches v1's PRD §16 #4 hard guarantee: no silently-wrong code.

Stateful guards are user-supplied filters that suppress action sequences containing forbidden transitions. The shape:

```swift
public protocol StatefulGuard<Action> {
    associatedtype Action
    func wouldAllow(_ next: Action, given history: [Action]) -> Bool
}
```

**Curated guards as v2.0 examples, not commitments.** Specific guards like `.noDoubleDelete`, `.requireLogin`, `.maxConcurrentTasks(N)` illustrate the shape but the v2.0 ship list is calibrated against the actual reference corpus during M2 — guards that don't fire empirically get dropped. The production guard list is an M2 deliverable, not a v2.0 commitment.

### 8.2 Action-Inference From Reducer Body

When the convenience entry's strategy chain can't derive a per-case generator (e.g., a payload type lacks `.memberwise`-suitable structure), v2.0 falls back to `.todo` *at the per-case level* — the convenience entry returns `nil`, and the caller routes through the primary entry with a user-supplied `Gen<A>`. The user is forced to construct the action generator explicitly rather than receiving a silently-broken sequence generator.

### 8.3 Confidence Surfacing

The action-sequence generator's confidence (`.high` / `.medium` / `.low`) flows into the §4.3 generator-awareness fields. A low-confidence generator (e.g., several `.todo` case payloads) downgrades the invariant suggestion's tier by one band.

-----

## 9. Contribution 5: InteractionInvariantBridge

### 9.1 Description

Analog of v1's RefactorBridge: when InteractionTemplateEngine accumulates ≥ 3 Strong-tier suggestions on the same reducer, propose conformance to a kit-defined `InteractionInvariant` protocol.

### 9.2 Kit-Side Law Surface (next kit minor)

The next SwiftPropertyLaws minor (§13) ships new protocols. The InteractionInvariant protocol declares only the predicate — the reducer is supplied separately to the verify harness, so the conformer doesn't need to *be* the reducer:

```swift
public protocol InteractionInvariant {
    associatedtype State
    static func invariantHolds(in state: State) -> Bool
}

public protocol CardinalityInvariant: InteractionInvariant { /* law: count ≤ N */ }
public protocol ReferentialIntegrityInvariant: InteractionInvariant { /* law: ref ∈ extant */ }
public protocol BiconditionalInvariant: InteractionInvariant { /* law: A ↔ B */ }
public protocol ConservationInvariant: InteractionInvariant { /* law: derived = recompute */ }
public protocol ActionIdempotenceInvariant: InteractionInvariant {
    associatedtype Action
    static var idempotentActions: Set<Action> { get } where Action: Hashable
    /* law: ∀ s, ∀ a ∈ idempotentActions: f(f(s, a), a) = f(s, a) */
}
```

The verify harness accepts the reducer as a closure parameter, so it works for any carrier (TCA `Inbox().reduce(into:action:)`, free function, hand-rolled closure):

```swift
public func checkInteractionInvariant<I: InteractionInvariant, A: Sendable>(
    _ invariantType: I.Type,
    reducer: @Sendable (inout I.State, A) -> Void,
    actionGen: Gen<A>,
    length: ClosedRange<Int> = 0...16,
    initialState: @Sendable @autoclosure () -> I.State
) async -> InvariantCheckResult
```

Each protocol exposes one Strict law via the same `PropertyLawMacro` discovery plugin that v1's Semigroup/Monoid/Group surface. When the user conforms `InboxReferentialIntegrity` (a stub type) to `ReferentialIntegrityInvariant`, SwiftPropertyLaws' discovery emits the property test on every CI run — pointing the verify harness at the user's reducer via a generated conformance stub.

### 9.3 Writeout Path

Bridge suggestions emit to `Tests/Generated/SwiftInferRefactors/<TypeName>/<InvariantName>.swift` (reusing v1's path, never auto-editing existing source — same v1 §16 #1 hard guarantee).

### 9.4 No Subsumption Across the Five Families

The five families are mutually independent — none subsumes another mathematically (unlike v1's CommutativeMonoid ⊃ Monoid hierarchy). When ≥ 2 families fire as Strong on the same reducer, **all of them surface as peer proposals** via an N-arm extended triage prompt:

```
[A/B/B'/B''/.../s/n/?]
```

Each `B*` proposal corresponds to one of the kit's family-specific `InteractionInvariant` protocols. There is no kit `CombinedInvariant<X, Y, ...>` umbrella protocol — conformance to each family stub is independent, and the user accepts each `B*` arm independently. The triage UI shows them as peers, not nested choices.

**Curated dual-pairing.** As in v1's Semilattice + SetAlgebra dual surfacing, v2.0 may surface curated stdlib-protocol Option-B pairs alongside the kit's `InteractionInvariant` — e.g., a reducer that satisfies `ReferentialIntegrityInvariant` and whose State exposes `Identifiable`-keyed collections may surface a secondary `BidirectionalCollection`-shape conformance suggestion. The pairing table is calibrated during M9 and is not committed in v2.0.

-----

## 10. Interactive Triage Mode (Extended)

`swift-infer discover-interaction --interactive` walks suggestions with the same `[A/B/B'/s/n/?]` prompts as v1, plus:

- **T** — show the failing trace (only meaningful for invariants where verify produced `.defaultFails`).
- **V** — re-run the verify pipeline with `--exhaustive` widened sequence-length range.

Decisions logged to `.swiftinfer/decisions.json` (schema v4).

-----

## 11. CI Drift Mode (Extended)

`swift-infer drift --interaction --baseline .swiftinfer/interaction-baseline.json` emits a non-fatal warning per new Strong-tier interaction-invariant suggestion lacking a recorded decision after the baseline date. Drift never fails the build (PRD §16 #3) — it surfaces signal for the developer to act on. Failing trace replays from `Tests/Generated/SwiftInferTraces/` *do* fail the build — they're standard `@Test` regressions, not advisory drift signal.

-----

## 12. Architecture Overview

| Concern | Owner | Notes |
|---|---|---|
| Conformance detection | SwiftPropertyLaws (`PropertyLawMacro`) | Same as v1 — discovery plugin extended for `InteractionInvariant` family |
| `InteractionInvariant` law specs | SwiftPropertyLaws (`PropertyLawKit`) | New in next kit minor |
| Action-sequence generator primitive | SwiftPropertyLaws (`DerivationStrategist`) | New in next kit minor |
| Reducer discovery | SwiftInferProperties (`ReducerDiscovery`) | New in v2.0 |
| Interaction-template registry + scoring | SwiftInferProperties (`InteractionTemplateEngine`) | New in v2.0; extends v1's TemplateEngine |
| Hybrid verify pipeline | SwiftInferProperties (`HybridVerifyPipeline`) | New in v2.0; in-process path is new, subprocess reuses v1.42+ |
| Trace shrinking + replay file emission | SwiftInferProperties (`TraceShrinker`) | New in v2.0 |
| InteractionInvariantBridge | SwiftInferProperties | Analog of v1's RefactorBridge |
| Test execution | SwiftPropertyLaws (`PropertyBackend`) | Unchanged |
| `.swiftinfer/` directory | SwiftInferProperties | Schema v4 for decisions.json |

**Type rule of thumb for contributors:** *contractual* properties live in SwiftPropertyLaws (you said you conform to `ReferentialIntegrityInvariant`, the kit verifies it on every action). *Structural and behavioral* properties live in SwiftInferProperties (the code looks like a reducer with a selection / collection pair, the inference is probabilistic).

-----

## 13. Relationship to SwiftPropertyLaws (Next Minor)

The kit changes for v2.0 are **purely additive** — new protocols (`InteractionInvariant` family) and new `DerivationStrategist` entries (action-sequence generators). Per semver, additive changes are a *minor* bump, not a major one. `Package.swift` will pin to the next minor after current — concretely `from: "2.N+1.0"` where N is the kit's current minor at v2.0 ship time (the kit was renamed at v2.0.0; the current minor floats with kit releases and is not load-bearing for this document).

No breaking kit changes are required for v2.0. A future major bump (v3.0.0) is reserved for if and when a kit redesign breaks v1's `Semigroup`/`Monoid`/etc. shape — adding new protocols alongside the existing ones does not justify it.

Deferred to a future kit minor: `ReachabilityInvariant` (needs bounded model checking — out of v2.0); `TemporalInvariant` (needs virtual clock — out of v2.0); `LivenessInvariant` (subset of temporal).

The one-way downstream relationship is preserved: SwiftInferProperties detects interaction patterns → suggests `InteractionInvariant` conformance → SwiftPropertyLaws verifies the laws on every action sequence thereafter.

-----

## 14. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Daikon trap is louder than v1** | **High** | Hidden Possible tier by default; all five families ship with default Possible visibility through their first three calibration cycles; raise thresholds before adding filters |
| **Reducer discovery surface is noisy across carriers** | High | `--reducer` flag required for multi-candidate modules; default behavior is *list candidates, do not pick* |
| **Curated-binding-table problem recurs per family** | High | Cycle-58/61/69 lessons applied: every new family ships with at least one calibration cycle dedicated to widening the binding/witness table empirically |
| **Action-sequence generators produce invalid sequences** | Medium | Kit's stateful-guards primitive (§8.1); curated guards (`.noDoubleDelete`, `.requireLogin`, `.maxConcurrentTasks`); user can supply project-specific guards |
| **In-process verify can't catch concurrency races** | Medium | Documented non-goal (§3); concurrency-aware verify is a v2.1+ direction |
| **Effect-bearing reducer verify is slow** | Medium | Subprocess path inherits v1.42+ infrastructure; in-process fast path covers the majority case |
| **Action enum is implicit (e.g., @Observable method dispatch)** | Medium | Documented out of scope (§2.3); fallback is the `--action-enum` flag pointing at an explicit enum if the user wants to opt in |
| **State is not Equatable** | Medium | Verify falls back to projection-based checking when the candidate invariant only touches Equatable projected fields (§5.6); when whole-State equality is needed, user supplies an instance method `func equals(_ other: Self) -> Bool` on State that the verify harness calls instead of `==`. No macro is defined for this — the user writes the method by hand |
| **Trace shrinking is non-deterministic** | Low | Seed policy unchanged from v1 §16 #6: SHA256 of suggestion-identity hash, packed into Xoshiro256** state |
| **`InteractionInvariant` law surface bloats SwiftPropertyLaws** | Medium | Kit ships five law protocols only, with strict-law-only laws (no Lawful tier); incremental kit minors deliver families 6–7 later if needed |
| **Calibration takes longer than v1's 27 cycles** | High | §19 Phase 2 acceptance targets are deliberately lower than v1's 70% bar; per-family milestones in §5.8 stay at default `Possible` visibility until three calibration cycles confirm stable acceptance rate (§3.5 policy); no family promotes to default-visible on cycle 1 |
| **Project-vocabulary explosion (witness-table problem at v1.4–v1.30 scale)** | Medium | Same `.swiftinfer/vocabulary.json` extension model; new keys: `cardinalityFieldPatterns`, `referentialIntegrityKeyPaths`, `biconditionalPairPatterns` |

-----

## 15. Performance Expectations

Hard targets enforced by regression tests in CI:

| Operation | Target | Failure mode |
|---|---|---|
| Reducer discovery on 50-file module | < 1 second wall | Regression test fails |
| Interaction-invariant discovery on 5-reducer module | < 3 seconds wall | Regression test fails |
| In-process verify (1k sequences, 5-case Action, 10-field State) | < 100ms wall | Regression test fails |
| Subprocess verify (single reducer, 256 sequences) | < 30 seconds wall | Regression test fails (same budget as v1's subprocess path) |
| Trace shrinking (initial 16-action sequence → minimal) | < 500ms wall | Regression test fails |
| Memory ceiling on 500-file module | < 1 GB resident (v2.0 starting point; recalibrate post-v2.1.0) | Regression test fails |

Numbers are Swift-realistic, not aspirational. SwiftSyntax parsing + in-process action execution dominate. The reference corpus is TCA's `swift-composable-architecture` examples directory, pinned at a commit fixed in `docs/calibration-corpus-v2.0.md` at M1 ship (the file will list each examples-app reducer, its carrier kind, and its expected per-family suggestion counts). v2.0's analog of v1's cycle-1 1167-baseline is the per-family suggestion count against this frozen corpus.

-----

## 16. Failure Modes and Hard Guarantees

Inherits all v1 §16 guarantees. v2.0 adds:

1. **SwiftInferProperties never executes user-side Effects in-process.** The in-process verify path calls only `(S, A) -> S` step semantics. If a reducer returns an `Effect<A>`, that Effect is captured and discarded — never run.
1a. **In-process verify executes user reducer-body code in the same process as `swift-infer`.** This is intentional — pure reducers are safe to run in-process and the speed-up is meaningful. But contributors must not over-promise: "swift-infer doesn't execute user code" is *not* a guarantee. In-process verify runs the body of any reducer that passes the §4.1 purity gate (no Effect / async / Task references), including any non-Effect side-effects in the body (logger calls, static-var reads, etc. — captured by the §4.1 "reducer body has hidden mutability" -∞ veto when detected). The subprocess path runs in a sandboxed SwiftPM work directory the same way v1's verify pipeline does. Routing is driven by the §4.1 type-flow check, exposed as `verifyPath` in §4.3.
2. **SwiftInferProperties never auto-applies an `InteractionInvariant` conformance.** Bridge suggestions write to `Tests/Generated/SwiftInferRefactors/` for manual review (same v1 §16 #1 hard guarantee).
3. **Shrunk traces are deterministic.** Same seed policy as v1 §16 #6: SHA256 of suggestion-identity hash packed into Xoshiro256**. Trace files include the seed in a comment header.
4. **Action-sequence verify is single-threaded.** Concurrency races require a different harness; in-process verify makes no concurrency claims.
5. **`Tests/Generated/SwiftInferTraces/` is a SwiftInferProperties-owned write path.** New in v2.0; same write-only-never-edit guarantee as v1's `Tests/Generated/SwiftInfer/`.
6. **The `--reducer` flag is required for ambiguous targets.** No silent picking of a reducer when ≥ 2 candidates match.

These guarantees are tested by the integration suite (§17). Violation is a release-blocking bug.

-----

## 17. Adoption Tracking and Metrics

v2.0 extends v1's `.swiftinfer/decisions.json` to schema v4. New fields per decision:

- `family`: one of `cardinality` / `referentialIntegrity` / `biconditional` / `conservation` / `idempotence`
- `reducerIdentity`: stable hash of `(module, typeName, funcName, canonical-signature)`
- `actionGeneratorConfidence`: from §4.3
- `verifyOutcome`: same five-category scheme as v1.42+ (`.bothPass` / `.edgeCaseAdvisory` / `.defaultFails` / `.error` / `.architecturalCoveragePending`)
- `traceReplayPath`: optional path to the `Tests/Generated/SwiftInferTraces/` artifact

`swift-infer metrics --interaction` aggregates locally with the same per-template tables as v1's `metrics`, partitioned by family. The five PRD §17.2 metrics from v1 transfer cleanly:

| Metric | v2.0 application |
|---|---|
| Acceptance rate per family | Templates with < 50% acceptance after 20 suggestions are candidates for retirement |
| False-positive rate per family | "Wrong" decisions ÷ total surfaced per family |
| Suppression rate | Suggestions vetoed by `.defaultFails` or `-∞` counter-signals |
| Time-to-adoption | Decision timestamp − reducer-firstSeenAt from SemanticIndex; same `firstSeenAt` anchor as v1.71 |
| Post-acceptance failure rate | Two sub-metrics, both contributing to the v1.71-parked 5th §17.2 metric: (a) **trace-replay regressions** — failures in `Tests/Generated/SwiftInferTraces/<reducer>/<invariant>.swift` after the trace was previously green. Unambiguous; the trace runs as a standard `@Test` on every CI invocation. (b) **verify-outcome flips** — previously-accepted Strong invariants whose verify outcome changes from `.bothPass` to `.defaultFails` or `.error` between CI runs. Noisier than trace-replay (could indicate generator flakiness or a flaky stateful guard rather than a real regression). v2.0 reports both sub-metrics separately. The PRD §17.2 5th metric is naturally measurable here, where it wasn't in v1, because trace replay is a built-in regression surface — but the metric splits two ways and the user reading it needs to know which sub-metric to trust. |

-----

## 18. Integration Tests

Calibration corpus for v2.0 includes:

- **TCA examples directory** (`swift-composable-architecture/Examples/`) — the canonical multi-reducer reference; ~15 reducers across the standard examples
- **2–3 OSS Elm-style reducer projects** (TBD — names will be pinned at M1 ship)
- **Hand-authored reducer corpus** (analog of v1's cycle-27 frozen surface) — a curated set of ~50 reducers exercising each family at least 5 times

Per-family golden-file tests for emitter output. Subprocess verify integration tests bracket the existing v1.42+ infrastructure.

-----

## 19. Success Criteria

v2.0 ships in two phases. Phase 1 must complete before Phase 2 starts.

**Phase 1 — Lifted families (M1–M4):**

| Metric | Target |
|---|---|
| Conservation Possible-tier acceptance rate | ≥ 70% (matches v1 PRD §19 bar) |
| Idempotence Possible-tier acceptance rate | ≥ 70% |
| In-process verify path working | At least 1 reducer in the calibration corpus produces `.bothPass` outcome |
| Subprocess verify path working | At least 1 effect-bearing reducer produces `.bothPass` outcome |
| Reducer-discovery false-positive rate | ≤ 20% of detected reducers are not real reducers |

**Phase 2 — New families (M5–M10):**

| Metric | Target |
|---|---|
| Cardinality Possible-tier acceptance rate (after 3 calibration cycles) | ≥ 50% |
| Referential-integrity Possible-tier acceptance rate (after 3 calibration cycles) | ≥ 60% |
| Biconditional Possible-tier acceptance rate (after 3 calibration cycles) | ≥ 40% |
| Measured-execution rate on calibration corpus | ≥ 30% |
| Bridge suggestion (≥ 3 Strong) trigger frequency | At least 5 reducers in the corpus accumulate ≥ 3 Strong invariants |

Phase 2 targets are lower than Phase 1 deliberately — new templates restart calibration from zero and the cycle-1 1167-baseline experience says 3 cycles is the *minimum* time to stable precision.

-----

## 20. Future Directions (v2.1+)

- **Family 6 — Reachability.** Bounded model checking over reducer state-space. "Authenticated content unreachable from unauth state." Needs an explicit reachability harness — out of v2.0.
- **Family 7 — Temporal.** Virtual-clock-based testing for "spinner disappears within timeout" and "cancelled writes never surface." Needs `UPPAAL`-style clock semantics — out of v2.0.
- **TCA TestStore integration.** Bridge that lets accepted invariants be verified via Point-Free's `TestStore` rather than the SwiftInferProperties verify harness. Smaller scope; cleaner integration with TCA's existing test surface.
- **@Observable view-model carriers.** Once the implicit-action-surface problem (§2.3) has a solution — likely a macro that lifts dispatched method calls to a synthetic Action enum.
- **View-introspection bridges.** ViewInspector integration for the small subset of invariants that *require* rendered-view state (e.g., "focused element is keyboard-accessible"). Probably a separate companion project.
- **Action-sequence mining from user trace logs.** Replace random `Gen<[Action]>` with empirical traces from production. Privacy concerns; probably opt-in per repo.
- **Macros: `@CardinalityInvariant`, `@ReferentialIntegrityInvariant`, etc.** First-class macro expansion for each family, beyond v2.0's generic `@CheckProperty` arms.
- **Concurrency-aware verify.** Parallel-history checking in the quickcheck-state-machine sense — out of v2.0 because the harness is fundamentally different.

-----

## 21. Open Questions

1. **What's the right default sequence length?** v2.0 ships `0...16`; calibration may push it up or down. The trade-off is between coverage (longer sequences exercise more state-space) and shrink quality (shorter sequences produce more readable failing traces).
2. **Implicit vs explicit Action surface.** Should v2.0 ship with a fallback macro that lifts dispatched method calls on `@Observable` models to a synthetic Action enum, or stay strict and require explicit Action enums? Strict is the cleaner v2.0; the fallback is a v2.1+ direction.
3. **Non-Equatable State.** A surprising fraction of SwiftUI state is non-Equatable (closures, AnyView, lazy structures). User-supplied `state.equals(_:)` is the documented workaround, but uptake will be uneven. Should v2.0 try to derive a structural `equals` for the user, or insist they write it?
4. **Calibration corpus bias.** TCA-only calibration risks the binding-table problem — heuristics tuned to TCA conventions may not generalize. Mitigation is including at least one Elm-style and one hand-rolled reducer in the corpus, but finding good OSS exemplars is itself a research task.
5. **The `--architecture` flag.** Should v2.0 ship with an explicit `--architecture tca|generic` flag, or rely on §6.3/§6.4's automatic carrier-kind labeling? The current decision is automatic (no flag); if calibration finds the carrier inference produces noticeable false matches, the flag becomes the v2.0 ship answer.
6. **Trace replay's interaction with `decisions.json`.** When a previously-accepted invariant starts failing on CI via a trace replay, do we auto-revoke the decision, prompt the user, or just fail loudly? The honest answer is "fail loudly" — let humans handle the regression — but that creates a new state for v1's decision schema.
7. **Memberwise State generators.** v1's `DerivationStrategist` handles memberwise generation for plain structs. State structs often contain `@ObservationIgnored` properties, `let` constants set at init, or computed properties — the strategist's existing memberwise pass needs an audit before v2.0 M3 ships.

-----

## Appendix A — Mapping the 8-Family Taxonomy to LTL

For readers who want the formal vocabulary:

| Family | Safety / Liveness | LTL form |
|---|---|---|
| 1. Cardinality | Safety | `G(count ≤ N)` |
| 2. Referential integrity | Safety | `G(ref ∈ extant)` |
| 3. Biconditional | Safety | `G(A ↔ B)` |
| 4. Conservation | Safety | `G(derived = recompute)` |
| 5. Idempotence | Safety | `G(f(f(s, a), a) = f(s, a))` for `a ∈ idempotentActions` |
| 6. Reachability | Reachability (CTL) | `EF(target)` / `AG ¬ unreachable` |
| 7. Temporal | Liveness / bounded liveness | `G(request → F(response))` / `G(request → F<T response)` |
| 8. Accessibility | Out of scope (not temporal-logic-shaped) | — |

v2.0 ships only safety properties (families 1–5). Safety has finite counterexamples and is relatively cheap to check; liveness has infinite-trace counterexamples and is expensive. The deferred families 6–7 are exactly where the tooling cost jumps — `TLA+` and `UPPAAL` exist for those, but bridging into the SwiftSyntax-first inference pipeline is itself a research direction.

-----

## Appendix B — Connection to the v1.0 Arc

The pure-function arc that built v1.0 (cycles 1–68) produced four reusable assets that v2.0 leans on directly:

| v1.0 Asset | v2.0 Application |
|---|---|
| `DerivationStrategist` (kit-side memberwise / CaseIterable / RawRepresentable) | Extended in the next kit minor with `actionSequence(from:length:statefulGuards:)` (primary) + `actionSequence(_:length:statefulGuards:)` (convenience, may return nil) |
| Verify-pipeline subprocess harness (v1.42+) | Routes effect-bearing reducers; same five-category outcome scheme |
| Verify-evidence persistence (`verify-evidence.json`, v1.64+) | Schema-compatible — interaction invariants persist alongside pure-function evidence |
| `.verified` first-class tier (v1.65) | Extends to interaction invariants — bothPass action-sequence verify promotes to `.verified` |
| Verify-as-grade-signal (`bothPass = +50`, `defaultFails = veto`; v1.66) | Identical weights apply to interaction invariants |
| Verify-before-the-cut (v1.67) | Identical ordering — interaction verify runs before the visibility filter |
| SemanticIndex `firstSeenAt` (v1.71 time-to-adoption anchor) | Extends naturally to reducer identities; time-to-adoption metric works for interaction invariants out of the box |
| `Tests/Generated/SwiftInferRefactors/` path (v1 RefactorBridge) | Reused by InteractionInvariantBridge |
| `.swiftinfer/decisions.json` schema | Schema v4 extends v3 — additive only; no breaking migration |

The cycle-1 1167-baseline metric ("how many candidate suggestions does the tool produce before any calibration?") is the natural v2.0 baseline as well; the first per-family calibration cycle will establish that number for cardinality / ref-integrity / biconditional. Conservation and idempotence inherit v1's baseline as the lifted-from-v1 starting point.

-----

## Document History

- **v2.0 (draft)** — Initial draft of the SwiftUI / state-system extension. Five new contributions, five shape families (4 + 5 lifted from v1; 1 + 2 + 3 new), hybrid in-process / subprocess verify, kit next-minor additive `InteractionInvariant` law surface. No surface has shipped.
