import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

@Suite("IdentityElementPairing — type filter")
struct IdentityElementPairingTests {

    @Test("Pairing emits one pair per (op, identity) on matching T")
    func pairingMatchesByType() {
        let merge = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "IntSet", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "IntSet", isInout: false),
            ],
            returnTypeText: "IntSet",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 10, column: 1),
            containingTypeName: "IntSet",
            bodySignals: .empty
        )
        let intSetEmpty = IdentityCandidate(
            name: "empty",
            typeText: "IntSet",
            containingTypeName: "IntSet",
            location: SourceLocation(file: "A.swift", line: 5, column: 1)
        )
        let stringEmpty = IdentityCandidate(
            name: "empty",
            typeText: "String",
            containingTypeName: "String",
            location: SourceLocation(file: "B.swift", line: 1, column: 1)
        )
        let pairs = IdentityElementPairing.candidates(
            in: [merge],
            identities: [intSetEmpty, stringEmpty]
        )
        #expect(pairs.count == 1)
        #expect(pairs.first?.identity.typeText == "IntSet")
    }

    @Test("Pairing rejects non-binary-op summaries")
    func pairingRejectsNonBinaryOps() {
        let normalize = FunctionSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "s", typeText: "String", isInout: false)],
            returnTypeText: "String",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let stringEmpty = IdentityCandidate(
            name: "empty",
            typeText: "String",
            containingTypeName: "String",
            location: SourceLocation(file: "A.swift", line: 5, column: 1)
        )
        let pairs = IdentityElementPairing.candidates(
            in: [normalize],
            identities: [stringEmpty]
        )
        #expect(pairs.isEmpty)
    }

    @Test("Same op + multiple same-typed identities yields one pair per identity")
    func multipleIdentitiesYieldMultiplePairs() {
        let merge = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "IntSet", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "IntSet", isInout: false),
            ],
            returnTypeText: "IntSet",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 10, column: 1),
            containingTypeName: "IntSet",
            bodySignals: .empty
        )
        let zero = IdentityCandidate(
            name: "zero",
            typeText: "IntSet",
            containingTypeName: "IntSet",
            location: SourceLocation(file: "A.swift", line: 4, column: 1)
        )
        let empty = IdentityCandidate(
            name: "empty",
            typeText: "IntSet",
            containingTypeName: "IntSet",
            location: SourceLocation(file: "A.swift", line: 5, column: 1)
        )
        let pairs = IdentityElementPairing.candidates(
            in: [merge],
            identities: [zero, empty]
        )
        #expect(pairs.count == 2)
        #expect(Set(pairs.map(\.identity.name)) == ["zero", "empty"])
    }
}
