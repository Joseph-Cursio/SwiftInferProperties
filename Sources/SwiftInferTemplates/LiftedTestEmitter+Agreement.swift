import SwiftInferCore

/// The property *"the subject agrees with an oracle on every drawn input"*, written once.
///
/// ## Why one emitter for two laws
///
/// The determinism law, `f(args) == f(args)`, and the docstring advisory's reference oracle,
/// `f(args) == f_reference(args)`, are the same law with a different right-hand side. Everything
/// that decides whether the stub compiles sits in what they share, not in the oracle:
///
/// - the binding — `value` for one argument, the #498 `(args: (A, B))` annotation for several,
///   without which a tuple drawn from large generic generators cannot be inferred;
/// - `try?` on both sides of a throwing subject, `await` on both sides of an async one;
/// - the actor hop, one `MainActor.run` around the whole comparison, or one `await` per
///   statement for an actor-instance receiver (`CalleeReference.isolated`);
/// - `equalityExpression`, with `approximatelyEqual` for a floating-point result.
///
/// The determinism arm had all of these and the docstring advisory's reference-oracle scaffold
/// has none: it spells a bare call (`fileName(…)` for `SandboxLedger.SourceKind.fileName`),
/// draws no receiver and writes no `try`, and none of the 88 scaffolds discover prints on
/// SwiftAssist compiles. A law that writes its comparison here gets every one of them, so the
/// two cannot drift apart once both do. Determinism passes the subject as its own oracle
/// (`deterministic(callee:…)`), and `DeterminismCalleeEmitterTests` pins that its property is
/// exactly this one.
extension LiftedTestEmitter {

    /// What `agreementProperty` compares: two calls with the same drawn arguments.
    public struct AgreementLaw: Sendable, Equatable {

        /// The function under test, spelled as accept spells it — qualified, labelled, with a
        /// drawn receiver first for an instance method.
        public let subject: CalleeReference

        /// The right-hand side. The subject itself for determinism; its `_reference` twin for
        /// the docstring advisory's reference oracle.
        public let oracle: CalleeReference

        /// One type per drawn argument, receiver first, annotating the multi-argument binding.
        /// Empty, or of a different count, falls back to the bare `args` binding.
        public let argumentTypes: [String]

        /// How many arguments each call takes — the number of generators the sample draws.
        public let argumentCount: Int

        /// How the two results are compared when the subject does not throw.
        public let equalityKind: EqualityKind

        /// Whether each call is awaited.
        public let isAsync: Bool

        /// Whether each call is wrapped in `try?` and compared as an `Optional`.
        public let isThrows: Bool

        public init(
            subject: CalleeReference,
            oracle: CalleeReference,
            argumentTypes: [String],
            argumentCount: Int,
            equalityKind: EqualityKind,
            isAsync: Bool,
            isThrows: Bool
        ) {
            self.subject = subject
            self.oracle = oracle
            self.argumentTypes = argumentTypes
            self.argumentCount = argumentCount
            self.equalityKind = equalityKind
            self.isAsync = isAsync
            self.isThrows = isThrows
        }

        /// The equality the emitted stub actually uses: a throwing subject compares two
        /// `Optional`s with `==`, whatever the result type, so it never needs the helper.
        public var effectiveEqualityKind: EqualityKind {
            isThrows ? .strict : equalityKind
        }
    }

    /// The property closure `{ <binding> in <subject(args)> <eq> <oracle(args)> }`.
    ///
    /// **A throwing subject compares `try?` on both sides, strictly.** An input in the throwing
    /// domain collapses to `nil == nil`, so throwing on the same inputs counts as agreeing and
    /// only a value difference falsifies the law. `Optional`'s `==` needs the result to CONFORM
    /// to `Equatable`, which is why a tuple result is declined before this is reached
    /// (`InteractiveTriage.determinismResultDeclineReason`).
    ///
    /// **An async subject is awaited on each side and never hopped**, because `MainActor.run`
    /// takes a synchronous closure (#432). A synchronous isolated subject gets one hop around
    /// the whole comparison — the oracle is declared beside the subject, so it shares the
    /// subject's isolation and the one hop covers both.
    public static func agreementProperty(_ law: AgreementLaw) -> String {
        let isTuple = law.argumentCount > 1
        let bind = isTuple
            ? tupleBinding(argumentTypes: law.argumentTypes, count: law.argumentCount)
            : "value"
        let arguments = isTuple ? (0 ..< law.argumentCount).map { "args.\($0)" } : ["value"]
        let subjectCall = law.subject.call(arguments)
        let oracleCall = law.oracle.call(arguments)
        let property: String
        if law.isThrows {
            let prefix = law.isAsync ? "try? await " : "try? "
            property = "(\(prefix)\(subjectCall)) == (\(prefix)\(oracleCall))"
        } else {
            let lhs = law.isAsync ? "(await \(subjectCall))" : subjectCall
            let rhs = law.isAsync ? "(await \(oracleCall))" : oracleCall
            property = equalityExpression(lhs: lhs, rhs: rhs, kind: law.equalityKind)
        }
        return "{ \(bind) in \(law.isAsync ? property : law.subject.isolated(property)) }"
    }

    /// The sample closure for one draw per generator, in argument order.
    ///
    /// One generator draws a single value inline. Several draw **one `let` per argument**, then
    /// return the tuple — the multi-line shape `monotonic` and `commutative` use. The one-line
    /// tuple of `.run(using:)` calls is what the reference-oracle scaffold writes, and on
    /// SwiftAssist it sits behind its *unable to type-check this expression in reasonable time*
    /// failures: a `SandboxLedger.SourceKind.fileName` scaffold that timed out compiled in 4.1 s
    /// once written this way, with the `(args: (String, String))` binding beside it.
    public static func argumentSample(generators: [String]) -> String {
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

    /// Whether a generator expression is a placeholder rather than a draw: the `.todo` member, or
    /// the block-comment marker `defaultGenerator` writes when nothing derives — which census 13
    /// also found inside a derived generator. Neither compiles.
    ///
    /// One reading, shared by every caller that must refuse to build on an unresolved generator,
    /// so the marker's spelling lives in one place.
    public static func isUnresolvedGenerator(_ generator: String) -> Bool {
        generator.contains(".todo") || generator.contains("no generator derived")
    }
}
