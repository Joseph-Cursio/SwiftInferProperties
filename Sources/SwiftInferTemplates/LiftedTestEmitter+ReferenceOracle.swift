import SwiftInferCore

/// The reference-oracle scaffold for any subject `accept` can call: a free function, a static or
/// instance member, an operator, `throws`, `async`, a global actor or an actor instance.
///
/// ## Why the call is the accept path's, not its own
///
/// The scaffold used to splice the bare function name into its property —
/// `fileName(tuple.0, matches: tuple.1) == fileName_reference(…)` for a static member of
/// `SandboxLedger.SourceKind` — and to declare the reference as a free function at file scope.
/// None of the 88 scaffolds `discover` printed on SwiftAssist compiled: 68 called a static member
/// unqualified, 18 called an instance method with no receiver, and 45 also hit *unable to
/// type-check this expression in reasonable time* on the one-line tuple sample.
///
/// The determinism law is the same law with the subject on both sides, and accept already wrote
/// it so that it compiles. So both now write their comparison through `agreementProperty`: the
/// subject spelled by `CalleeReference` (qualified, or with a drawn receiver first), `try?` and
/// `await` on both sides, one actor hop, the #498 `(args: (A, B))` binding, the multi-line
/// `argumentSample`, and `approximatelyEqual` for a floating-point result. The oracle only
/// renames the right-hand callee to `<name>_reference`.
///
/// ## Where the reference lives
///
/// A free function's reference is a free function, exactly as before. A member's is declared in
/// `extension <Owner> { … }`, where `Self`, the owner's nested types and its isolation all
/// resolve as they do for the subject — a file-scope `-> Self?` was *global function cannot
/// return 'Self'*. The reference copies `static` and `nonisolated` from the subject: a
/// `nonisolated` actor member compared with an isolated reference fails with *actor-isolated
/// instance method cannot be called from outside of the actor*.
extension LiftedTestEmitter {

    /// The function a reference oracle checks, spelled as accept spells it.
    public struct ReferenceOracleSubject: Sendable, Equatable {

        /// The subject's call: qualified for a static member, receiver-first for an instance one.
        public let callee: CalleeReference

        /// The declaring type's qualified name, or `nil` for a free function.
        public let owner: String?

        /// The declared parameters, receiver excluded, as the reference declaration repeats them.
        public let parameters: [Parameter]

        /// The declared result, effects stripped.
        public let returnTypeText: String

        public let isAsync: Bool
        public let isThrows: Bool

        /// Whether the subject spells `nonisolated`, which its reference must copy.
        public let declaresNonisolated: Bool

        public init(
            callee: CalleeReference,
            owner: String?,
            parameters: [Parameter],
            returnTypeText: String,
            isAsync: Bool,
            isThrows: Bool,
            declaresNonisolated: Bool = false
        ) {
            self.callee = callee
            self.owner = owner
            self.parameters = parameters
            self.returnTypeText = returnTypeText
            self.isAsync = isAsync
            self.isThrows = isThrows
            self.declaresNonisolated = declaresNonisolated
        }

        /// The `<name>_reference` twin the property calls on the right-hand side.
        ///
        /// Same receiver and isolation as the subject. A static or operator member is called
        /// through its owner (an operator's twin is a named function, so it has no infix form),
        /// and an operator's twin takes no labels, because it is declared with `_` for each.
        public var reference: CalleeReference {
            CalleeReference(
                bareName: "\(callee.identifierName)_reference",
                qualifier: callee.isInstanceMethod ? nil : owner,
                argumentLabels: callee.isOperator ? callee.argumentLabels.map { _ in nil } : callee.argumentLabels,
                isolation: callee.isolation,
                isInstanceMethod: callee.isInstanceMethod
            )
        }

        /// `<id>_matchesReferenceDefinition`, prefixed with the owner for a member: SwiftAssist
        /// alone prints three `resolve` scaffolds, on three types.
        var testFunctionName: String {
            let name = "\(callee.identifierName)_matchesReferenceDefinition"
            guard let owner else { return name }
            return "\(owner.replacingOccurrences(of: ".", with: "_"))_\(name)"
        }

        /// The subject as a reader greps for it — qualified with its owner, receiver or not.
        var failureLabel: String {
            let prefix = callee.qualifier == nil ? owner.map { "\($0)." } ?? "" : ""
            return "\(prefix)\(callee.displaySignature) disagrees with its documented reference definition"
        }
    }

    /// What the oracle's sample draws: one generator per call argument, receiver first.
    public struct ReferenceOracleDraws: Sendable, Equatable {

        /// One generator expression per call argument, receiver first.
        public let generators: [String]

        /// The same arguments' types, as a test file spells them — they annotate the binding and
        /// choose each argument's edge bias.
        public let argumentTypes: [String]

        /// Types the scaffold must declare `@unchecked Sendable` for its inputs to be a check's
        /// `Input`, sorted.
        public let sendableShims: [String]

        public init(generators: [String], argumentTypes: [String], sendableShims: [String] = []) {
            self.generators = generators
            self.argumentTypes = argumentTypes
            self.sendableShims = sendableShims
        }
    }

    /// The scaffold: guidance comments, the `_reference` declaration with a `fatalError` body for
    /// the reader to replace, and a `@Test` checking `subject(args) == reference(args)`.
    ///
    /// Each numeric argument keeps the scaffold's own edge bias (`edgeBiasedGenerator`), so an
    /// `Int` still draws `0` and `±1` beside the bounded uniform baseline. A throwing subject
    /// compares `try?` on both sides strictly, so it never needs the approximate helper.
    public static func referenceOracle(
        subject: ReferenceOracleSubject,
        draws: ReferenceOracleDraws,
        equalityKind: EqualityKind,
        docComment: String,
        seed: SamplingSeed.Value
    ) -> String {
        guard !draws.generators.isEmpty else { return "" }
        let law = AgreementLaw(
            subject: subject.callee,
            oracle: subject.reference,
            argumentTypes: draws.argumentTypes,
            argumentCount: draws.generators.count,
            equalityKind: equalityKind,
            isAsync: subject.isAsync,
            isThrows: subject.isThrows
        )
        let biased = draws.generators.indices.map { index in
            index < draws.argumentTypes.count
                ? edgeBiasedGenerator(forTypeText: draws.argumentTypes[index], fallback: draws.generators[index])
                : draws.generators[index]
        }
        let stub = guidance(subject: subject, docComment: docComment, shims: draws.sendableShims)
            + referenceDeclaration(subject)
        let test = makeTestStubExpression(
            testFunctionName: subject.testFunctionName,
            seed: seed,
            sampleExpression: argumentSample(generators: biased),
            propertyExpression: agreementProperty(law),
            failureLabel: subject.failureLabel
        )
        return withApproximateEqualityHelper(stub + "\n" + test, kind: law.effectiveEqualityKind)
    }

    /// The comment block above the reference, ending in a newline: the docstring, then what a
    /// throwing subject's comparison means, what the result needs, and the `Sendable` shims.
    static func guidance(subject: ReferenceOracleSubject, docComment: String, shims: [String]) -> String {
        var lines = [
            "// Fill in the reference definition below — your docstring already states it:",
            "//   \"\(docComment)\"",
            "// Then run the test: the generator finds the input where the code disagrees",
            "// with its own documentation."
        ]
        if subject.isThrows {
            lines.append(
                "// It throws, so both sides are compared through try?: throwing on the same inputs "
                    + "counts as agreeing (which error is not compared)."
            )
        }
        let note = subject.returnTypeText == "Bool" ? "" : equatableNote(forReturnType: subject.returnTypeText)
        if !note.isEmpty { lines.append(String(note.dropLast())) }
        if !shims.isEmpty {
            lines.append(
                "// Inputs must be Sendable. Declare each of these once per test target, and delete it if "
                    + "SwiftInferSendableShims.swift or another scaffold already does:"
            )
            lines += shims.map { "extension \($0): @unchecked Sendable {}" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `func <id>_reference(…)[ async][ throws] -> R { fatalError(…) }` — at file scope for a
    /// free function, inside `extension <Owner>` for a member, `static` unless it is an instance
    /// member and `nonisolated` when the subject is.
    static func referenceDeclaration(_ subject: ReferenceOracleSubject) -> String {
        let isOperator = subject.callee.isOperator
        let clause = subject.parameters.map { parameter in
            parameterClause(
                label: isOperator ? nil : parameter.label, name: parameter.internalName, typeText: parameter.typeText
            )
        }
        let effects = (subject.isAsync ? " async" : "") + (subject.isThrows ? " throws" : "")
        let signature = "func \(subject.reference.bareName)(\(clause.joined(separator: ", ")))\(effects) "
            + "-> \(subject.returnTypeText) {"
        let body = "fatalError(\"state the reference definition from the docstring, then replace this line\")"
        guard let owner = subject.owner else {
            return [signature, "    \(body)", "}"].joined(separator: "\n")
        }
        let modifiers = (subject.declaresNonisolated ? "nonisolated " : "")
            + (subject.callee.isInstanceMethod ? "" : "static ")
        return ["extension \(owner) {", "    \(modifiers)\(signature)", "        \(body)", "    }", "}"]
            .joined(separator: "\n")
    }
}
