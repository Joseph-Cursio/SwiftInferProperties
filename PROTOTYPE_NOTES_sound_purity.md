# SoundPurity (Idea #4, step 2)

Status: **wired and validated.** The swift-syntax skew that blocked this leg
has been resolved.

## What this branch contains

- `Sources/SwiftInferCore/SoundPurity.swift` — composes SIP's
  `ReducerPurityAnalyzer` with `SwiftEffectInference.PurityInferrer` (the
  canonical purity oracle, relocated into the shared leaf). `.pure` is claimed
  only when **both** refutation analyzers agree — the sound mapping. Mapping
  `ReducerPurity.pure → Effect.pure` *alone* is unsound, because
  `ReducerPurityAnalyzer` never inspects I/O / nondeterminism / totality (a
  reducer can be `ReducerPurity.pure` yet still call `print()` / force-unwrap).
- `Tests/SwiftInferCoreTests/SoundPurityTests.swift` — 6 tests. The headline
  case (`reducerPureButLogs_isRefuted`) proves the meet: `ReducerPurity` returns
  `.pure`, but `SoundPurity` refutes because `PurityInferrer` catches the
  `print`.
- `Package.swift` — adds the SEI dependency to `SwiftInferCore` and pins
  swift-syntax `exact: "602.0.0"`.

## How the blocker was resolved

SIP pinned swift-syntax transitively through SwiftPropertyLaws (capped at the
600 line), while SEI is on 602. Fixed by **SwiftPropertyLaws v3.1.0** — a clean
swift-syntax 600 → 602 bump (no API breakage; 574 tests green). SIP's
`from: "3.0.0"` requirement picks up 3.1.0 automatically, and the dependency
graph now resolves on swift-syntax 602 across SEI, SwiftProjectLint,
SwiftPropertyLaws, and SwiftInferProperties.

## Known follow-up (precision, not a blocker)

The canonical `PurityInferrer` refutes I/O, the randomness family, and
partiality, but its marker set does **not** yet include clock/UUID
nondeterminism (`Date()`, `UUID()`). In SwiftProjectLint those were caught by a
*separate* `NonInjectedNondeterminism` rule. For `Effect.pure` to fully imply
determinism, those markers should move into the shared oracle — a precision
improvement worth doing before SIP emits `pure` suggestions in anger.

## Remaining wiring (not done here)

`SoundPurity` is built and tested but not yet called from SIP's suggestion
path. The final step is: only emit a `/// @lint.effect pure` suggestion when
`SoundPurity.isPure(fn)`.
