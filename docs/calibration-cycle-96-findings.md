# v1.99 Calibration Cycle 96 — Findings (kit v2.4.0 harness)

Captured: 2026-05-17. swift-infer at v1.99 / SwiftPropertyLaws at v2.4.0.

## Headline

**Third cross-repo cycle ships — after M2 (v1.76 / kit v2.2.0) and
M9 (v1.86 / kit v2.3.0).** Kit v2.4.0 adds the runtime
`checkInteractionInvariantPropertyLaws` +
`checkActionIdempotenceInvariantPropertyLaws` harnesses for the
v2.3.0 InteractionInvariant protocol family. Repo v1.99 bumps the
kit pin from v2.2.0 → v2.4.0 and adds a smoke test confirming
both harnesses are reachable + functional from the consumer side.

**No corpus delta** — cross-repo plumbing cycle, not a detector
change. Cycle-7 baseline (92 reducers, 76 interactions) carries
forward. The unlock is **CI-grade automatic verification of
interaction-invariant conformances**: a user who accepts a
suggestion via `accept-interaction` (or interactive triage),
writes the conformance stub, and runs `swift test` now gets the
property-based law check on every CI invocation. Previously the
property check lived only inside SwiftInferProperties' M3.E
`verify-interaction` subcommand — useful for one-shot validation
but not for continuous verification.

After v1.99, the cycle-87 sibling-thread queue is empty. The
remaining surface is the PropertyLawMacro discovery integration
(so conforming types emit their `checkXxxLaws(...)` calls
automatically) — a SwiftSyntax-based code-gen layer rather than a
runtime harness, and a separate future cycle.

## What landed

### Kit side (v2.3.0 → v2.4.0)

New `Sources/PropertyLawKit/Public/InteractionInvariantLaws.swift`
with two public free functions:

- `checkInteractionInvariantPropertyLaws(for:initialState:reducer:
  length:statefulGuards:options:)` — state-predicate harness for
  the four refining families. Samples action sequences via the
  v2.2.0 `ActionSequenceFactory.actionSequence(forCaseIterable:
  length:statefulGuards:)`, applies step-by-step to `initialState`
  via the user-provided `@Sendable` reducer closure, checks
  `Invariant.invariantHolds(in:)` after each step. One Strict-tier
  law: `InteractionInvariant.invariantHoldsAfterEachStep`.
- `checkActionIdempotenceInvariantPropertyLaws(...)` — sibling
  harness for the fifth family. Samples a sequence to drive the
  reducer to an arbitrary reachable state, then for each
  `a ∈ Invariant.idempotentActions` asserts
  `reducer(reducer(s, a), a) == reducer(s, a)`. One Strict-tier
  law: `ActionIdempotenceInvariant.doubleApplicationEqualsSingle`.

Both require `Invariant: Sendable` so the `Invariant.Type`
metatype crosses the actor-isolation boundary cleanly (PerLawDriver
runs on the configured backend's actor). Counterexamples report
the action prefix that drove the state to the failing
configuration (state-predicate) or which `idempotentActions`
member failed double-application (action-idempotence).

6 kit-side tests in
`Tests/PropertyLawKitTests/InteractionInvariantLawsTests.swift`:
positive control (invariant always holds), negative control
(faulty reducer surfaces violation), initial-state violation,
ActionIdempotence positive / negative / empty-set degenerate.
Kit full suite: 473 → 479 tests.

### Repo side (v1.98 → v1.99)

- **Pin bump**: `Package.swift` from `from: "2.2.0"` → `from:
  "2.4.0"`. The repo had been pinned at v2.2.0 since cycle 73
  (M2 ship); cycle-86's v2.3.0 protocols + cycle-96's v2.4.0
  harnesses both land in this single bump. Build verifies the
  jump compiles cleanly across two cross-repo cycles' API
  additions.
- **Smoke test**: 2 tests in new
  `Tests/SwiftInferCLITests/KitV24InteractionInvariantLawsSmokeTests.swift`
  exercising both harnesses from the repo side. Local fixtures
  (no `@testable` import of the kit's internals) — confirms the
  public API surface is consumer-complete + the pin bump
  actually wired the new product version through.

## Why a smoke test at the cross-repo boundary

Three reasons:

1. **Catches version-skew at build time, not deferred CI time.**
   Pin bumps occasionally surface latent API-shape mismatches
   (the kit may have added a parameter, renamed a generic
   constraint, etc.). A repo-side smoke test that compiles +
   runs the new API catches these immediately rather than at
   the next consumer's first usage.
2. **Validates the API is consumer-complete.** Kit-side tests
   use `@testable import PropertyLawKit` and can reach
   internals. A repo-side test using only the public API
   confirms the surface is genuinely public + ergonomic for
   real consumers.
3. **Provides a reference for the M9 Bridge writeout's stub
   shape.** When M9's RefactorBridge proposes a conformer stub,
   the user needs an example test that exercises it. The smoke
   test serves as that reference; the writeout can quote it
   directly in the bridge-emitted `// Example invocation:`
   block (future cycle).

## What's next

The cycle-87 sibling-thread queue is empty after v1.99. The
remaining surface from CLAUDE.md's earlier queue:

1. **PropertyLawMacro discovery integration** — a SwiftSyntax-
   based code-gen layer that auto-discovers `InteractionInvariant`
   conformers in the test target and emits `checkXxxLaws(...)`
   calls. Different shape from a runtime harness; the kit's
   existing `PropertyLawMacro` target is the natural home.
   When this ships, conforming types fire law checks on every
   `swift test` invocation automatically — no manual wiring.

2. **Bridge-level N-arm peer triage** (deferred from v1.98
   cycle-95) — PRD §9.4's `[A/B/B'/B''/.../s/n/?]` for M9's
   bridge-level peer proposals. v1.98 shipped the per-suggestion
   form; bridge-level would reuse the `readChoice` arm-driver
   shape.

Plus the calibration loop proper — three cycles of stable per-
family acceptance rate against the cycle-7 baseline (76
suggestions). Now that the kit harness ships, the calibration
loop can use *runtime* law violations as an additional signal
beyond the static detection rate.

## Cross-repo cycle inventory

This is the third cross-repo cycle of the v2.0 arc:

| Cycle | Repo ver | Kit ver | What landed |
|---|---|---|---|
| 73 (M2)  | v1.76 | v2.2.0 | ActionSequenceFactory + StatefulGuard |
| 83 (M9)  | v1.86 | v2.3.0 | InteractionInvariant protocol family |
| 96 (M9.harness) | v1.99 | v2.4.0 | checkInteractionInvariantPropertyLaws harnesses |

Each cross-repo cycle bumps the kit + repo together; the repo's
Package.swift pin always tracks the kit's `from:` version. The
PropertyLawMacro discovery integration is queued as the fourth.
