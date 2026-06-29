import SwiftInferCore

/// Determinism arm of `LiftedTestEmitter`, kept in its own file so the core
/// emitter stays under SwiftLint's file-length cap. Mirrors the M5.5 lifted-only
/// arms: it composes the shared `makeTestStubExpression` scaffold directly.
extension LiftedTestEmitter {

    /// Emit a determinism test stub for a pure `f: T -> U`. The body asserts
    /// `f(value) == f(value)` over the supplied generator — a tautology for a
    /// genuinely pure function, so the test is a regression guard that catches
    /// hidden nondeterminism (a global read, dictionary ordering, a clock). It
    /// is seed-driven from a lint pure-function candidate, not inferred from the
    /// signature. Equality keys off the *return* type, so `.approximate` is used
    /// for floating-point results.
    ///
    /// `argumentLabel` is the single parameter's external label (e.g.
    /// `forTypeName`), so the emitted call is `f(forTypeName: value)` and
    /// compiles for labeled functions; `nil` (an `_`-labeled parameter) emits
    /// the bare `f(value)`.
    public static func deterministic(
        funcName: String,
        argumentLabel: String? = nil,
        seed: SamplingSeed.Value,
        generator: String,
        equalityKind: EqualityKind = .strict
    ) -> String {
        let call = argumentLabel.map { "\(funcName)(\($0): value)" } ?? "\(funcName)(value)"
        let property = equalityExpression(lhs: call, rhs: call, kind: equalityKind)
        return makeTestStubExpression(
            testFunctionName: "\(funcName)_isDeterministic",
            seed: seed,
            sampleExpression: "{ rng in (\(generator)).run(using: &rng) }",
            propertyExpression: "{ value in \(property) }",
            failureLabel: "\(funcName)(_:) is not deterministic — same input produced different output"
        )
    }
}
