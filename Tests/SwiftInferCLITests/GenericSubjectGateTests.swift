import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
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
}
