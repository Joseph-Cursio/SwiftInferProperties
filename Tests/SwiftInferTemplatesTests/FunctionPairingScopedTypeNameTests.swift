import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// A bare nested type name resolves to the type it names in the function's own scope before pairing.
///
/// OpenAPIKit declares a `CodingKeys` inside each of dozens of types, each with
/// `var stringValue: String` and `static func extendedKey(for: String) -> CodingKeys`. Compared as
/// text, every one read as the inverse of every other — 1,520 false round-trip rows.
@Suite("FunctionPairing — scoped type names")
struct FunctionPairingScopedTypeNameTests {

    private func summary(
        _ name: String, param: String?, returns: String, in scope: String, isStatic: Bool = false, line: Int
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: param.map {
                [Parameter(label: nil, internalName: "value", typeText: $0, isInout: false)]
            } ?? [],
            returnTypeText: returns,
            isThrows: false, isAsync: false, isMutating: false, isStatic: isStatic,
            location: SourceLocation(file: "Keys.swift", line: line, column: 1),
            containingTypeName: String(scope.split(separator: ".").last!),
            bodySignals: .empty,
            qualifiedContainingTypeName: scope
        )
    }

    @Test("two nested CodingKeys on DIFFERENT types do not pair")
    func nestedNamesDoNotPairAcrossTypes() {
        let document = summary("stringValue", param: nil, returns: "String", in: "OpenAPI.Document.CodingKeys", line: 3)
        let operation = summary(
            "extendedKey", param: "String", returns: "CodingKeys", in: "OpenAPI.Operation.CodingKeys",
            isStatic: true, line: 30
        )
        #expect(FunctionPairing.candidates(in: [document, operation]).isEmpty)
    }

    @Test("the same pair on ONE nested type still pairs")
    func nestedNamesStillPairWithinOneType() {
        let forward = summary("stringValue", param: nil, returns: "String", in: "OpenAPI.Document.CodingKeys", line: 3)
        let inverse = summary(
            "extendedKey", param: "String", returns: "CodingKeys", in: "OpenAPI.Document.CodingKeys",
            isStatic: true, line: 9
        )
        #expect(FunctionPairing.candidates(in: [forward, inverse]).count == 1)
    }

    @Test("a function on the parent that returns its nested type pairs with that type's own function")
    func parentReturningItsNestedTypeStillPairs() {
        let parent = summary(
            "key", param: "String", returns: "CodingKeys", in: "OpenAPI.Document", isStatic: true, line: 3
        )
        let child = summary("stringValue", param: nil, returns: "String", in: "OpenAPI.Document.CodingKeys", line: 9)
        #expect(FunctionPairing.candidates(in: [parent, child]).count == 1)
    }

    @Test("resolution is Swift's lookup: innermost declared scope first, unresolved names left alone")
    func resolutionFollowsLookup() {
        let declared: Set<String> = ["A", "A.B", "A.B.Key", "A.Key"]
        let inner = summary("f", param: nil, returns: "Key", in: "A.B", line: 1)
        let outer = summary("g", param: nil, returns: "Key", in: "A", line: 2)
        #expect(FunctionPairing.resolvingScopedNames("Key", declaredIn: inner, declared: declared) == "A.B.Key")
        #expect(FunctionPairing.resolvingScopedNames("[Key]?", declaredIn: outer, declared: declared) == "[A.Key]?")
        #expect(FunctionPairing.resolvingScopedNames("String", declaredIn: inner, declared: declared) == "String")
        #expect(FunctionPairing.resolvingScopedNames("Other.Key", declaredIn: inner, declared: declared) == "Other.Key")
    }
}
