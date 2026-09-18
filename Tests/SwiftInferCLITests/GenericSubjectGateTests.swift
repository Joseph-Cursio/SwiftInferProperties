import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// **A stub that names a type parameter cannot compile, so it is not written** (#493).
///
/// Both exhibits are real declarations from the corpus funnel re-run.
@Suite("Generic subjects — withdrawn, not emitted")
struct GenericSubjectGateTests {

    private static let loc = SourceLocation(file: "MinimalDecoder.swift", line: 108, column: 5)

    private func suggestion(
        display: String,
        parameterTypes: [String],
        owner: String
    ) -> Suggestion {
        Suggestion(
            templateName: "predicate",
            evidence: [
                Evidence(
                    displayName: display,
                    signature: "\(display) -> Bool",
                    location: Self.loc,
                    parameterTypeNames: parameterTypes,
                    qualifiedTypeName: owner
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "predicate|\(owner)|\(display)"),
            carrier: owner
        )
    }

    /// `struct KeyedDecoding<Key: CodingKey> { func contains(_ key: Key) -> Bool }` —
    /// SwiftPropertyLaws `MinimalDecoder.swift:108`, which emitted `Key.gen()`.
    @Test("a parameter whose type is a type parameter is withdrawn, and the name is reported")
    func typeParameterAsParameterType() throws {
        let reason = try #require(GenericSubjectGate.declineReason(
            for: suggestion(display: "contains(_:)", parameterTypes: ["Key"], owner: "KeyedDecoding"),
            genericParametersByName: [
                "KeyedDecoding": [TypeDecl.GenericParameter(name: "Key", constraint: "CodingKey")]
            ]
        ))
        #expect(reason.contains("Key"))
        #expect(reason.contains("generic parameter"))
        #expect(reason.contains("KeyedDecoding"))
    }

    /// The receiver written bare. Same defect CLAUDE.md records for monotonicity's carriers —
    /// "of 34 distinct carriers in production output ZERO contain `<`".
    @Test("a generic receiver with no type arguments is withdrawn")
    func genericReceiverWithoutArguments() throws {
        let reason = try #require(GenericSubjectGate.declineReason(
            for: suggestion(display: "isEmpty", parameterTypes: [], owner: "Deque"),
            genericParametersByName: [
                "Deque": [TypeDecl.GenericParameter(name: "Element", constraint: nil)]
            ]
        ))
        #expect(reason.contains("Deque"))
        #expect(reason.contains("type arguments"))
    }

    /// **The gate must cost no laws.** A non-generic subject is untouched, which is the whole
    /// argument for shipping a 55-row withdrawal.
    @Test("a non-generic subject is not gated")
    func nonGenericIsUntouched() {
        #expect(GenericSubjectGate.declineReason(
            for: suggestion(display: "isValid(_:)", parameterTypes: ["String"], owner: "Checker"),
            genericParametersByName: ["Deque": [TypeDecl.GenericParameter(name: "Element", constraint: nil)]]
        ) == nil)
    }

    /// A generic type is only a problem where the emitted call would NAME a parameter. A method
    /// on a generic type taking a concrete type still writes its receiver bare, so it is gated —
    /// but a subject on a type with no generics never is, whatever the map holds.
    @Test("an empty map gates nothing, so a caller without one behaves as before")
    func emptyMapIsInert() {
        #expect(GenericSubjectGate.declineReason(
            for: suggestion(display: "contains(_:)", parameterTypes: ["Key"], owner: "KeyedDecoding"),
            genericParametersByName: [:]
        ) == nil)
    }

    // MARK: - A generic function's own parameters (#497)

    /// The exhibit from #497, scanned rather than hand-built, so the test covers the scanner and
    /// the `Evidence` projection as well as the gate. It is a top-level function with no declaring
    /// type and an empty map — both guards #493's gate had, and the reason it withdrew nothing here.
    @Test("a top-level generic function is withdrawn with no owner and no map")
    func scannedGenericFreeFunction() throws {
        let summary = try #require(FunctionScanner.scan(
            source: """
            func swapAtInvolutionCounterexample<C: MutableCollection>(for sample: C) -> String? { nil }
            """,
            file: "Involution.swift"
        ).first)
        #expect(summary.genericParameters == [
            TypeDecl.GenericParameter(name: "C", constraint: "MutableCollection")
        ])
        let evidence = summary.inferenceEvidence
        #expect(evidence.genericParameters == summary.genericParameters)

        let reason = try #require(GenericSubjectGate.declineReason(
            for: suggestion(evidence: evidence, carrier: nil),
            genericParametersByName: [:]
        ))
        #expect(reason.contains("takes C"))
        #expect(reason.contains("function itself"))
    }

    /// The head of `Set<T>` is `Set`, so `bareName` would miss it; the argument is the parameter.
    @Test("a type parameter nested inside a parameter's type is named")
    func nestedTypeParameterIsNamed() throws {
        let reason = try #require(GenericSubjectGate.declineReason(
            for: suggestion(
                evidence: evidence(display: "union(_:)", parameterTypes: ["Set<T>"], generics: ["T"]),
                carrier: nil
            ),
            genericParametersByName: [:]
        ))
        #expect(reason.contains("takes T"))
    }

    /// `func make<T>() -> T` has no parameter to name `T`, and nothing to infer it from either.
    @Test("a type parameter used only in the return type is still withdrawn")
    func returnOnlyTypeParameter() throws {
        let reason = try #require(GenericSubjectGate.declineReason(
            for: suggestion(
                evidence: evidence(display: "make()", parameterTypes: [], generics: ["T"]),
                carrier: nil
            ),
            genericParametersByName: [:]
        ))
        #expect(reason.contains("generic function over T"))
    }

    /// **The gate must still cost no laws**: a scanned non-generic free function records nothing
    /// and is untouched.
    @Test("a non-generic free function records no parameters and is not gated")
    func nonGenericFreeFunctionIsUntouched() throws {
        let summary = try #require(FunctionScanner.scan(
            source: "func isValid(_ name: String) -> Bool { true }",
            file: "Checker.swift"
        ).first)
        #expect(summary.genericParameters.isEmpty)
        #expect(GenericSubjectGate.declineReason(
            for: suggestion(evidence: summary.inferenceEvidence, carrier: nil),
            genericParametersByName: [:]
        ) == nil)
    }

    /// A method on a non-generic type that is itself generic: the function's parameters are read,
    /// the map holding an unrelated type does not matter.
    @Test("a generic method on a non-generic type is withdrawn")
    func genericMethodOnPlainType() throws {
        let summary = try #require(FunctionScanner.scan(
            source: """
            struct Sorter {
                func sorted<S: Sequence>(_ values: S) -> [S.Element] where S.Element: Comparable { [] }
            }
            """,
            file: "Sorter.swift"
        ).first)
        let reason = try #require(GenericSubjectGate.declineReason(
            for: suggestion(evidence: summary.inferenceEvidence, carrier: "Sorter"),
            genericParametersByName: ["Deque": [TypeDecl.GenericParameter(name: "Element", constraint: nil)]]
        ))
        #expect(reason.contains("takes S"))
    }

    private func evidence(display: String, parameterTypes: [String], generics: [String]) -> Evidence {
        Evidence(
            displayName: display,
            signature: "\(display) -> Bool",
            location: Self.loc,
            parameterTypeNames: parameterTypes,
            genericParameters: generics.map { TypeDecl.GenericParameter(name: $0, constraint: nil) }
        )
    }

    private func suggestion(evidence: Evidence, carrier: String?) -> Suggestion {
        Suggestion(
            templateName: "predicate",
            evidence: [evidence],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "predicate|\(evidence.displayName)"),
            carrier: carrier
        )
    }
}
