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
    /// The property is `agreementProperty` with the subject as its own oracle. A reference oracle
    /// states the same law against `<name>_reference`, so one written through that emitter cannot
    /// spell the binding, `try?`, `await` or actor hop differently from this one.
    ///
    /// ## The approximate helper is appended, which it never used to be
    ///
    /// A `Double` result compares through `approximatelyEqual`, and this arm wrote the call
    /// without the helper every other caller of `equalityExpression` appends — so a
    /// floating-point determinism stub failed with *cannot find 'approximatelyEqual' in scope*.
    /// A throwing subject compares `Optional`s strictly and gets no helper.
    public static func deterministic(
        callee: CalleeReference,
        generators: [String],
        seed: SamplingSeed.Value,
        equalityKind: EqualityKind = .strict,
        isAsync: Bool = false,
        isThrows: Bool = false,
        argumentTypes: [String] = []
    ) -> String {
        let law = AgreementLaw(
            subject: callee,
            oracle: callee,
            argumentTypes: argumentTypes,
            argumentCount: generators.count,
            equalityKind: equalityKind,
            isAsync: isAsync,
            isThrows: isThrows
        )
        let stub = makeTestStubExpression(
            testFunctionName: "\(callee.identifierName)_isDeterministic",
            seed: seed,
            sampleExpression: argumentSample(generators: generators),
            propertyExpression: agreementProperty(law),
            failureLabel: "\(callee.displaySignature) is not deterministic — same input produced different output"
        )
        return withApproximateEqualityHelper(stub, kind: law.effectiveEqualityKind)
    }
}
