# TestStore Trace Mining Proposal

**Status:** **SHIPPED IN FULL + ARCHIVED (2026-07-21) — Slices 1–3, all three generation modes, measured proof, and two hardening fixes.** The build-out is tracked in `docs/teststore-trace-mining-build-plan.md` — read it first; this proposal is the design record it was grounded against. **Two latent bugs surfaced by the Slice-3 measured corpus and fixed:** (1) payload-bearing idempotence witnesses (`case select(Int)`) emitted the bare uncompilable `.select` — now the payload is synthesized (x-curried `.select(0)`); (2) a non-constructible-payload witness (`select(Item)`) wasted a full build before landing at coverage-pending — now a pre-build gate skips it with a disclosed reason. Both live in the interaction verify path, not the trace-mining code, but were only reachable once mining exercised payload-bearing cases. What shipped: **Slice 1** — `TestStoreTraceExtractor` + `MinedActionTrace`/`MinedAction` in `SwiftInferTestLifter` (mines `store.send`/`receive` orderings, reducer type, and initial-state expr; `send` feeds the user-action corpus, `receive` kept separate per §6 #1). **Slice 2** — payload-free mode (a) replay-then-extend: `ActionSequenceStubEmitter.Inputs.seedTraces` + `MinedTraceSelector` + `VerifyInteractionPipeline.resolveEmitAndSeed`, checking mined orderings through the same invariant loop *before* random generation, coverage floor preserved. **Slice 3** — the rest: **payload-bearing generalization** (§6 #2 — canned literals reusing the random generator's own values, so no new precision risk), **any-carrier alphabet capture** (`ActionAlphabetScanner`, §6 #4), **initial-state seeding** (§5 — self-contained `TestStore(initialState:)` exprs only), **mode (b) prefix-biasing** (`--trace-prefix-bias`), and **mode (c) Markov synthesis** (`--trace-markov`). **Nothing left unbuilt** — the one honest gap is a purpose-built *measured* corpus proving a generalized trace compiles end-to-end (the emit + wiring are proven; it only reconfirms compilation).
**Target:** SwiftInferProperties (this repo). Extends SwiftInferTestLifter and the ActionSequenceGenerator (Contribution 4); no kit changes required (confirmed — even mode (b) prefix-biasing was realized engine-side).
**Date:** 2026-06-07 (status refreshed 2026-07-21)
**Relates to:** PRD v2.0 §20 ("Action-sequence mining from user trace logs"), §21 open question #1 (default sequence length), Contribution 4 (ActionSequenceGenerator), the existing TestLifter milestone arc. **As-built plan:** `docs/teststore-trace-mining-build-plan.md`.

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

**(a) Replay-then-extend (default). — ✅ SHIPPED (Slice 2, payload-free).** The verify run prepends observed traces to the random corpus: every mined trace is checked verbatim first, then random generation continues for the remaining budget. Cheap, strictly additive coverage, and any invariant the developer's own test ordering already exercises gets checked immediately. *As built: the emitter runs each mined payload-free ordering through the same per-step invariant + post-loop check as a generated sequence, ahead of the random loop, guarded by the shrink pin. Payload-bearing traces are mined but not yet replayed (§6 #2).*

**(b) Prefix-biased generation. — ✅ SHIPPED (Slice 3d, `--trace-prefix-bias`, off by default).** Use observed traces as *prefixes* the generator extends with random tails. Reaches "developer set up this realistic state, then what happens under arbitrary continued use?" — the highest-value sequences, since they start from human-plausible states and explore outward. *As built: realized entirely engine-side (each mined ordering is replayed then extended with a random tail from the same generator) — the kit-side `seedPrefixes:` overload (§4.1) turned out unnecessary.*

**(c) Alphabet/transition weighting. — ✅ SHIPPED (Slice 3e, `--trace-markov`, off by default).** Build a first-order Markov model of action→action transitions from the mined traces and synthesize novel orderings. Most aggressive; risks overfitting to the test suite's habits (the binding-table problem, §21 #4), so opt-in. *As built: deterministic (byte-stable) recombination of observed transitions into novel orderings (`[A,B]+[B,C] → [A,B,C]`), appended selector-side as extra seed traces.*

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

## 5. Initial-state mining (a bonus the same extractor yields) — ✅ SHIPPED (Slice 3c)

*As built: the extractor captures `initialStateExpr`, and the selector uses it as the trace's starting State only when it is **self-contained** — no lowercase-leading identifier reference, the marker of a test-body-local binding. So `Feature.State(count: 3)` seeds a real starting state; `Feature.State(items: [a, b])` (fixture-referencing) falls back to the reducer default. Conservative — a false "not self-contained" only costs a mined starting state, never correctness.*

`TestStore(initialState: Feature.State(items: [a, b]))` is a developer-curated *starting state*. v2.0 generates initial states from the State type's memberwise strategist; mined initial states are realistic seeds that bias state generation toward plausible configurations (a non-empty `items`, a selected ID that exists). Same replay-then-extend posture: check from mined seeds first, then generated seeds. Falls directly out of parsing the `TestStore(initialState:)` argument — near-zero marginal cost once the extractor exists.

## 6. Open questions

1. **`send` vs `receive`.** ✅ **RESOLVED as proposed.** `MinedAction.Kind` mines `send` into the user-action corpus and records `receive` separately (unused in v1). A `receive` is an *effect output*, not a user action — replaying it as a user-sent action is wrong.
2. **Argument concreteness.** ✅ **RESOLVED (Slice 3b).** A payload-bearing arg (`.select(a.id)`) references a test-body-local binding the standalone verifier can't reconstruct, so the selector *generalizes* it to `.select(<generated>)` using the same canned literals (`defaultValueLiteral`, labels preserved) the random `.tca` generator already explores — which re-opens the cycle-119 value-generator question *formally* but adds **no new precision risk**, since a canned arg the random path already covers cannot produce a novel false positive. A non-defaultable payload type (`Color`) drops the trace.
3. **Overfitting (the binding-table risk).** ✅ **RESOLVED — enforced as a hard rule.** Slice 2 mined traces only ever *prepend*; random generation stays the coverage floor and is never replaced. Baked into the emitter (mined block precedes the `for sequenceIndex` random loop) and the build plan.
4. **Non-TCA carriers.** ✅ **RESOLVED (Slice 3a).** `ActionAlphabetScanner` resolves the Action enum's cases + labels for *any* carrier (`.tca` / `.elmStyle` / `.generic`; nested `Feature.Action` or top-level `enum AppAction`), so the selection is alphabet-driven, not carrier-gated. (In practice `TestStore` is a TCA construct, so the real applicability stays TCA-centric as predicted — but the mechanism is now carrier-agnostic *and* label-correct, which payload generalization needs.)
5. **Stale traces.** ✅ **RESOLVED — plus a belt-and-suspenders guard.** The host suite is self-validating (if it compiles, the cases are current), *and* `MinedTraceSelector`'s stale-case guard drops any trace referencing a case absent from the candidate's current Action alphabet, so discovery/test drift can't emit an uncompilable literal.

## 7. What this proposal will NOT do

1. **Touch production data.** The whole point is to get §20's empirical-trace value from *scripted tests*, avoiding the privacy/instrumentation cost of real user logs. Production-log mining stays deferred.
2. **Replace random generation.** Mined traces *augment* the corpus; they never become the sole source (§6 #3). Random generation remains the coverage floor.
3. **Integrate with TCA `TestStore` as a verify backend.** That's a separate §20 direction ("TCA TestStore integration" — verify *via* TestStore). This proposal *reads* TestStore tests as a data source; it does not *run* through TestStore. Distinct projects.
4. **Auto-apply.** Opt-in, human-reviewed, suggestion-only — same as all of v2.0.
