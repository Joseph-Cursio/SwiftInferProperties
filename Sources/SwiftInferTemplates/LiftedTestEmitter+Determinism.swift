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
    ///
    /// **Async form (collections/async workplan Phase 4):** with
    /// `isAsync: true`, each side of the equality becomes `(await f(args))` —
    /// two sequentially awaited calls compared for equality, the same shape
    /// as PropertyLawAsync's `debounceIsDeterministicUnderTestClock`. No
    /// scaffold change is needed: the backend's `property` closure is
    /// already `async` (`PropertyBackend`'s check contract), so the emitted
    /// closure may await. Justified only for clock-deterministic-annotated
    /// candidates — the discover gate enforces that.
    public static func deterministic(
        funcName: String,
        parameters: [DeterminismParameter],
        seed: SamplingSeed.Value,
        equalityKind: EqualityKind = .strict,
        isAsync: Bool = false,
        isThrows: Bool = false
    ) -> String {
        deterministic(
            callee: CalleeReference(bareName: funcName, argumentLabels: parameters.map(\.label)),
            generators: parameters.map(\.generator),
            seed: seed,
            equalityKind: equalityKind,
            isAsync: isAsync,
            isThrows: isThrows
        )
    }

    /// The determinism stub for a callee — qualified, labelled, and drawing a receiver.
    ///
    /// ## Why a bare name could not work
    ///
    /// The `funcName:` form above splices one string into the call, which is right for a free
    /// function and wrong for every member: `tokenizeLine(args.0, args.1)` for a member of
    /// `SwiftTokenizer` is `cannot find 'tokenizeLine' in scope`. **In the corpus funnel census all
    /// 33 determinism stubs that compiled were free functions, and 776 member stubs failed** (#465)
    /// — the defect #415 fixed for every signature-template arm, which this one dispatches ahead of.
    ///
    /// `generators` holds one draw per argument the call needs, the receiver's first for an
    /// instance method, exactly as the totality arm takes them. One draws `value`; several draw a
    /// tuple and call with `args.0`, `args.1`, ….
    ///
    /// A synchronous isolated callee gets one hop around the whole equality; an async one is
    /// awaited instead, because `MainActor.run` cannot contain an `await` (#432).
    public static func deterministic(
        callee: CalleeReference,
        generators: [String],
        seed: SamplingSeed.Value,
        equalityKind: EqualityKind = .strict,
        isAsync: Bool = false,
        isThrows: Bool = false
    ) -> String {
        let isTuple = generators.count > 1
        let bind = isTuple ? "args" : "value"
        let invocation = callee.call(isTuple ? generators.indices.map { "args.\($0)" } : ["value"])
        let property: String
        if isThrows {
            // A throwing pure function is deterministic over `Result`: compare
            // `try? f(x)` on both sides. An input in the throwing domain collapses
            // to `nil == nil` (no false positive); only a value difference — the
            // hidden nondeterminism the law targets — falsifies it. Strict `==` on
            // the resulting optional; the caveat already requires `Equatable`.
            let prefix = isAsync ? "try? await " : "try? "
            let call = "(\(prefix)\(invocation))"
            property = "\(call) == \(call)"
        } else {
            let call = isAsync ? "(await \(invocation))" : invocation
            property = equalityExpression(lhs: call, rhs: call, kind: equalityKind)
        }
        return makeTestStubExpression(
            testFunctionName: "\(callee.bareName)_isDeterministic",
            seed: seed,
            sampleExpression: determinismSample(generators: generators),
            propertyExpression: "{ \(bind) in \(isAsync ? property : callee.isolated(property)) }",
            failureLabel: "\(callee.displaySignature) is not deterministic — same input produced different output"
        )
    }

    /// One draw for a single generator; for several, a tuple of draws in argument order (the
    /// multi-line sample shape `monotonic`/`commutative` use).
    private static func determinismSample(generators: [String]) -> String {
        guard generators.count > 1 else {
            return "{ rng in (\(generators.first ?? "")).run(using: &rng) }"
        }
        let draws = generators.indices.map { index in
            "                    let arg\(index) = (\(generators[index])).run(using: &rng)"
        }
        let slots = generators.indices.map { "arg\($0)" }.joined(separator: ", ")
        let tupleReturn = "                    return (\(slots))"
        return (["{ rng in"] + draws + [tupleReturn, "                }"]).joined(separator: "\n")
    }
}
