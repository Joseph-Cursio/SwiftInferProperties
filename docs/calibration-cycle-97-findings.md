# v1.100 Calibration Cycle 97 — Findings (kit v2.5.0 macro)

Captured: 2026-05-17. swift-infer at v1.100 / SwiftPropertyLaws at v2.5.0.

## Headline

**Fourth cross-repo cycle ships — closes the InteractionInvariant
arc.** After v2.3.0 protocols (cycle 83) + v2.4.0 runtime
harnesses (cycle 96), kit v2.5.0 adds the
`@InteractionInvariantTests` peer macro for auto-generation. Repo
v1.100 bumps the kit pin from v2.4.0 → v2.5.0 and adds a smoke
test confirming the macro expands + the auto-generated test runs
end-to-end.

**The full chain is now wired**: user writes a conformer stub +
`@InteractionInvariantTests` → kit macro emits a peer suite →
emitted test calls the v2.4.0 harness → harness drives the
reducer via v2.2.0 ActionSequenceFactory → CI surfaces violations
on every `swift test`.

**No corpus delta** — cross-repo plumbing cycle, not a detector
change. Cycle-7 baseline (92 reducers, 76 interactions) carries
forward.

After v1.100, the three sibling threads queued since v1.88 are
all closed. The only remaining surface is the calibration loop
proper.

## What landed

### Kit side (v2.4.0 → v2.5.0)

New `@InteractionInvariantTests` peer macro:

- **Declaration** in `Sources/PropertyLawMacro/PropertyLawMacro.swift`
  alongside the existing `@PropertyLawSuite` + `@Discoverable`.
- **Implementation** in
  `Sources/PropertyLawMacroImpl/InteractionInvariantTestsMacro.swift`.
- **Family detection**: reads the decoratee's inheritance clause
  for `CardinalityInvariant` / `ReferentialIntegrityInvariant` /
  `BiconditionalInvariant` / `ConservationInvariant` /
  `ActionIdempotenceInvariant` / `InteractionInvariant` (root).
  **Arm order matters** — `ActionIdempotenceInvariant` is checked
  first because it refines the root and would also satisfy the
  bare-root arm; matching it first routes to the correct
  (action-applicative) harness, not the state-predicate one.
- **Emit shape**: a peer `<TypeName>InteractionInvariantTests`
  `@Suite` struct with one `@Test func` that calls the
  appropriate v2.4.0 harness against `Self.initialState` +
  `Self.reducer`.

User contract — conformer must define
`static var initialState: State` and
`static var reducer: @Sendable (State, Action) -> State`. Missing
members surface as clear compile errors from the emitted test
code (PRD §5.7's "compile error beats silent fallthrough", same
posture as `@PropertyLawSuite`'s "missing `gen()`").

7 kit-side macro tests in
`Tests/PropertyLawMacroTests/InteractionInvariantTestsMacroTests.swift`
covering all 5 families + the combined-conformance arm-order case
+ the no-family-conformance diagnostic.

New `noInteractionInvariantConformance` diagnostic case (warning
severity, matches `noKnownConformance` posture).

Plugin entry registered in `Plugin.swift` alongside
`PropertyLawSuiteMacro` + `DiscoverableMacro`.

### Repo side (v1.99.0 → v1.100.0)

- **Pin bump**: `Package.swift` from `from: "2.4.0"` →
  `from: "2.5.0"`.
- **Test target deps**: `SwiftInferCLITests` gains a
  `PropertyLawMacro` product dependency so the smoke test can
  import the macro module.
- **Smoke test**: 1 test in new
  `Tests/SwiftInferCLITests/KitV25InteractionInvariantTestsMacroSmokeTests.swift`.
  The test fixture is a `SmokeMacroCardinality` conformer
  attached to `@InteractionInvariantTests`. The auto-generated
  `SmokeMacroCardinalityInteractionInvariantTests` suite is
  discovered + run by `swift test` automatically.

**End-to-end validation** (confirmed via `swift test --filter
cardinalityInvariant_SmokeMacroCardinality`): the macro expands,
the emitted test compiles, the test runs the v2.4.0 harness, the
harness samples action sequences via v2.2.0
ActionSequenceFactory + checks the invariant after each step.

## Cross-repo cycle inventory (updated)

| Cycle | Repo ver | Kit ver | What landed |
|---|---|---|---|
| 73 (M2)  | v1.76 | v2.2.0 | ActionSequenceFactory + StatefulGuard |
| 83 (M9)  | v1.86 | v2.3.0 | InteractionInvariant protocol family |
| 96 (M9.harness)  | v1.99 | v2.4.0 | check*InteractionInvariant*PropertyLaws harnesses |
| **97 (M9.macro)** | **v1.100** | **v2.5.0** | **`@InteractionInvariantTests` peer macro (auto-gen)** |

Four cross-repo cycles in total. The InteractionInvariant arc is
complete: protocols + runtime harness + auto-generation. The
SwiftInferProperties consumer surface is fully wired —
`accept-interaction` records a decision → user writes a
conformer stub + `@InteractionInvariantTests` → CI verification
is continuous.

## What's next

After v1.100, the cycle-87 + post-detector-arc queues are both
empty. The remaining active surface is:

1. **Calibration loop proper** — three cycles of stable per-
   family acceptance rate against the cycle-7 baseline (76
   suggestions across 92 reducers). Now that the runtime harness
   + macro auto-generation both ship, the loop can use **runtime
   law violations** (from macro-emitted CI tests) as a signal
   beyond static detection rate. Workflow:
   - `swift-infer discover-interaction --interactive` to record
     decisions on the 76 cycle-7 suggestions.
   - User writes conformer stubs + `@InteractionInvariantTests`
     for accepted invariants.
   - CI runs `swift test` — runtime violations surface as test
     failures, classified by family.
   - Three cycles of stable per-family pass-rate → tier
     promotion from default-`.possible` to `.likely`.

2. **Bridge-level N-arm peer triage** (still queued from
   cycle-95) — PRD §9.4's `[A/B/B'/B''/.../s/n/?]` for M9
   bridge-level peer proposals. Lower priority than the
   calibration loop; could be picked up later if the per-
   suggestion form proves insufficient in practice.

3. **Real-world TCA dogfooding** — applying the full chain to a
   non-corpus TCA codebase (someone else's project, ideally)
   would surface the cross-cutting ergonomic issues that
   synthetic corpora don't.

## Notes on the version-number jump (v1.99 → v1.100)

This is a SemVer minor-version increment, not a major bump. The
v2.0 designator in PRD references is **the project arc name**
(v2.0 = interaction-invariant inference for SwiftUI state
systems), not the CLI version. CLI version stays in the v1.x
band until a major API break — which the v2.0 work hasn't
required (every cycle has been additive). SwiftPM handles
multi-digit minor versions cleanly (`1.100.0 > 1.99.0` by
numeric comparison, not string).
