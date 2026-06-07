# @Observable View-Model Carrier Proposal

**Status:** Draft / proposal — not yet committed to any milestone.
**Target:** SwiftInferProperties (this repo). Extends ReducerDiscovery (§6) and the verify pipeline; no kit changes required.
**Date:** 2026-06-07
**Relates to:** PRD v2.0 §2.3 (scope boundary), §20 ("@Observable view-model carriers"), §21 open question #2 (implicit vs explicit Action surface).

## 1. Summary

Teach ReducerDiscovery to treat an `@Observable` view-model class as a reducer carrier by **lifting its mutating methods into a synthetic Action enum**. Today v2.0 is scoped to carriers with a *first-class, enumerable Action type* — hand-rolled reducers, Elm-style reducers, and TCA `Reducer.body`. The single largest class of modern SwiftUI state — the `@Observable` "MV" view-model, where actions are method calls rather than enum cases — is explicitly out of scope (§2.3). This proposal removes that boundary by synthesizing the Action enum the discovery and action-sequence machinery already require, so the rest of the pipeline (interaction-invariant templates, hybrid verify, the InteractionInvariantBridge) works unchanged.

This is the highest-leverage UI-paradigm extension available: it brings the dominant post-TCA SwiftUI architecture into the same interaction-invariant inference that v2.0 built for reducers, without touching the verify harness or the kit.

## 2. Motivation

### 2.1 The paradigm gap

v2.0's §2.1 thesis — interaction bugs (transition / stale-state / cardinality / referential-integrity) dominate real-world UI failures — is *not* TCA-specific. It is a claim about stateful UI in general. But v2.0 can only act on it where the state machine is spelled as `(State, Action) -> State` with an enumerable `Action`. The `@Observable` macro (Swift 5.9+, now the Apple-default for SwiftUI state) produces carriers shaped like:

```swift
@Observable
final class CartModel {
    var items: [Item] = []
    var selectedID: Item.ID?
    var isCheckingOut = false

    func add(_ item: Item) { items.append(item) }
    func remove(id: Item.ID) { items.removeAll { $0.id == id }; if selectedID == id { selectedID = nil } }
    func select(_ id: Item.ID) { selectedID = id }
    func beginCheckout() { isCheckingOut = true }
}
```

Every interaction invariant v2.0 ships targets is *present and checkable* here: cardinality ("at most one of {browsing, checkingOut}"), referential integrity (`selectedID ∈ items[*].id` — and note `remove` already tries to maintain it, which is exactly the kind of hand-maintained invariant that rots), conservation, biconditional, idempotence (`select(x); select(x)` ≡ `select(x)`). The *only* thing missing versus a reducer is the Action enum — and that's a syntactic accident of the architecture, not a semantic one.

### 2.2 Why this is the right next carrier (not @Observable-specific cleverness)

The action surface of an `@Observable` model *is* its set of mutating methods. That's not a heuristic guess — it's the definition of how the view drives the model. Lifting `func add(_:)`, `func remove(id:)`, `func select(_:)` into

```swift
enum Action { case add(Item); case remove(id: Item.ID); case select(Item.ID); case beginCheckout }
```

is a mechanical, total, and reversible transform. The dispatch function `(inout Model, Action) -> Void` is synthesized as a `switch` that calls the original method per case. Once that synthetic pair exists, the model is indistinguishable from an `(inout S, A) -> Void` reducer to everything downstream.

### 2.3 Why it was deferred, and why now

§21 #2 framed the choice as "strict (require explicit Action enums) vs. fallback (lift method calls)." Strict was correct for the v2.0 *ship* — it kept the carrier-detection surface small while the interaction-invariant templates were being calibrated against TCA. With the templates now calibrated (cycle-7 baseline, 92 reducers / 76 interactions) and the five families stable, the fallback is the natural v2.1 expansion: the templates and verify path are proven, and the only new surface is *one more carrier-discovery front-end* that feeds them.

## 3. Design

### 3.1 What counts as an @Observable carrier

Discovery fires on a `class` (or `@Observable`-macro-expanded type) when **all** hold:

1. The type is annotated `@Observable` (or, conservatively-off-by-default, `@Bindable`/`ObservableObject` — see §6 #1).
2. It has ≥1 stored mutable (`var`) property that is not `@ObservationIgnored`. (The state.)
3. It has ≥1 method that mutates state. (The action surface.)

This is *signature-detectable*, same philosophy as §6.2. As with reducers, the default is **list candidates with a carrier-kind label (`observable`) and exit** — never silently pick one. The user pins via the existing `--reducer <module>.<typeName>` mechanism (extended to accept a type with no func, since the carrier *is* the type here, not a specific method).

### 3.2 The Action-lifting transform

For each lifted method, one Action case:

| Method shape | Synthesized case | Notes |
|---|---|---|
| `func beginCheckout()` | `case beginCheckout` | no payload |
| `func add(_ item: Item)` | `case add(Item)` | positional payload |
| `func remove(id: Item.ID)` | `case remove(id: Item.ID)` | labeled payload preserved |
| `func select(_ id: Item.ID)` | `case select(Item.ID)` | — |

The synthesized dispatcher:

```swift
func _dispatch(_ model: inout CartModel, _ action: Action) {
    switch action {
    case .beginCheckout:      model.beginCheckout()
    case .add(let i):         model.add(i)
    case .remove(let id):     model.remove(id: id)
    case .select(let id):     model.select(id)
    }
}
```

`Gen<[Action]>` then comes from the kit's `DerivationStrategist.actionSequence(from:)` exactly as for a real reducer — the synthetic enum is a normal `CaseIterable`-derivable / payload-generated Action.

### 3.3 Eligibility filters (the scope of "liftable")

A method is **liftable** only if every parameter type is generatable by the kit's `DerivationStrategist`. Methods that are not liftable are *dropped from the action surface with a recorded reason* (explainability is first-class — PRD §4.5), not silently. Initial v2.1 filters — start strict, widen on calibration:

- **Liftable:** value-type parameters the strategist can generate (stdlib scalars, `CaseIterable`/`RawRepresentable` enums, memberwise-generatable structs, the model's own `Item.ID`-style associated types when generatable).
- **Not liftable (v2.1):** `@escaping` closures, generics on the method, `async`/`throws` methods, parameters of non-generatable reference types, `inout` parameters. These are the same boundaries v2.0 already draws for effect-bearing reducers (which route to subprocess) and non-generatable state.

A carrier with *some* non-liftable methods still produces a (smaller) action surface — the proposal does not require all-or-nothing. The explainability block reports "lifted 4/6 methods; `subscribe(_:)` skipped (escaping closure param), `load() async` skipped (async)."

### 3.4 State equality

Same problem and same answer as §2.3 risk 3 / §21 #3: `@Observable` state is frequently non-Equatable (closures, `AnyView`, tasks). The in-process verify path tolerates this for invariants over *projected* fields (the templates already project); the subprocess path accepts a user-supplied `state.equals(_:)`. No new mechanism — `@Observable` inherits v2.0's existing non-Equatable handling.

### 3.5 Purity / verify routing

`ReducerPurityAnalyzer` (M8) classifies the synthesized dispatcher the same way it classifies a reducer body: a model whose methods only mutate stored `var`s is `.pure` → in-process verify; a model whose methods spawn `Task`/await/call out is `.effectBearing` → subprocess. `@Observable` models that kick off `Task`s in methods are common, so expect a higher subprocess fraction than the TCA corpus — acceptable, the harness is shared.

## 4. Pipeline impact (what changes vs. what doesn't)

| Stage | Change? |
|---|---|
| ReducerDiscovery front-end | **New** `ObservableCarrierDiscoverer` + Action-lifter. The only substantial new code. |
| `ReducerCandidate` model | **Minor** — add `observable` to `ReducerCarrierKind`; carry the lifted-method→case map + skipped-method reasons. |
| InteractionTemplateEngine (5 families) | **None** — operates on the synthesized `(inout S, A)` shape. |
| `DerivationStrategist.actionSequence` | **None** — synthetic Action is a normal enum. |
| Hybrid verify (in-process / subprocess) | **None** — routes on purity as today. |
| InteractionInvariantBridge | **None** — bridges on accumulated signals as today. |
| Explainability / triage | **Minor** — surface the lifted/skipped method report. |

The shape of the change — one new discovery front-end feeding an unchanged downstream — is the same shape as M1.B (the TCA walker) was: TCA reducers also "don't match the canonical signatures directly" (§2.3 risk 2) and were brought in by a carrier-specific recovery pass. @Observable is the second such pass.

## 5. Calibration & success criteria

- **Corpus:** §21 #4 already flags TCA-only calibration bias and asks for non-TCA exemplars. `@Observable` MV apps are the obvious diversification — add 2-3 OSS `@Observable`-architecture apps to the corpus. This proposal *helps* the existing bias problem rather than adding a new one.
- **Precision target:** hold the same per-family precision bars as §5; do not let the larger carrier surface lower the bar (the "avoid the Daikon trap" design decision — raise thresholds, don't pile on filters).
- **Baseline metric:** record the cycle-1-style pre-calibration candidate count for the `@Observable` corpus separately, so its acceptance-rate curve is measured independently of the reducer corpus.

## 6. Open questions

1. **`ObservableObject` / `@Published` too, or `@Observable` only?** The pre-macro `ObservableObject` + `@Published` pattern is structurally identical (mutating methods over published state) and still enormous in existing codebases. Lifting it is the same transform. Proposal: ship `@Observable` first (cleaner detection), gate `ObservableObject` behind a flag or a later sub-milestone once the lifter is proven.
2. **Computed-property invariants.** `@Observable` models often expose derived state as computed `var`s (`var total: Decimal { items.reduce(...) }`). These are perfect *conservation* template targets (cached-vs-recompute) — but only when there's also a stored cache to compare against. When the derived value is purely computed, there's no invariant to violate. Detect and skip the no-cache case.
3. **Method side-effects on `self` beyond the stored state.** A method that mutates a stored `var` *and* writes to `UserDefaults` is `.effectBearing` → subprocess, fine. But one that mutates a stored *reference-type* property's interior (`self.cache.insert(...)`) may read as pure to a shallow analyzer while actually carrying hidden mutability. `ReducerPurityAnalyzer`'s `.hiddenMutability` class already exists for exactly this — confirm it triggers on reference-type-interior mutation.
4. **Action-surface explosion.** A model with 20 methods yields a 20-case Action enum and a large `Gen<[Action]>` space. Sequence-length defaults (§21 #1, `0...16`) may need per-carrier tuning when the action alphabet is large. Measure before tuning.
5. **`--architecture observable|tca|generic` flag.** §21 #5 left carrier inference automatic with no flag. Adding `@Observable` makes a plain `class` with mutating methods look carrier-ish; if automatic inference produces false matches, the flag becomes the disambiguator. Decide on calibration evidence, not pre-emptively.

## 7. What this proposal will NOT do

1. **Infer actions from view code.** The action surface is the model's mutating methods, full stop — not "what buttons in the SwiftUI view call." Reading the view layer to discover dispatch is a much larger, much noisier project (and overlaps the deferred view-introspection direction, §20).
2. **Handle implicit-effect actions** (methods that *only* fire effects, mutate nothing). No state delta → no interaction invariant. Skipped with a reason.
3. **Auto-apply anything.** Same invariant as all of v2.0: opt-in, human-reviewed, never executes in-process effects, all output is suggestion.
4. **Touch the kit.** Unlike the Ring / Semigroup work, this is purely a SwiftInferProperties-side discovery front-end. No SwiftPropertyLaws change.
