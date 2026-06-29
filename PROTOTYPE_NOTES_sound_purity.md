# Prototype: SoundPurity (Idea #4, step 2)

Status: **design-complete, build-blocked** on an ecosystem swift-syntax skew.

## What this branch contains

- `Sources/SwiftInferCore/SoundPurity.swift` — composes SIP's
  `ReducerPurityAnalyzer` with `SwiftEffectInference.PurityInferrer` (the
  canonical purity oracle relocated into the shared leaf). `.pure` is claimed
  only when **both** refutation analyzers agree — the sound mapping. Mapping
  `ReducerPurity.pure → Effect.pure` *alone* is unsound, because
  `ReducerPurityAnalyzer` never inspects I/O / nondeterminism / totality (a
  reducer can be `ReducerPurity.pure` yet still call `print()` / `Date()` /
  force-unwrap).
- `Package.swift` — adds the SEI dependency to `SwiftInferCore` and bumps
  swift-syntax to `exact: "602.0.0"` (the version SEI and SwiftProjectLint use).

## The blocker

`swift build` fails to resolve:

```
root depends on 'swiftpropertylaws' 3.0.0..<4.0.0 and
'swifteffectinference' depends on 'swift-syntax' 602.0.0.
'swiftpropertylaws' 3.0.0 depends on 'swift-syntax' 600.0.0..<601.0.0
```

SIP pins swift-syntax transitively through **SwiftPropertyLaws v3.0.0**, which
caps it at the 600 line. SwiftEffectInference (and SwiftProjectLint) are on
602. So the relocation's real blast radius is an **ecosystem-wide swift-syntax
600 → 602 alignment**, gated on a new SwiftPropertyLaws release built against
swift-syntax 602.

## Unblock path

1. Bump `SwiftPropertyLaws` swift-syntax to 602; verify its build/tests under
   the 600 → 602 API changes; cut **v3.0.1** (or v3.1.0).
2. Point SIP at that SwiftPropertyLaws release.
3. Re-resolve; `SoundPurity` then compiles. Add the soundness tests
   (the headline case: a `ReducerPurity.pure` body that calls `print()` must
   return `nil`, proving the meet refutes what `ReducerPurity` alone misses).
4. Wire `SoundPurity` into SIP's suggestion path: only emit a
   `/// @lint.effect pure` suggestion when `SoundPurity.isPure(fn)`.

The SEI leg (canonical `PurityInferrer`, branch `purity-inferrer`) and the
SwiftProjectLint leg (forwarder onto it, branch `purity-inferrer-relocation`)
both build and pass tests today; only this SIP leg is version-gated.
