import Foundation
import Testing
@testable import SwiftInferCore

@Suite("NClassEquivalenceClassHint — TestLifter M13.2 data model")
struct NClassEquivalenceClassHintTests {

    // MARK: - init + Equatable

    @Test("Init carries every field verbatim")
    func initCarriesFields() {
        let hint = NClassEquivalenceClassHint(
            predicateName: "size",
            argTypeName: "Box",
            returnTypeName: "Size",
            markerSetName: "Sizes",
            markers: ["Small", "Medium", "Large"],
            siteCountsByMarker: ["Small": 3, "Medium": 4, "Large": 5],
            predicateVeto: nil,
            suggestedGeneratorsByMarker: [
                "Small": "Gen<Box>.gen().filter { size($0) == .small }",
                "Medium": "Gen<Box>.gen().filter { size($0) == .medium }",
                "Large": "Gen<Box>.gen().filter { size($0) == .large }"
            ]
        )
        #expect(hint.predicateName == "size")
        #expect(hint.argTypeName == "Box")
        #expect(hint.returnTypeName == "Size")
        #expect(hint.markerSetName == "Sizes")
        #expect(hint.markers == ["Small", "Medium", "Large"])
        #expect(hint.siteCountsByMarker["Medium"] == 4)
        #expect(hint.predicateVeto == nil)
        #expect(hint.suggestedGeneratorsByMarker.count == 3)
    }

    @Test("Equatable holds across identical hints")
    func equatable() {
        let lhs = NClassEquivalenceClassHint(
            predicateName: "p", argTypeName: "T", returnTypeName: "R",
            markerSetName: "S", markers: ["a"], siteCountsByMarker: ["a": 3],
            predicateVeto: nil, suggestedGeneratorsByMarker: ["a": "g"]
        )
        let rhs = NClassEquivalenceClassHint(
            predicateName: "p", argTypeName: "T", returnTypeName: "R",
            markerSetName: "S", markers: ["a"], siteCountsByMarker: ["a": 3],
            predicateVeto: nil, suggestedGeneratorsByMarker: ["a": "g"]
        )
        #expect(lhs == rhs)
    }

    // MARK: - Codable round-trip

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = NClassEquivalenceClassHint(
            predicateName: "size",
            argTypeName: "Box",
            returnTypeName: "Size",
            markerSetName: "Sizes",
            markers: ["Small", "Medium", "Large"],
            siteCountsByMarker: ["Small": 3, "Medium": 4, "Large": 5],
            predicateVeto: .predicateThrows,
            suggestedGeneratorsByMarker: ["Small": "g1", "Medium": "g2", "Large": "g3"]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NClassEquivalenceClassHint.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - PredicateVetoReason — new M13.2 case

    @Test("predicateReturnNotEquatable veto reason has user-facing advisory text")
    func newVetoReasonHasAdvisory() {
        let veto = PredicateVetoReason.predicateReturnNotEquatable
        #expect(!veto.advisoryReason.isEmpty)
        #expect(veto.advisoryReason.lowercased().contains("equatable"))
    }

    @Test("predicateReturnNotEquatable Codable round-trip")
    func newVetoReasonCodable() throws {
        let original = PredicateVetoReason.predicateReturnNotEquatable
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PredicateVetoReason.self, from: data)
        #expect(decoded == original)
    }
}
