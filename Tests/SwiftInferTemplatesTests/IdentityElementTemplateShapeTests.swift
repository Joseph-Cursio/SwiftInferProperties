import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// MARK: - Shared helpers

func makeIdentityElementPair(
    opName: String,
    paramTypes: (String, String),
    returnType: String,
    identityName: String,
    identityType: String,
    opBodySignals: BodySignals = .empty
) -> IdentityElementPair {
    let operation = FunctionSummary(
        name: opName,
        parameters: [
            Parameter(label: nil, internalName: "lhs", typeText: paramTypes.0, isInout: false),
            Parameter(label: nil, internalName: "rhs", typeText: paramTypes.1, isInout: false),
        ],
        returnTypeText: returnType,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 1, column: 1),
        containingTypeName: returnType,
        bodySignals: opBodySignals
    )
    let identity = IdentityCandidate(
        name: identityName,
        typeText: identityType,
        containingTypeName: identityType,
        location: SourceLocation(file: "Test.swift", line: 5, column: 1)
    )
    return IdentityElementPair(operation: operation, identity: identity)
}

@Suite("IdentityElementTemplate — suggestion shape + identity")
struct IdentityElementTemplateShapeTests {

    @Test("Suggestion uses the 'identity-element' template ID and carries op + identity Evidence")
    func evidenceCarriesOpAndIdentity() throws {
        let pair = makeIdentityElementPair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        #expect(suggestion.templateName == "identity-element")
        #expect(suggestion.evidence.count == 2)
        #expect(suggestion.evidence[0].displayName == "merge(_:_:)")
        #expect(suggestion.evidence[0].signature == "(IntSet, IntSet) -> IntSet")
        #expect(suggestion.evidence[1].displayName == "IntSet.empty")
        #expect(suggestion.evidence[1].signature == ": IntSet")
    }

    @Test("Generator and sampling are M2 placeholders (M3/M4 deferred)")
    func placeholderGeneratorAndSampling() throws {
        let pair = makeIdentityElementPair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        #expect(suggestion.generator.source == .notYetComputed)
        #expect(suggestion.generator.confidence == nil)
        #expect(suggestion.generator.sampling == .notRun)
    }

    @Test("Caveats include Equatable, class-equality, and the two-sided identity warning")
    func caveatsAlwaysPresent() throws {
        let pair = makeIdentityElementPair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        #expect(suggestion.explainability.whyMightBeWrong.count == 3)
        #expect(suggestion.explainability.whyMightBeWrong[0].contains("Equatable"))
        #expect(suggestion.explainability.whyMightBeWrong[1].contains("class"))
        #expect(suggestion.explainability.whyMightBeWrong[2].contains("two-sided"))
    }

    @Test("Suggestion identity is namespaced by 'identity-element' and includes op + identity key")
    func identityIncludesTemplateID() throws {
        let pair = makeIdentityElementPair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        let commutativityIdentity = SuggestionIdentity(
            canonicalInput: "commutativity|" + IdempotenceTemplate.canonicalSignature(of: pair.operation)
        )
        #expect(suggestion.identity != commutativityIdentity)
    }

    @Test("Same op + same identity at a different file location preserves identity hash")
    func identityIsLocationIndependent() throws {
        let opA = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "IntSet", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "IntSet", isInout: false),
            ],
            returnTypeText: "IntSet",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 1, column: 1),
            containingTypeName: "IntSet",
            bodySignals: .empty
        )
        let opB = FunctionSummary(
            name: "merge",
            parameters: opA.parameters,
            returnTypeText: opA.returnTypeText,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "B.swift", line: 99, column: 1),
            containingTypeName: "IntSet",
            bodySignals: .empty
        )
        let identityA = IdentityCandidate(
            name: "empty",
            typeText: "IntSet",
            containingTypeName: "IntSet",
            location: SourceLocation(file: "A.swift", line: 5, column: 1)
        )
        let identityB = IdentityCandidate(
            name: "empty",
            typeText: "IntSet",
            containingTypeName: "IntSet",
            location: SourceLocation(file: "C.swift", line: 50, column: 1)
        )
        let suggestionA = try #require(
            IdentityElementTemplate.suggest(for: IdentityElementPair(operation: opA, identity: identityA))
        )
        let suggestionB = try #require(
            IdentityElementTemplate.suggest(for: IdentityElementPair(operation: opB, identity: identityB))
        )
        #expect(suggestionA.identity == suggestionB.identity)
    }
}
