# Calibration cycle 122 — `.tca` carrier epic, Phase A spike (verify a real TCA reducer)

> **STATUS: SHIPPED (v1.126.0).** A throwaway spike drove a real internal
> `@Reducer` + `@ObservableState` reducer (the exact `tca-25-discovery`
> shape) to `measured-bothPass` by hand — proving the five scoped blockers
> clearable and surfacing three the static scope missed — and Phase A was
> then wired into the production pipeline in four commits + a capstone
> `.subprocess` test (`TCACarrierMeasuredTests`, ~75s). `verify-interaction`
> now builds + runs a real payload-free TCA `@Reducer` end-to-end. Captured
> 2026-06-14.
>
> **Wiring summary:** (1) discovery captures `ReducerCandidate.actionCaseNames`
> (payload-free, withheld if any payload case); (2) the emitter's `.tca` path
> (CA import, explicit-case generator, instance-relative invocation);
> (3) `VerifierWorkdir.interactionTCA` (CA dep + direct source inclusion,
> stub → `Verifier.swift`); (4) the capstone test. Blocker #6
> (Testing.framework) needed no code — cycle-110's `DYLD_FRAMEWORK_PATH`
> injection already covers it. Suite green (3203).

## Why a spike first

The `.tca` carrier epic is the genuine remaining lever on the frozen 50.5%
(cycle 121: 58 `.tca` reducers currently unmeasurable). It is multi-blocker
and macro-heavy, so the responsible first move was a de-risking spike: get
*one* real `@Reducer` to `measured-bothPass` by hand, learn what actually
breaks, before touching the production emitter.

## The spike

A standalone SwiftPM executable (`/tmp/tca-spike`, throwaway) with:

- **`Counter.swift`** — a real-shaped TCA reducer: `internal` (not public),
  `@Reducer` + `@ObservableState`, a payload-free `enum Action` that does
  **not** declare `CaseIterable`, an idempotent witness `case closeMenu`
  (`menuOpen = false`), and the usual `var body: some Reducer { Reduce { … } }`.
- **`Verifier.swift`** — a hand-written stub mirroring the emitter's shape
  with the `.tca` changes (below), co-compiled with `Counter.swift` in one
  executable target.
- **`Package.swift`** — depends on swift-property-based, SwiftPropertyLaws
  (PropertyLawKit, via local path), and **swift-composable-architecture**
  (`from: 1.15.0`).

Result, on `swift build` + run with the framework path set:

```
INTERACTION-VERIFY-OUTCOME: bothPass totalRuns=1024 clean=1024
```

## The five scoped blockers — all clearable (validated)

1. **`.tca` instance invocation.** `let r = Counter(); _ = r.reduce(into:
   &state, action: action)` compiles and runs. The discoverer already
   captures everything needed (`enclosingTypeName` = `Counter`, qualified
   `Counter.State`/`Counter.Action`, shape `.inoutStateActionReturnsEffect`).
2. **CA import + verifier dependency.** Adding swift-composable-architecture
   to the verifier package + `import ComposableArchitecture` in the stub
   resolves `Reduce`/`Effect`/`reduce(into:action:)`.
3. **Corpus declares CA** — the CorpusPackager `dependencies:` thread
   (cycle 121); moot under the direct-source-inclusion path (below).
4. **Non-`CaseIterable` Action enumeration.** The explicit-case generator
   `Gen.element(of: [Counter.Action.increment, .decrement, .closeMenu]).map { $0! }`
   works. (`Gen.element(of:)` yields an *Optional* element generator —
   `Generator<Action?, _>` — so an unwrap-map back to the bare `Action` is
   required; guard the case list non-empty.)
5. **Internal-type visibility.** Direct source inclusion — compiling the
   corpus `.swift` *into* the verifier target — makes the `internal` reducer
   visible with no `import`/`@testable`. This is the cleaner of the two
   options scoped (no `-enable-testing`-on-dependency fragility).

**Bonus positive:** `@ObservableState`'s synthesized `Equatable` compared
correctly — the worry that its `_$id` mutation token would spuriously break
the idempotence `==` did **not** materialize for value-equal states. (Watch
item: an idempotent witness that calls `withMutation` on every apply even
when the value is unchanged could still bump `_$id`; not observed here.)

## Three NEW blockers the spike surfaced

6. **`Testing.framework` runtime linking — the silent killer.** TCA
   transitively links swift-testing (via issue-reporting), so the verifier
   binary **dyld-aborts** (`exit 134`, `Library not loaded:
   @rpath/Testing.framework`) on a plain run — the reduce logic never
   executes. Fix: run with
   `DYLD_FRAMEWORK_PATH=/Applications/Xcode.app/Contents/SharedFrameworks`
   (where `Testing.framework` lives; also the platform Frameworks dir).
   **`VerifierSubprocess.runVerifierBinary` must inject this env for the TCA
   mode.** A naive implementation that only fixed compilation would have
   produced a confusing `.measuredDefaultFails`/exit-134 with no logic ever
   running.
7. **`@main` ⊕ `main.swift` filename conflict.** With corpus sources
   co-compiled into the target, the stub cannot be named `main.swift`
   (`'main' attribute cannot be used in a module that contains top-level
   code`). The stub file needs a non-`main` name (e.g. `Verifier.swift`) or
   `-parse-as-library`.
8. **`reduce(into:action:)` deprecation warnings.** TCA marks direct
   reducer invocation deprecated ("Reducers are processed by the store").
   Functional but noisy; cosmetic — optionally silenced.

Plus: TCA pulls swift-syntax (macros) → heavy cold builds, so cycle-120's
reducer-grouped warm-`.build/` reuse matters even more for a TCA survey.

## Architecture decision: direct source inclusion

The current verify path references the corpus as a SwiftPM **path
dependency** (a library product). For real TCA reducers that fails on
visibility (blocker 5: everything is `internal`). The spike validated
**direct source inclusion** instead — co-compile the corpus `.swift` into
the verifier's own target. This:

- solves visibility (internal types become in-module);
- makes CorpusPackager's package/product machinery unnecessary for this
  path (the verifier just needs the corpus's *external* deps, e.g. CA);
- diverges from today's path-dependency model — so the wiring adds a TCA
  mode rather than reworking the existing generic/algebraic path.

## Wiring plan (Phase A, this cycle continues)

1. **Emitter** — lift the `.tca` `validate` rejection; emit instance setup
   (`let reducer = <Type>()`) + the `.tca` apply/idempotence forms
   (`reducer.reduce(into:&s, action:)`); conditional `import
   ComposableArchitecture`; explicit-case generator from a captured Action
   case list; non-`main` stub filename.
2. **Candidate** — thread the Action enum's payload-free case names onto
   `ReducerCandidate` (shares the capture work with the shelved cycle-119
   value-gen path).
3. **VerifierWorkdir** — a TCA mode (CA `.package`/`.product`) +
   direct-source-inclusion of the corpus sources.
4. **Subprocess runner** — inject `DYLD_FRAMEWORK_PATH` for the TCA mode.
5. **Proof** — a `.subprocess` test driving a real `Counter`-shaped reducer
   to `measured-bothPass`, mirroring this spike.

## What's next after Phase A

Phase B (payload-bearing TCA actions → un-shelve cycle-119 value-gen) and
Phase C (corpus-scale survey over real `tca-10`/`tca-25` via cycle-120's
parallel survey), each evidence-gated. The decisive Phase-A data point to
collect: of the 58 `.tca` reducers, how many are Counter-shaped
(payload-free Action, zero-arg `Equatable` State) and thus reachable by
Phase A alone.
</content>
