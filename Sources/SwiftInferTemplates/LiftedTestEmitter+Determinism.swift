import SwiftInferCore

/// Determinism arm of `LiftedTestEmitter`, kept in its own file so the core
/// emitter stays under SwiftLint's file-length cap. Mirrors the M5.5 lifted-only
/// arms: it composes the shared `makeTestStubExpression` scaffold directly.
extension LiftedTestEmitter {

    /// One parameter of the function under a determinism stub: its external
    /// label (`nil` for an `_`-labeled parameter) and the generator expression
    /// for its type.
    public struct DeterminismParameter: Sendable, Equatable {
        public let label: String?
        public let generator: String

        public init(label: String?, generator: String) {
            self.label = label
            self.generator = generator
        }
    }

    /// Emit a determinism test stub for a pure `f: (P0, P1, …) -> U`. The body
    /// asserts `f(args) == f(args)` over generated inputs — a tautology for a
    /// genuinely pure function, so the test is a regression guard that catches
    /// hidden nondeterminism (a global read, dictionary ordering, a clock).
    /// Seed-driven from a lint pure-function candidate, not inferred from the
    /// signature. Equality keys off the *return* type, so `.approximate` is used
    /// for floating-point results.
    ///
    /// One parameter draws a single `value`; two or more draw a tuple, one slot
    /// per parameter from its own generator. Labels are emitted so the call
    /// compiles for labeled functions.
    public static func deterministic(
        funcName: String,
        parameters: [DeterminismParameter],
        seed: SamplingSeed.Value,
        equalityKind: EqualityKind = .strict
    ) -> String {
        let shape = parameters.count == 1
            ? singleParameterShape(funcName: funcName, parameter: parameters[0])
            : tupleShape(funcName: funcName, parameters: parameters)
        let property = equalityExpression(lhs: shape.call, rhs: shape.call, kind: equalityKind)
        return makeTestStubExpression(
            testFunctionName: "\(funcName)_isDeterministic",
            seed: seed,
            sampleExpression: shape.sample,
            propertyExpression: "{ \(shape.bind) in \(property) }",
            failureLabel: "\(funcName)(_:) is not deterministic — same input produced different output"
        )
    }

    /// The three emitted fragments that vary by arity: the `sample` closure, the
    /// name its drawn input is bound to, and the call applied to that input.
    private struct Shape {
        let sample: String
        let bind: String
        let call: String
    }

    /// Single parameter: one `value` drawn from one generator, called directly.
    private static func singleParameterShape(
        funcName: String,
        parameter: DeterminismParameter
    ) -> Shape {
        let argument = parameter.label.map { "\($0): value" } ?? "value"
        return Shape(
            sample: "{ rng in (\(parameter.generator)).run(using: &rng) }",
            bind: "value",
            call: "\(funcName)(\(argument))"
        )
    }

    /// Two or more parameters: draw a tuple, one slot per parameter from its own
    /// generator (the same multi-line sample shape `monotonic`/`commutative`
    /// use), then call with `args.0`, `args.1`, … under each label.
    private static func tupleShape(
        funcName: String,
        parameters: [DeterminismParameter]
    ) -> Shape {
        let draws = parameters.indices.map { index in
            "                    let arg\(index) = (\(parameters[index].generator)).run(using: &rng)"
        }
        let slots = parameters.indices.map { "arg\($0)" }.joined(separator: ", ")
        let tupleReturn = "                    return (\(slots))"
        let sample = (["{ rng in"] + draws + [tupleReturn, "                }"]).joined(separator: "\n")
        let argumentList = parameters.indices.map { index in
            (parameters[index].label.map { "\($0): " } ?? "") + "args.\(index)"
        }
        let arguments = argumentList.joined(separator: ", ")
        return Shape(sample: sample, bind: "args", call: "\(funcName)(\(arguments))")
    }
}
