# TestStore Trace Mining Proposal

**Status:** Draft / proposal — not yet committed to any milestone.
**Target:** SwiftInferProperties (this repo). Extends SwiftInferTestLifter and the ActionSequenceGenerator (Contribution 4); no kit changes required.
**Date:** 2026-06-07
**Relates to:** PRD v2.0 §20 ("Action-sequence mining from user trace logs"), §21 open question #1 (default sequence length), Contribution 4 (ActionSequenceGenerator), the existing TestLifter milestone arc.

## 1. Summary

Seed `Gen<[Action]>` from the **action sequences already written in a repo's existing TCA `TestStore` tests**, instead of (or alongside) random generation. v2.0's ActionSequenceGenerator synthesizes random bounded action sequences from the Action enum. Real TCA test suites already contain hand-curated, semantically-meaningful action orderings — every `await store.send(.foo)` / `await store.receive(.bar)` is a developer asserting "this ordering matters." Mining those scripts gives the verify pipeline a corpus of *realistic* sequences to bias generation toward, directly improving the coverage-vs-shrink-quality trade-off that §21 #1 leaves open.

This is the §20 "action-sequence mining" direction, but sourced from **scripted tests rather than production trace logs** — which sidesteps the privacy concern §20 itself flags, requires no runtime instrumentation, and reuses TestLifter's existing test-parsing infrastructure.

## 2. Motivation

### 2.1 Random sequences under-sample the interesting orderings

`Gen<[Action]>` over a k-case Action enum with length `0...16` samples uniformly from a combinatorially huge space. Most random sequences are *uninteresting* — they never set up the precondition that makes an invariant violable. The bug in "selecting an item then deleting a *different* item must not clear the selection" requires the specific ordering `select(a); delete(b)`; random generation finds it eventually, but spends most of its budget elsewhere, and the failing trace it produces is long and needs heavy shrinking.

### 2.2 The repo already contains the good orderings — for free

A TCA codebase that this tool runs on *already ships* a `TestStore` suite. Those tests are a developer's curated answer to "what action orderings matter for this reducer":

```swift
func testSelectionSurvivesUnrelatedDelete() async {
    let store = TestStore(initialState: Feature.State(items: [a, b])) { Feature() }
    await store.send(.select(a.id)) { $0.selectedID = a.id }
    await store.send(.delete(b.id)) { $0.items = [a] }
    // developer asserts selectedID is still a.id by omission
}
```

The ordered list `[.select(a.id), .delete(b.id)]` is a hand-written, meaningful trace. A codebase has dozens of these. They are *exactly* the empirical action distribution §20 wanted from production logs — minus the privacy problem, minus the instrumentation, and already parsed-adjacent by TestLifter.

### 2.3 Why TestLifter is the right home

SwiftInferTestLifter already "analyzes existing XCTest + Swift Testing suites, slices test bodies into setup + property regions, detects cross-validation evidence." Extracting `store.send(...)` / `store.receive(...)` call sequences is the same kind of test-body AST slice it already does for cross-validation signals — a new extractor over the same parsed bodies, not new parsing infrastructure.

## 3. Design

### 3.1 What gets mined

For each `TestStore`-based test function targeting a discovered reducer, extract the ordered sequence of dispatched actions:

- `await store.send(.action(args))` → `.action(args)` (a *sent* action; user-driven)
- `await store.receive(.action(args))` → optionally recorded as an *expected effect output*, not a user action (see §6 #1)
- The `TestStore(initialState:)` argument → a recorded *seed initial state* (feeds generation of starting states, §5)

The result per reducer is a set of **observed action traces**: `[[Action]]`, each a real ordering a developer wrote.

### 3.2 How traces bias generation

Three modes, increasingly aggressive — ship mode (a), gate (b)/(c) on calibration:

**(a) Replay-then-extend (default).** The verify run prepends observed traces to the random corpus: every mined trace is checked verbatim first, then random generation continues for the remaining budget. Cheap, strictly additive coverage, and any invariant the developer's own test ordering already exercises gets checked immediately.

**(b) Prefix-biased generation.** Use observed traces as *prefixes* the generator extends with random tails. Reaches "developer set up this realistic state, then what happens under arbitrary continued use?" — the highest-value sequences, since they start from human-plausible states and explore outward.

**(c) Alphabet/transition weighting.** Build a first-order Markov model of action→action transitions from the mined traces and bias random generation toward observed transitions. Most aggressive; risks overfitting to the test suite's habits (the binding-table problem, §21 #4). Behind a flag.

### 3.3 Shrinking benefit

Mined traces are short and meaningful, so failures found by replay-then-extend already start near-minimal — less shrinking, more readable counterexamples. This is the concrete payoff against §21 #1's "longer sequences → more coverage but worse shrink quality" tension: realistic short prefixes get coverage *and* readability.

## 4. Pipeline impact

| Stage | Change? |
|---|---|
| SwiftInferTestLifter | **New** `TestStoreTraceExtractor` over already-sliced test bodies. The main new code. |
| ActionSequenceGenerator (kit-side `DerivationStrategist`) | **Minor** — accept an optional `seedTraces: [[Action]]` / `prefixes:` argument; default empty preserves current behavior. Additive. |
| Verify pipeline | **Minor** — thread mined traces from discovery into the generator call; mode (a) is just "check these first." |
| Interaction templates / Bridge | **None.** |
| Explainability | **Minor** — "checked 12 developer-authored traces + 1000 generated" in the evidence block. |

### 4.1 Kit coordination

Mode (a) needs no kit change (the verify driver just runs extra explicit sequences before generation). Modes (b)/(c) want a small additive `DerivationStrategist.actionSequence(from:length:statefulGuards:seedPrefixes:)` overload — additive, defaulting to today's behavior, same shape as the existing `actionSequence` surface noted in PRD Appendix B. No breaking change.

## 5. Initial-state mining (a bonus the same extractor yields)

`TestStore(initialState: Feature.State(items: [a, b]))` is a developer-curated *starting state*. v2.0 generates initial states from the State type's memberwise strategist; mined initial states are realistic seeds that bias state generation toward plausible configurations (a non-empty `items`, a selected ID that exists). Same replay-then-extend posture: check from mined seeds first, then generated seeds. Falls directly out of parsing the `TestStore(initialState:)` argument — near-zero marginal cost once the extractor exists.

## 6. Open questions

1. **`send` vs `receive`.** A `receive` is an *effect output*, not a user action — replaying it as a user-sent action is wrong (it asserts the system produced it). v2.0's in-process path doesn't run effects at all. Proposal: mine only `send` actions for the user-action corpus; record `receive` separately as effect-shape evidence for the subprocess path, or ignore in v1.
2. **Argument concreteness.** Mined actions carry *concrete* args (`.select(a.id)` for a specific `a`). For generation we want the *case* with *generated* args, but the concrete trace is also valuable verbatim. Mode (a) uses concrete; modes (b)/(c) generalize to the case and re-generate args. Decide per mode.
3. **Overfitting (the binding-table risk).** §21 #4 warns TCA-tuned heuristics may not generalize. Trace mining is *more* susceptible — it biases toward exactly what the test author already thought of, potentially missing the orderings they *didn't* test (which is where bugs hide). Mitigation: replay-then-extend (mode a) keeps full random coverage as the floor; never *replace* random generation with mined traces, only prepend/bias. This must be a hard design rule.
4. **Non-TCA carriers.** Hand-rolled and Elm-style reducers rarely have a `TestStore`; their tests dispatch differently (direct `reduce(&state, action)` calls). The extractor can be generalized to "sequences of reduce-shaped calls in any test body," but TCA `TestStore` is the high-density, uniform-syntax starting point. Generalize on demand.
5. **Stale traces.** A mined trace references an Action case that was later renamed/removed compiles-fails in the host repo anyway, so the test suite is a self-validating source — if it compiles, the traces are current. This is a quiet advantage over production logs (which can reference long-dead action shapes).

## 7. What this proposal will NOT do

1. **Touch production data.** The whole point is to get §20's empirical-trace value from *scripted tests*, avoiding the privacy/instrumentation cost of real user logs. Production-log mining stays deferred.
2. **Replace random generation.** Mined traces *augment* the corpus; they never become the sole source (§6 #3). Random generation remains the coverage floor.
3. **Integrate with TCA `TestStore` as a verify backend.** That's a separate §20 direction ("TCA TestStore integration" — verify *via* TestStore). This proposal *reads* TestStore tests as a data source; it does not *run* through TestStore. Distinct projects.
4. **Auto-apply.** Opt-in, human-reviewed, suggestion-only — same as all of v2.0.
