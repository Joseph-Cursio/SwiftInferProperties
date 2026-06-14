# Calibration cycle 109 — fix Blocker A (nested State/Action pre-qualification)

> **STATUS: SHIPPED (v1.116.0).** Fixes cycle-108 Blocker A: the
> interaction verifier stub failed to compile (`cannot find 'State' in
> scope`) for the universal nested-`State`/`Action` reducer shape. The
> discoverer now pre-qualifies a bare nested param type to
> `<Enclosing>.State`, so the synthesized verifier compiles. Confirmed
> end-to-end on a standalone reducer. **Blocker B (verifier links
> `Testing.framework`) is unchanged** — measured evidence still can't run
> until B is resolved, so idempotence stays `.likely`. Captured 2026-06-14.

## The fix

**Root cause (recap).** `ActionSequenceStubEmitter` /
`InteractionTraceEmitter` construct `State()` / `Action.self` from the
candidate's stored `stateTypeName` / `actionTypeName` verbatim. M1.B's TCA
walker already pre-qualifies these to `Feature.State` (so the emitters
produce a resolvable `Feature.State()`), but **M1.A's signature scan stored
the bare `"State"`** — which fails to resolve in the verifier (it imports
the user module, not the reducer type).

**Fix — at the discoverer, not the emitter.** Distinguishing a *nested*
`State` from a *top-level* `AppState` referenced by bare name needs
syntactic context only the discoverer has. `ReducerDiscoveryVisitor` now
tracks, parallel to `typeStack`, the set of directly-nested type names per
enclosing type (`nestedTypeNamesStack`). `matchReducer` pre-qualifies a
param type via `qualifyIfNested(_:enclosing:nested:)` **only when** the
bare name is in the enclosing type's nested-type set — so:

- `struct Feature { struct State; enum Action; func reduce… }` →
  `stateTypeName = "Feature.State"` (was `"State"`). ✓ compiles.
- A method over a *top-level* `AppState` → stays `"AppState"` (not
  mis-qualified to `Logic.AppState`). ✓
- Free-function reducers (no enclosing type) → stays bare. ✓
- M1.B TCA candidates (already dotted) → untouched (no double-qualify). ✓

Fixing at the source means **both** emitters (`ActionSequenceStubEmitter`
and `InteractionTraceEmitter`, which had the identical bare-name bug) are
fixed at once, the witness detectors keep working (they consume the
`stateQualifiedName`/`actionQualifiedName` computed properties, which now
no-op on the already-dotted stored value), and the display/bridge paths
just show the more precise qualified name (already true for TCA).

## Verification

- **End-to-end:** on a standalone `struct Demo { struct State; enum
  Action; static func reduce… }`, `verify-interaction` now emits
  `var state = Demo.State()` / `Demo.Action.self` and the synthesized
  workdir **builds clean** — the `cannot find 'State'` errors are gone.
  (Execution then hits Blocker B; see below.)
- **Regression tests:** `ReducerDiscovererNestedTypeTests` (4 cases) —
  nested → qualified, inout-nested → qualified, top-level → bare,
  free-function → bare. Existing discoverer tests unchanged (their
  fixtures reference non-nested types, so they correctly stay bare).
- **Full suite:** 3161 tests / 420 suites green (4 perf-budget timing
  flakes only). SwiftLint clean.

## Refactor (mechanical, no behavior change)

The fix pushed `ReducerDiscoverer.swift` past SwiftLint's 400-line
`file_length` cap (it was at 399). To stay silent:

- The two stateless helpers (`nestedTypeNames`, `qualifyIfNested`) moved to
  `ReducerDiscoverer+ShapeHelpers.swift`.
- The visitor's TCA-conformance walk moved to a new
  `ReducerDiscoverer+TCAWalk.swift`. This required the visitor to become
  `internal`, which collided with a same-named `private Visitor` in
  `ReducerPurityAnalyzer.swift`, so it was renamed
  `Visitor → ReducerDiscoveryVisitor`. Pure relocation.

## Blocker B is still open (measured evidence still blocked)

Cycle 109 unblocks the *build* leg only. The verifier executable still
transitively links `@rpath/Testing.framework` via kit 2.5.0's
PropertyLawKit/PropertyBased and fails at launch (a plain `@main`
executable can't host swift-testing), which the outcome parser
misclassifies as a reducer trap (`measuredDefaultFails`). Until B is
resolved, the A1 `.likely → .strong` campaign cannot run on empirical
evidence. **Idempotence remains `.likely` (no promotion this cycle.)**

## What's next

| Item | Notes |
|---|---|
| **Blocker B** — verifier ✗ swift-testing linkage | Design call, likely kit-side (a verifier-facing product without swift-testing) or build the verifier as a test bundle. The gating item for A1. |
| Parser hardening — dyld launch failure ≠ reducer trap | Bundle with B; a launch failure must not read as `measuredDefaultFails`. |
| Resume `.likely → .strong` (A1) | Only once B lands and measured `.measuredBothPass` is obtainable. |
