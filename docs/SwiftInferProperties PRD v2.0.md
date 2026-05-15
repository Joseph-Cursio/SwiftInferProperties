# Product Requirements Document

## SwiftInferProperties v2.0: Interaction-Invariant Inference for SwiftUI State Systems

**Version:** 2.0 (draft)
**Status:** Planned (no v2.0 surface has shipped; v1.71.0 is the current release line)
**Audience:** Open Source Contributors, Swift Ecosystem
**Depends On:** SwiftPropertyLaws v3.0.0+ (planned major bump — new `InteractionInvariant` law surface; see §11)

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
- **Contribution 2 — ReducerDiscovery.** Carrier-agnostic SwiftSyntax pass that finds reducer-shaped functions (`(S, A) -> S`, `(inout S, A) -> Void`, `(S, A) -> (S, Effect<A>)`) without committing to any one architecture (TCA, Observable, ReSwift, hand-rolled Elm-style). The discovery model deliberately accepts any signature shape that fits — at the cost of a louder Daikon-trap risk that §3.5 addresses directly.
- **Contribution 3 — HybridVerifyPipeline.** Pure reducers (Equatable State, no async / Effect in body) verify **in-process** at < 100ms/1k-action-sequence; effect-bearing reducers fall back to the existing v1.42+ **subprocess** harness with the same five-category outcome scheme. Both paths share the `.bothPass` / `.edgeCaseAdvisory` / `.defaultFails` / `.error` / `.architectural-coverage-pending` vocabulary so v1's measured-execution metric extends cleanly to v2.
- **Contribution 4 — ActionSequenceGenerator.** Kit-side extension to `DerivationStrategist`: synthesize `Gen<[Action]>` from an Action enum, with optional stateful guards (don't fire `.delete(id)` after `.delete(id)` on the same id). Sequences are bounded (default ≤ 16 actions); shrinking minimizes a failing trace to its smallest reproducer. Persisted to `Tests/Generated/SwiftInferTraces/` on failure.
- **Contribution 5 — InteractionInvariantBridge.** When the InteractionTemplateEngine accumulates ≥3 Strong-tier suggestions on the same reducer, propose conformance to a kit-defined `InteractionInvariant` protocol so SwiftPropertyLaws verifies the laws on every CI run thereafter. Analog of v1's RefactorBridge.

All five contributions inherit v1's invariants: opt-in, human-reviewed, never auto-applies, never executes Effects in-process, all output is probabilistic suggestion (§16).

-----

## 2. Problem Statement

### 2.1 Interaction Bugs Dominate Real-World UI Failures

Postmortems across SwiftUI and reactive-UI codebases consistently identify *transition bugs*, *temporal bugs*, *stale-state bugs*, and *race conditions* as the dominant failure modes — not rendering bugs. v1.0 covered pure-function correctness; the much larger surface of *state-system correctness* sits in the reducer layer, where mainstream Swift testing tooling stops at scripted action sequences (Point-Free's `TestStore`) and has no `forAll`-over-actions equivalent to QuickCheck / Hypothesis / quickcheck-state-machine.

### 2.2 The Interaction-Invariant Taxonomy

The natural unit isn't "PBT for SwiftUI" but **interaction invariants** — predicates over `(State, Action) -> State` that must hold for any user action sequence. The taxonomy is shape-based (cardinality, ref-integrity, biconditional, conservation, idempotence, reachability, temporal, accessibility), not domain-based (auth, cart, navigation): the same *shape* recurs across domains and each shape has a different cost/tool profile. Lumping them all under "invariants" hides that — and is exactly the mistake the academic LTL/CTL taxonomy (safety vs liveness vs fairness) avoids.

### 2.3 Why "Any Reducer-Shaped" Is Harder Than TCA Only

v2.0 takes the carrier-agnostic stance: detect any reducer-shaped function regardless of architecture. This is the **most general but loudest Daikon-trap target** of the four scoping options. Three risks the design must mitigate:

1. The reducer convention varies. TCA's `Reducer.body` is one shape; `@Observable` view-models with explicit `dispatch(_:)` are another; hand-rolled Elm-style switches are a third. The discovery surface for the (S, A) → S signature is real but discovery-by-shape risks false matches against non-reducer functions that happen to have the right type signature.
2. The Action enum may be implicit. In `@Observable` models the "actions" are often just public methods on the model — there's no first-class Action type to enumerate. v2.0 documents this case as out of scope; sequence generation requires an explicit Action enum.
3. State may not be Equatable. SwiftUI's @State holds opaque value types regularly; reducer State is often a struct with closures, AnyView, or other non-Equatable fields. The in-process verify path requires Equatable State; the subprocess path can sometimes work around it via custom comparison closures.

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
- TCA-specific TestStore integration (deferred to §20 — keeps v2.0 carrier-agnostic)
- Effects / async / cancellation modeling beyond per-step semantics (the verify pipeline calls each `(S, A) -> S` step; downstream Effect resolution is not simulated)
- Concurrency-race detection (in-process verify is single-threaded; concurrency requires a different harness — §14)
- Stateful PBT in the full quickcheck-state-machine sense (bundles, parallel histories) — v2.0 ships sequential action sequences only

-----

## 3.5 Product Philosophy

v2.0 inherits v1.0's conservative-inference philosophy verbatim and adds one corollary:

> **Interaction-invariant precision is harder than algebraic-law precision.** SwiftUI state graphs have far less structure than function signatures. The curated-binding-table problem (the cycle-58 V1.51.B latent-pair-table bug masking 12 picks for ~13 release cycles, the v1.61 dual-style pair fix, the v1.69 monotonicity-emitter rework) will recur at every new family. Defaults must skew even more aggressively toward suppression.

Concretely this means:

1. **`Possible` tier is hidden by default in v2.0 just as in v1.0.** No exceptions for new families.
2. **Each new family ships behind at least three calibration cycles before being claimed measured.** v1's pattern (cycles 1–27 to drive Possible-tier acceptance to ≥70%) is the precedent — new family X cannot claim "shipped" status until cycles N, N+1, N+2 produce a stable acceptance rate.
3. **The verify pipeline's `.bothPass` outcome is the strongest signal v2.0 emits.** Heuristic-only invariants stay in the lower tiers; only execution evidence promotes to `.verified` (continuing the v1.65 first-class tier introduction).
4. **The Daikon trap is louder.** If calibration shows interaction-template families producing more suggestions than a developer can read in one sitting, raise thresholds — *do not* add filters on top.

-----

## 3.6 Developer Workflow

End-to-end workflow. Each step lists its owning §5–§9 contribution.

1. **Reducer discovery.** Developer runs `swift-infer discover-reducers --target MyApp`. Lists detected reducer-shaped functions with a signature shape + carrier inference (TCA Reducer.body / @Observable method-dispatch / generic `(S, A) -> S`). The user pins the target reducer via `--reducer Inbox.body` when ambiguous.
2. **Interaction-invariant discovery.** `swift-infer discover-interaction --reducer Inbox.body` scans the State struct and Action enum, applies the five template families, and produces tiered suggestions (✓ Strong / ~ Likely / ? Possible) using the same §4 explainability block as v1.
3. **Suggestion review.** Each suggestion shows: family, predicate, evidence trail, candidate generator strategy, expected verify path (in-process vs subprocess), and the same "why suggested" / "why this might be wrong" two-sided block.
4. **Adoption.** Accepted suggestions write `@Test` stubs to `Tests/Generated/SwiftInferInteraction/`. InteractionInvariantBridge suggestions (≥3 Strong on the same reducer) propose kit-conformance stubs in `Tests/Generated/SwiftInferRefactors/`.
5. **Verify.** `swift-infer verify-interaction --reducer Inbox.body` runs N action sequences per accepted invariant — in-process if pure, subprocess if effect-bearing. Outcomes flow into the same five-category vocabulary as v1.
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
| **Reducer body calls async / Effect / Task** | -∞ for in-process; routes to subprocess instead | Detected via type-flow analysis at the SwiftSyntax level. Subprocess verify is *not* a veto; it routes the suggestion through the slower path. |
| **Cardinality witness: ≥ 2 transient-presentation modifiers** | +25 | State exposes ≥ 2 `Bool` / `Optional` fields that look like sheet/alert/fullScreenCover items. Triggers cardinality-family templates. |
| **Referential-integrity witness: KeyPath into collection** | +25 | State has a `selectedID: T.ID?` field and a `items: [T]` field where `T.ID` matches. Triggers ref-integrity templates. |
| **Biconditional witness: parallel state pairs** | +20 | State has a pair `(isLoadingX: Bool, requestX: Task?)` or `(isShowingX: Bool, dataX: T?)`. Triggers biconditional templates. |
| **Counter-signal: implicit action surface** | -20 | Reducer body switches over an action enum, but the action enum has ≥ 3 cases with unhandled-default routes — the action set is implicit. |
| **Counter-signal: reducer has hidden mutability** | -20 | Body mutates global state, static vars, or escapes captured references — verify-pipeline outcomes will be non-deterministic. |
| **Verify outcome: bothPass on action sequences** | +50 | The action-sequence verify pipeline produces `.bothPass` for the invariant across both default and edge generators. Same +50 weight as v1.66. |
| **Verify outcome: defaultFails** | veto (suppression) | Verify pipeline disproved the invariant. Same vetoing semantics as v1.66. |

### 4.2 Tier Mapping

Unchanged from v1: ≥ 75 Strong, 40–74 Likely, 20–39 Possible (hidden by default), < 20 suppressed. The `.verified` tier (v1.65) extends to interaction invariants: a Strong suggestion with `.measuredBothPass` evidence promotes to `.verified` and floats to the head of the discover stream.

### 4.3 Generator Awareness

Every interaction-invariant suggestion's evidence record adds:

- `actionGeneratorSource`: `.derivedFromCaseIterableAction` | `.derivedWithStatefulGuards` | `.registered` | `.todo`
- `actionGeneratorConfidence`: `.high` | `.medium` | `.low`
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

**Pattern:** State has a derived value (computed property or repeated computation) that should equal the recomputation from primary fields.

**Witnesses:**
- A State computed-var `total` whose definition references `items.reduce(0, +)` (or equivalent).
- An Action `.setTotal(Decimal)` whose handler writes to the stored property — suggesting the derived value is cached and should equal the recomputation.
- Three or more action handlers that touch both a stored aggregate (`total`) and a contributing collection (`items`) — suggesting an invariant `total == items.map(\.price).reduce(0, +)`.

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

-----

## 6. Contribution 2: ReducerDiscovery

### 6.1 Description

SwiftSyntax pass that scans the target module for reducer-shaped functions. Carrier-agnostic: any function matching one of the three canonical signatures qualifies as a candidate.

### 6.2 Canonical Signatures

| Shape | Example | In-process verifiable? |
|---|---|---|
| `(S, A) -> S` | TCA-style, Elm-style, hand-rolled | Yes (if S: Equatable, no Effect/async in body) |
| `(inout S, A) -> Void` | TCA's `Reducer.body` post-2022 | Yes (S: Equatable; in-process verify makes a copy and feeds it in) |
| `(S, A) -> (S, Effect<A>)` | TCA pre-2022, ReSwift with thunks | No — routes to subprocess |
| `func dispatch(_ action: A)` on a class | @Observable view-models | **Out of scope in v2.0** — no first-class Action carrier |

### 6.3 Carrier Inference

Each reducer candidate gets a `carrierKind` label (`.tca` / `.observable` / `.elmStyle` / `.generic`) inferred from imports and context (e.g., the function is `body` on a `Reducer`-conforming type → `.tca`). The label is informational; templates fire on all carrier kinds equally.

### 6.4 Disambiguation

When multiple reducer candidates exist in the target, the user pins via `--reducer <module>.<typeName>.<funcName>`. The default behavior (no flag) is to list all candidates with their carrier-kind labels and exit — never silently picking one.

### 6.5 Discovery Performance Budget

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

1. Generate a sequence of N actions via the action-sequence generator (§8).
2. Apply each action in turn, checking the candidate invariant at each step.
3. On failure, shrink the sequence to its minimal reproducer (drop-prefix, drop-suffix, halving — standard QuickCheck shrinking).
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
| Has Effect/Task but State: Equatable | Subprocess (or in-process with stub-mocked Effects) | Effect resolution unknown; subprocess captures real semantics |
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

`SwiftPropertyLaws v3.0.0` extends `DerivationStrategist` with:

```swift
public extension DerivationStrategist {
    static func actionSequence<A: CaseIterable & Sendable>(
        _ actionType: A.Type,
        length: ClosedRange<Int> = 0...16,
        statefulGuards: [(any StatefulGuard<A>)] = []
    ) -> Gen<[A]>
}
```

Stateful guards are user-supplied filters that suppress action sequences containing forbidden transitions (e.g., "no `.delete(id)` after `.delete(id)` on the same id"). v2.0 ships three curated guards:

- `.noDoubleDelete` — pairs a `.delete(id)` action with a `.insert(_:)` action by id.
- `.requireLogin` — `.dispatchAfterLogin` actions are gated by a preceding `.login` action.
- `.maxConcurrentTasks(N)` — at most N async-effect-bearing actions queued at any point.

### 8.2 Action-Inference From Reducer Body

When the Action enum has cases the engine doesn't know how to enumerate (e.g., associated `T` payloads), the generator falls back to the kit's `DerivationStrategist` per-case-payload strategy chain (`.caseIterable` / `.rawRepresentable` / `.memberwise` / `.codableRoundTrip` / `.todo`). Same tiered fallback as v1's TestLifter generator inference (§7.4 of v1.0).

### 8.3 Confidence Surfacing

The action-sequence generator's confidence (`.high` / `.medium` / `.low`) flows into the §4.3 generator-awareness fields. A low-confidence generator (e.g., several `.todo` case payloads) downgrades the invariant suggestion's tier by one band.

-----

## 9. Contribution 5: InteractionInvariantBridge

### 9.1 Description

Analog of v1's RefactorBridge: when InteractionTemplateEngine accumulates ≥ 3 Strong-tier suggestions on the same reducer, propose conformance to a kit-defined `InteractionInvariant` protocol.

### 9.2 Kit-Side Law Surface (v3.0.0)

SwiftPropertyLaws v3.0.0 ships new protocols:

```swift
public protocol InteractionInvariant {
    associatedtype State
    associatedtype Action
    static func reduce(_ state: State, _ action: Action) -> State
    static func invariantHolds(in state: State) -> Bool
}

public protocol CardinalityInvariant: InteractionInvariant { /* law: count ≤ N */ }
public protocol ReferentialIntegrityInvariant: InteractionInvariant { /* law: ref ∈ extant */ }
public protocol BiconditionalInvariant: InteractionInvariant { /* law: A ↔ B */ }
public protocol ConservationInvariant: InteractionInvariant { /* law: derived = recompute */ }
public protocol ActionIdempotenceInvariant: InteractionInvariant { /* law: f(f(s), a) = f(s, a) */ }
```

Each protocol exposes one Strict law via the same `PropertyLawMacro` discovery plugin that v1's Semigroup/Monoid/Group surface. When the user conforms `Inbox` to `ReferentialIntegrityInvariant`, SwiftPropertyLaws' discovery emits the property test on every CI run.

### 9.3 Writeout Path

Bridge suggestions emit to `Tests/Generated/SwiftInferRefactors/<TypeName>/<InvariantName>.swift` (reusing v1's path, never auto-editing existing source — same v1 §16 #1 hard guarantee).

### 9.4 Strict-Subsumption + Incomparable Arms

When two interaction-invariant protocols are mathematically incomparable (e.g., a reducer satisfies both `CardinalityInvariant` and `ReferentialIntegrityInvariant`), both are emitted as peer proposals via the `[A/B/B'/s/n/?]` extended prompt that v1.8 introduced. No subsumption hierarchy across the five families is currently defined.

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
| `InteractionInvariant` law specs | SwiftPropertyLaws (`PropertyLawKit`) | New in v3.0.0 |
| Action-sequence generator primitive | SwiftPropertyLaws (`DerivationStrategist`) | New in v3.0.0 |
| Reducer discovery | SwiftInferProperties (`ReducerDiscovery`) | New in v2.0 |
| Interaction-template registry + scoring | SwiftInferProperties (`InteractionTemplateEngine`) | New in v2.0; extends v1's TemplateEngine |
| Hybrid verify pipeline | SwiftInferProperties (`HybridVerifyPipeline`) | New in v2.0; in-process path is new, subprocess reuses v1.42+ |
| Trace shrinking + replay file emission | SwiftInferProperties (`TraceShrinker`) | New in v2.0 |
| InteractionInvariantBridge | SwiftInferProperties | Analog of v1's RefactorBridge |
| Test execution | SwiftPropertyLaws (`PropertyBackend`) | Unchanged |
| `.swiftinfer/` directory | SwiftInferProperties | Schema v4 for decisions.json |

**Type rule of thumb for contributors:** *contractual* properties live in SwiftPropertyLaws (you said you conform to `ReferentialIntegrityInvariant`, the kit verifies it on every action). *Structural and behavioral* properties live in SwiftInferProperties (the code looks like a reducer with a selection / collection pair, the inference is probabilistic).

-----

## 13. Relationship to SwiftPropertyLaws v3.0.0

`Package.swift` will be bumped to `from: "3.0.0"` at v2.0 ship. v3.0.0 is a major bump because the new `InteractionInvariant` protocol family is large enough to be a public-API change worth signalling, and because new `DerivationStrategist` API for action-sequence generation extends the public surface.

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
| **State is not Equatable** | Medium | User supplies `state.equals(_:)` via macro or annotation; verify path uses it instead of `==` |
| **Trace shrinking is non-deterministic** | Low | Seed policy unchanged from v1 §16 #6: SHA256 of suggestion-identity hash, packed into Xoshiro256** state |
| **`InteractionInvariant` law surface bloats SwiftPropertyLaws** | Medium | Kit ships five law protocols only, with strict-law-only laws (no Lawful tier); incremental kit minors deliver families 6–7 later if needed |
| **Calibration takes longer than v1's 27 cycles** | High | Acknowledged up front: success-criteria targets in §19 are deliberately lower than v1's 70% bar to reflect this |
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

Numbers are Swift-realistic, not aspirational. SwiftSyntax parsing + in-process action execution dominate. Calibrated against TCA's `swift-composable-architecture` examples directory as the reference corpus.

-----

## 16. Failure Modes and Hard Guarantees

Inherits all v1 §16 guarantees. v2.0 adds:

1. **SwiftInferProperties never executes user-side Effects in-process.** The in-process verify path calls only `(S, A) -> S` step semantics. If a reducer returns an `Effect<A>`, that Effect is captured and discarded — never run.
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
| Post-acceptance failure rate | Trace-replay regressions in `Tests/Generated/SwiftInferTraces/` that newly fail on CI. **This is finally the natural setting for the 5th §17.2 metric that v1.71 parked** — the trigger isn't open here: trace replays run on every CI invocation, no separate hook needed. |

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
5. **The `--architecture` flag.** Should v2.0 ship with an explicit `--architecture tca|observable|generic` flag, or stay carrier-agnostic and infer? Carrier-agnostic is the current decision (§2.3) but it may be the wrong one — early calibration will tell.
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
| 5. Idempotence | Safety | `G(f(f(s), a) = f(s, a))` |
| 6. Reachability | Reachability (CTL) | `EF(target)` / `AG ¬ unreachable` |
| 7. Temporal | Liveness / bounded liveness | `G(request → F(response))` / `G(request → F<T response)` |
| 8. Accessibility | Out of scope (not temporal-logic-shaped) | — |

v2.0 ships only safety properties (families 1–5). Safety has finite counterexamples and is relatively cheap to check; liveness has infinite-trace counterexamples and is expensive. The deferred families 6–7 are exactly where the tooling cost jumps — `TLA+` and `UPPAAL` exist for those, but bridging into the SwiftSyntax-first inference pipeline is itself a research direction.

-----

## Appendix B — Connection to the v1.0 Arc

The pure-function arc that built v1.0 (cycles 1–68) produced four reusable assets that v2.0 leans on directly:

| v1.0 Asset | v2.0 Application |
|---|---|
| `DerivationStrategist` (kit-side memberwise / CaseIterable / RawRepresentable) | Extended in v3.0.0 with `actionSequence(_:length:statefulGuards:)` |
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

- **v2.0 (draft)** — Initial draft of the SwiftUI / state-system extension. Five new contributions, five shape families (4 + 5 lifted from v1; 1 + 2 + 3 new), hybrid in-process / subprocess verify, kit v3.0.0 `InteractionInvariant` law surface. No surface has shipped.
