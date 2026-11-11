import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// MARK: - Inverse-pair

@Suite("AssumedKitCoverage — inverse-pair (V1.5.2)")
struct InversePairAssumedKitCoverageTests {

    @Test("Inverse-pair on : SignedNumeric vetoes (additiveInverse covered)")
    func signedNumericVetoesInversePair() {
        let pair = makeRoundTripPair(
            forwardName: "negate",
            reverseName: "negate",
            forwardParam: "BigInt",
            forwardReturn: "BigInt"
        )
        let result = InversePairTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["SignedNumeric"])
        )
        #expect(result == nil)
    }

    @Test("Inverse-pair on : Group vetoes (groupInverse covered)")
    func groupVetoesInversePair() {
        let pair = makeRoundTripPair(
            forwardName: "compose",
            reverseName: "invert",
            forwardParam: "Permutation",
            forwardReturn: "Permutation"
        )
        let result = InversePairTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Permutation", conformances: ["Group"])
        )
        #expect(result == nil)
    }

    @Test("Inverse-pair on : Numeric does NOT veto (Numeric lacks additiveInverse)")
    func numericDoesNotVetoInversePair() {
        // Numeric covers `+` / `*` but NOT additive-inverse; that's a
        // SignedNumeric-only law. Inverse-pair on a Numeric (not
        // SignedNumeric) carrier stays surfaced.
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "BigInt",
            forwardReturn: "Data"
        )
        let result = InversePairTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("BigInt", conformances: ["Numeric"])
        )
        if let result {
            #expect(!result.score.signals.contains { $0.kind == .protocolCoveredProperty })
        }
    }

    @Test("Inverse-pair on plain user type does NOT veto")
    func plainTypeDoesNotVetoInversePair() throws {
        let pair = makeRoundTripPair(
            forwardName: "parse",
            reverseName: "format",
            forwardParam: "Doc",
            forwardReturn: "String"
        )
        let suggestion = try #require(InversePairTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Doc", conformances: ["Hashable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }
}
