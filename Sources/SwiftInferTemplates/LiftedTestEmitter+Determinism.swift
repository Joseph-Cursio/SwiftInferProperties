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
    public static func deterministic(
        funcName: String,
        seed: SamplingSeed.Value,
        generator: String,
        equalityKind: EqualityKind = .strict
    ) -> String {
        let property = equalityExpression(
            lhs: "\(funcName)(value)",
            rhs: "\(funcName)(value)",
            kind: equalityKind
        )
        return makeTestStubExpression(
            testFunctionName: "\(funcName)_isDeterministic",
            seed: seed,
            sampleExpression: "{ rng in (\(generator)).run(&rng) }",
            propertyExpression: "{ value in \(property) }",
            failureLabel: "\(funcName)(_:) is not deterministic — same input produced different output"
        )
    }
}
