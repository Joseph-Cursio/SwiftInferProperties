# Scope: dependency-pinned determinism verify for TCA reducers

## Motivation

A road-test against Point-Free's own TCA examples (41 reducers) surfaced the
gap: **determinism measured-verify reaches zero real reducers.** Every
real-world reducer is `carrier:tca`, and determinism is gated to the
`.redux` family (`DeterminismInteractionTemplate` / `ReducerInteractionAnalyzer`
use `carrierKind.isReduxFamily`, which excludes `.tca`). The witness families
(idempotence, biconditional, cardinality) *do* fire on real TCA — 23
suggestions, incl. a legit `.selectTab` idempotence — but determinism, the
family we built the measured-verify pipeline for, does not.

The `ActionSequenceStubEmitter.makeDeterminismCheck` already has an `isTCA`
branch (`reducer.reduce(into:&s,action:)`), so the *emitter* supports TCA; only
the *production template* gate excludes it.

## The property (why not naive live-dependency determinism)

A bare `reducer.reduce(into:&s, action:)` uses **live** `@Dependency`s (real
clock / uuid / random). Two back-to-back calls that read `\.uuid` get different
values → determinism fails — technically true (un-scoped, the reducer *is*
nondeterministic) but not the useful signal: it just flags "uses a dependency,"
which is expected and correct in TCA.

The idiomatic TCA property is stronger and worth checking:

> With every **declared** dependency pinned to a fixed value,
> `reduce(s, a) == reduce(s, a)`.

Pinning the declared dependencies makes their contribution identical across the
two calls, so any residual difference is **un-declared** nondeterminism — a
reducer sneaking a raw `Date()` / `UUID()` / `Int.random()` / nondeterministic
`Set` iteration into its synchronous state mutation instead of routing it
through `@Dependency`. That is a genuine TCA anti-pattern, and exactly what this
check catches. (Effects are discarded — `_ = reduce(...)` — so this tests the
reducer's pure synchronous logic, not its async work.)

## Design

### The stub (core change)

Restructure `makeDeterminismCheck`'s `isTCA` branch so each of the two
applications runs in its **own** `withDependencies` scope with an *identical*
pinned environment (a shared scope would let a fixed-seed RNG advance between
the two calls and diverge):

```swift
func runOnce() -> State {
    withDependencies {
        $0.date = .constant(Date(timeIntervalSince1970: 0))
        $0.uuid = .constant(UUID(0))
        $0.calendar = Calendar(identifier: .gregorian)
        $0.timeZone = TimeZone(identifier: "UTC")!
        $0.continuousClock = ImmediateClock()
        $0.suspendingClock = ImmediateClock()
        $0.withRandomNumberGenerator = WithRandomNumberGenerator(FixedSeedRNG(seed: 0))
    } operation: {
        var state = detState
        _ = reducer.reduce(into: &state, action: action)
        return state
    }
}
precondition(runOnce() == runOnce(), "Determinism invariant violated")
```

`withDependencies` / `DependencyValues` come from `Dependencies`, re-exported by
`ComposableArchitecture` — already imported and already a workdir dependency
(`VerifierWorkdir` `.interactionTCA` pins `swift-composable-architecture`
from 1.15.0). No new dependency, no new workdir mode.

**Pinned set (open decision — recommend the curated standard set above):** TCA's
built-in nondeterministic dependencies. Custom user `@Dependency`s aren't pinned
— but those are almost always async/effect (discarded), not synchronous state
mutation, so they rarely affect this check.

### The gate

Include `.tca` in the determinism-eligible carriers
(`DeterminismInteractionTemplate.analyze`, `ReducerInteractionAnalyzer`).
Reuse the existing construction gates: Action must have ≥1 constructible case
(else `tcaActionNotEnumerable`), and State must be no-arg constructible.

**State constructibility (open decision):** real TCA States are frequently
all-defaulted (`Counter.State { var count = 0 }`, `Todos.State { … = [] }`) →
`State()` synthesizes. Options: (a) a lightweight heuristic (all stored props
defaulted, or an explicit `init()`) to avoid surfacing un-verifiable Possibles;
(b) surface at Possible regardless and let verify report
`architecturalCoveragePending` via the existing disclosure. Recommend (a) to
keep the Possible stream honest.

### Verify path

`.tca` + `.effectBearing` already routes to subprocess verify (M8) with the
CA-bearing workdir. Determinism rides that unchanged — subprocess builds, slower
but correct.

## Implementation stages

1. **Stub** — restructure `makeDeterminismCheck` `isTCA` to the `runOnce` +
   `withDependencies`-pin form; emit a `FixedSeedRNG` helper into the stub.
   Unit tests on the emitted shape.
2. **Gate** — add `.tca` to `DeterminismInteractionTemplate` /
   `ReducerInteractionAnalyzer`; update the "TCA excluded" tests + the Phase-2
   design note.
3. **Measured e2e** — a TCA corpus with a three-way split proving the thesis:
   - pure TCA reducer (Counter-like) → bothPass → verified;
   - TCA reducer using `@Dependency(\.uuid)` *properly* → pinned → deterministic
     → verified (declared deps are fine);
   - TCA reducer sneaking a raw `Date()` / `Int.random()` into state →
     defaultFails → suppressed (the anti-pattern caught).
4. **Road-test** — re-run `discover-interaction` / `verify-interaction --family
   determinism` against the Point-Free examples; harvest how many real reducers
   now surface + promote.

## Risks / limitations

- **Custom synchronous-nondeterministic dependencies** outside the pinned set →
  possible false `defaultFails`. Low likelihood (deps are usually async/effect);
  disclosed if it happens.
- **Construction ceiling** — the 60% action-payload coverage and non-constructible
  States limit reach; disclosed via `excludedCaseNames` /
  `architecturalCoveragePending`.
- **`withRandomNumberGenerator`** order-dependence handled by the per-call fresh
  RNG (the `runOnce` restructuring).

## Open questions for sign-off

1. Pinned dependency set — the curated standard set above, or narrower/wider?
2. State-constructibility gating — heuristic (recommended) vs. surface-and-disclose?
3. Is the three-way measured corpus (pure / proper-dependency / snuck-raw) the
   right proof shape?
