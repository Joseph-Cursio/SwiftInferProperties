import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// MARK: - Round-trip

@Suite("AssumedKitCoverage — round-trip (V1.5.2)")
struct RoundTripAssumedKitCoverageTests {

    @Test("Round-trip on : Codable forward type vetoes")
    func codableVetoesRoundTrip() {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "User",
            forwardReturn: "Data"
        )
        let result = RoundTripTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("User", conformances: ["Codable"])
        )
        #expect(result == nil, "Codable conformance should suppress round-trip")
    }

    @Test("Round-trip on plain forward type does NOT veto")
    func plainForwardTypeDoesNotVetoRoundTrip() throws {
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "Doc",
            forwardReturn: "String"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Doc", conformances: ["Equatable", "Sendable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    @Test("Round-trip on : Encodable-only type does NOT veto (Codable-only key in table)")
    func encodableOnlyDoesNotVetoRoundTrip() throws {
        // V1.5.1 documented limitation: Encodable / Decodable as separate
        // conformances aren't covered (neither alone covers
        // codableRoundTrip). User code that writes them separately
        // doesn't get suppression.
        let pair = makeRoundTripPair(
            forwardName: "encode",
            reverseName: "decode",
            forwardParam: "Tag",
            forwardReturn: "Data"
        )
        let suggestion = try #require(RoundTripTemplate.suggest(
            for: pair,
            inheritedTypesByName: makeInheritedIndex("Tag", conformances: ["Encodable", "Decodable"])
        ))
        #expect(!suggestion.score.signals.contains { $0.kind == .protocolCoveredProperty })
    }

    // V1.8.1 shape-gate tests live in `RoundTripCodableShapeGateTests.swift`.
}
