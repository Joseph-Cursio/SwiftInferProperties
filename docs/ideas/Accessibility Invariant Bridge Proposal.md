# Accessibility Invariant Bridge Proposal

**Status:** Draft / proposal — exploratory; likely a *companion project*, not an in-repo milestone (see §7).
**Target:** A ViewInspector-backed bridge between SwiftInferProperties' interaction-invariant verify and rendered-view state. Cross-pollinates with SwiftProjectLint (sibling repo) for the static half.
**Date:** 2026-06-07
**Relates to:** PRD v2.0 §1 (Family 8 — Accessibility, "Out of scope (not PBT)"), §20 ("View-introspection bridges. ViewInspector integration … probably a separate companion project").

## 1. Summary

Family 8 (Accessibility — "all controls labeled; focus reachable") was set aside in the v2.0 taxonomy as "out of scope (not PBT)" because it's not temporal-logic-shaped and, more practically, because the other seven families are predicates over *reducer state* while accessibility is a predicate over *rendered view state*. This proposal reframes a useful subset of accessibility as a genuine property — `∀ reachable state, render(state) has no unlabeled control` — and verifies it by composing two pieces you **already own**: SwiftInferProperties' action-sequence engine (to reach states) and a ViewInspector pass (to inspect the rendered tree at each state). The static, no-render half overlaps SwiftProjectLint's existing accessibility rules directly.

The honest framing (§7): this is the *most speculative* of the four ideas and probably belongs in a separate companion project, exactly as §20 predicted. It's included because the cross-repo leverage — three of your projects pointing at one property — is unusually high.

## 2. Motivation

### 2.1 Accessibility *is* a property — over the right state

"All controls have an accessibility label" reads like a lint rule, and statically it is one (SwiftProjectLint already ships `Control Missing Accessibility Label`, committed `a74a671`). But the static rule can only see the *literal* `Button("…")` in source. It cannot see the button that appears only after `add(item); beginCheckout()` puts the model into a state where a conditionally-rendered, dynamically-labeled control exists. That control's label might be empty *for some reachable states and not others* — e.g. `Button(viewModel.actionTitle)` where `actionTitle` is `""` until a field is filled.

That's a property, not a lint: `∀ s ∈ reachableStates, ∀ control ∈ render(s), control.label ≠ ""`. It has a finite counterexample (a state + the offending control), which is what makes it *safety-shaped* and checkable — unlike the genuinely-temporal Family 7. The v2.0 LTL appendix lists Family 8 as "not temporal-logic-shaped"; this proposal's point is that the *label-existence* slice of accessibility is `G(rendered ⇒ labeled)`, a safety property after all, even though *focus-order* accessibility is not.

### 2.2 The two halves, and who already owns them

| Half | What it checks | Already exists where |
|---|---|---|
| **Static** | Literal controls in source have labels | **SwiftProjectLint** — `Control Missing Accessibility Label` rule, SwiftSyntax-based |
| **Dynamic** | Controls in *rendered* trees, across reachable states, have labels | Nowhere — this proposal |

The dynamic half needs (a) a way to reach states — **SwiftInferProperties' action-sequence engine**, already built — and (b) a way to inspect a rendered SwiftUI tree — **ViewInspector**, which SwiftProjectLint already uses for its own tests (per its CLAUDE.md). Every component exists; nothing connects them.

## 3. Design sketch

### 3.1 The checkable property

For a view `V` driven by a discovered carrier (reducer or `@Observable` model — see the companion @Observable proposal):

```
forAll actions: [Action]
    let state = fold(reduce, initialState, actions)
    let tree  = ViewInspector.inspect(V(state))
    for control in tree.findAll(interactiveControls) {
        require control.accessibilityLabel != "" || control.accessibilityHidden
    }
```

The action-sequence engine supplies `actions`; ViewInspector supplies `inspect` and `findAll`. The invariant is per-control label-presence (and the accessibility-hidden escape hatch, which is a legitimate label-free case).

### 3.2 Why this rides the existing verify path

Reaching `state` is exactly what the subprocess verify harness does today for effect-bearing reducers: build a test, fold an action sequence, observe. The only new step is "render and inspect" instead of "compare projected state." It is a new *property body*, not a new harness — the action-sequence generation, shrinking (minimal failing action sequence → the shortest path to an unlabeled control), and five-category outcome scheme all apply unchanged.

### 3.3 Checkable accessibility slices (and the ones that stay out)

| Accessibility concern | Shape | In scope here? |
|---|---|---|
| Control has a non-empty label | `G(rendered ⇒ labeled)` safety | **Yes** — finite counterexample |
| Control has an accessibility *trait* matching its role | safety | Yes (extension) |
| Image/icon-only buttons labeled | safety | Yes |
| Dynamic Type doesn't truncate/clip | safety-ish, needs layout | Maybe — needs rendered geometry, harder |
| Focus order is sensible / element reachable by keyboard | *ordering / liveness* | **No** — not safety-shaped, genuinely the Family-7-adjacent hard case |
| Contrast ratio | needs pixel render | No — out of ViewInspector's reach |

The proposal scopes to the top block (label/trait presence across reachable states). Focus-order and contrast stay out for the same reason temporal families do — different, more expensive tooling.

## 4. Cross-repo leverage (why this is interesting despite being speculative)

Three of your projects converge on one property:

- **SwiftProjectLint** owns the *static* check and the ViewInspector know-how.
- **SwiftInferProperties** owns *state reachability* (action-sequence generation + verify).
- **SwiftPropertyLaws** owns the *law-verification grading* (`.verified` tier, evidence persistence) that a passing dynamic check would record.

A dynamic accessibility check is the natural seam where all three meet: SwiftProjectLint's static rule becomes the cheap first pass, SwiftInferProperties' engine reaches the states the static pass can't see, and a clean run promotes to SwiftPropertyLaws' `.verified` tier. None of the three alone can make the claim "every control is labeled in every reachable state"; together they can.

## 5. Why it's gated behind @Observable / TestStore work

This proposal *consumes* state reachability over a view's carrier. It is most valuable for `@Observable` view-models (where the view-to-state binding is direct) — so it naturally sequences **after** the @Observable Carrier proposal lands. For pure TCA, the view is a function of `Store<State>` and reachability already works, but the rendering step needs a `ViewStore`/`Store` test double. Either way, this is downstream of the carrier work, not parallel to it.

## 6. Open questions

1. **ViewInspector's rendering fidelity.** ViewInspector inspects the *view tree structure*, not a true render — it does not run layout or the real accessibility engine. So it can see `.accessibilityLabel("")` modifiers and `Button` titles, but cannot see a label injected by the system or computed at true render time. The check is therefore "structurally labeled," a useful-but-partial proxy for "accessible." Be explicit about that ceiling in every suggestion (explainability is first-class — PRD §4.5).
2. **State → View binding discovery.** The tool must know *which view* a carrier drives to render it. For TCA there's a `Store`/`ViewStore` convention; for `@Observable`, a `let model: Model` property on the view. Inferring the binding is its own small discovery problem.
3. **Non-determinism.** If a view's body branches on something other than the carrier state (environment, dates), the same state renders different trees. Restrict to state-deterministic views; flag and skip the rest.
4. **Companion-project boundary.** §20 already calls ViewInspector integration "probably a separate companion project." Mixing a UIKit/SwiftUI-rendering test dependency into SwiftInferProperties' currently render-free, pure-AST-and-subprocess pipeline is a real architectural cost. The honest call is likely: build it as a thin companion that *depends on* SwiftInferProperties (for reachability) and *borrows from* SwiftProjectLint (for the inspection rules), rather than landing it inside either.

## 7. Recommendation / status

Of the four ideas drafted in this round, this is the **most speculative and the least self-contained** — it depends on @Observable carrier support, pulls in a rendering test dependency, and ViewInspector's structural-only fidelity caps how strong the claim can be. It is included for the cross-repo leverage (§4), which is genuinely unusual.

Suggested posture: **do not** build this until the @Observable Carrier and TestStore Trace Mining work has shipped and proven the reachability engine on view-driving carriers. At that point, prototype it as a **separate companion repo** (`SwiftInferAccessibility` or similar) that composes the three existing projects, keeping SwiftInferProperties' core render-free. Revisit this doc then.

## 8. What this proposal will NOT do

1. **Replace SwiftProjectLint's static rule.** The static pass is cheaper and catches the literal cases; this is the dynamic complement, not a replacement.
2. **Claim full accessibility coverage.** Label/trait presence is a slice. Focus order, contrast, VoiceOver navigation, and Dynamic Type layout are explicitly out (§3.3).
3. **Render pixels or run the real accessibility engine.** ViewInspector inspects structure; the check is "structurally labeled," and every suggestion says so (§6 #1).
4. **Live inside the core pipeline.** Companion project, depending on the core — not a new dependency in SwiftInferProperties itself (§6 #4).
