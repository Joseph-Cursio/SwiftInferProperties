# v1.31 Calibration Cycle 28 — Findings (Design-Completion Phase)

Captured: 2026-05-11. swift-infer at v1.31 development tip (`b13a8b1`). The twenty-eighth execution of PRD §17.3's empirical-tuning loop and the **first design-completion cycle** (post-§19-achievement, post-v1.30).

## Headline

**13-cycle carry-forward closed: FP approximate-equality template arm shipped.** First cycle of the PRD §20 v1.1+ design-completion phase. **No acceptance-rate re-measurement** — v1.31 is correctness-emission work that doesn't shift the inference rate (CM round-trips already accept 8/8 across cycles 25 + 27). The cycle delivers emission correctness for the canonical-accept patterns the calibration loop validated.

| Metric | Cycle 27 (post-v1.30) | Cycle 28 (post-v1.31) | Δ |
|---|---:|---:|---|
| Surface | 109 | 109 | 0 (no inference changes) |
| Acceptance rate | 72.4% | 72.4% (carry; no re-measurement) | 0pp |
| Mechanism classes shipped | 15 | **16** | +1 (class 16 = emit-time equality-form dispatch) |
| Test count | 1923 | **1959** | +36 |

## What v1.31 ships

Three independently-mergeable workstreams:

- **V1.31.A**: `FloatingPointEquatableTypes` curated set + detector in `SwiftInferCore`. Mirrors the `MathForwardFunctions`/`IdentityOperatorAlgebra` curated-set pattern. Covers stdlib `Real` types (Double/Float/Float16/Float80/CGFloat) and swift-numerics `Complex` variants (bare + qualified). Generic-parameter stripping at lookup time. 17 unit tests.
- **V1.31.B**: `EqualityKind` enum + approximate-equality emit on `LiftedTestEmitter.roundTrip`/`idempotent`/`inversePair`. Optional parameter; default `.strict` preserves all current behavior bit-for-bit. 10 unit tests + all 35 pre-existing emitter tests pass.
- **V1.31.C**: Dispatch wiring in `InteractiveTriage+Accept` (3 sites) + `CheckPropertyMacro` (2 sites). Suggestion carrier type → `EqualityKind` via the V1.31.A detector. 9 unit tests verifying the dispatch table.

## Mechanism-class taxonomy

15 → **16** classes. **Class 16 = emit-time equality-form dispatch** — the first emit-side mechanism class in the loop's history. All prior 15 classes are inference-time (signal arithmetic at suggestion-construction); class 16 sits at suggestion-acceptance (test-stub generation) and consults the suggestion's carrier-type metadata via a new SwiftInferCore curated set.

## End-to-end behavior change

A future `exp/log` Complex round-trip pair accepted via `swift-infer discover --interactive` will now emit:

```swift
@Test func exp_log_roundTrip() async {
    let backend = SwiftPropertyBasedBackend()
    let seed = Seed(stateA: ..., stateB: ..., stateC: ..., stateD: ...)
    let result = await backend.check(
        trials: 100,
        seed: seed,
        sample: { rng in (ComplexGenerator).run(&rng) },
        property: { value in log(exp(value)).isApproximatelyEqual(to: value) }
    )
    if case let .failed(_, _, input, error) = result {
        Issue.record("exp/log round-trip failed at input \\(input). \\(error?.message ?? \\"\\")")
    }
}
```

Previously the property was `log(exp(value)) == value`, which fails under IEEE 754 rounding even on canonical inverse pairs. The new form uses swift-numerics' `AlgebraicField.isApproximatelyEqual(to:)` method (available on `Real` and `Complex<Real>`), with the protocol's default tolerance.

## Backward compatibility

- All `LiftedTestEmitter` API additions are **optional parameters defaulting to `.strict`** — call sites that don't update compile unchanged and emit identical output.
- All 35 pre-existing emitter tests pass without modification.
- All 1950 pre-existing tests in the full suite pass without modification.
- The `EqualityKind.strict` path emits byte-for-byte the same output as before v1.31.

## Scope boundaries observed

- **In scope**: round-trip, idempotent, inverse-pair (the three unary-property emit arms; round-trip is the primary motivation).
- **Out of scope this cycle**: commutativity, associativity, monotonicity, identity-element, dual-style-consistency. FP `_relaxedAdd/_relaxedMul` are commutative bit-for-bit; monotonicity uses `<=` which is exact; the form-mutating dual-style assertions check `var copy` equality which is exact for value-semantic carriers. These arms don't need FP equality.
- **Out of scope this cycle**: Counter-example regression emitters in `LiftedTestEmitter+Regression.swift` (different shape: concrete value, not generator-driven).
- **Out of scope this cycle**: Module imports in emitted test files. The emitted property test must have `import Numerics` available; this requirement is documented in the `EqualityKind` doccomment.

## Cycle-29 priorities

The post-v1.0 calibration era has closed; the project enters the steady-state PRD §20 v1.1+ design-completion phase:

1. **`swift-infer apply` (PRD §20.6)** — auto-apply accepted suggestions CLI surface. Traverses `.swiftinfer/decisions.json` + `Tests/Generated/SwiftInfer/` and emits real test files for the user's accept gestures.
2. **SemanticIndex integration (PRD §20.4)** — replace the current source-walk with SwiftSyntax semantic index. Enables cross-module type resolution; unblocks Constraint Engine, Domain Template Packs, IDE integration.
3. **Test-execution evidence (architectural shift you raised earlier)** — run inferred property tests for evidence rather than name-heuristic guessing. Major design discussion needed (sandboxing, scope, UX).
4. **Domain Template Packs (PRD §20.5)** — extension surface for project-specific algebraic-property templates.

Each is a discrete v1.32+ scope. The user picks the next direction.

## Conclusion

v1.31 closes the 13-cycle longest-running carry-forward priority and opens the design-completion phase. The first emit-side mechanism class (16) ships with full backward compatibility. The empirical-tuning loop's design intent (PRD §19 ≥70%) was reached at v1.30; v1.31 ships the emission correctness that production CM round-trip tests require to compile and pass.

No new findings to rotate forward — v1.31 is correctness work, not calibration work. The cycle-29 priority list is design-completion-driven rather than empirically-driven.
