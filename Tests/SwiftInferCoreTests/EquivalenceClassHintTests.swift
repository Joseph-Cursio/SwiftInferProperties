import Foundation
import Testing
@testable import SwiftInferCore

@Suite("EquivalenceClassHint — data model (M11.0)")
struct EquivalenceClassHintTests {

    private static func sampleHint(
        positiveSiteCount: Int = 5,
        negativeSiteCount: Int = 4,
        predicateVeto: PredicateVetoReason? = nil
    ) -> EquivalenceClassHint {
        EquivalenceClassHint(
            predicateName: "isValid",
            argTypeName: "String",
            positiveMarker: "Valid",
            negativeMarker: "Invalid",
            positiveSiteCount: positiveSiteCount,
            negativeSiteCount: negativeSiteCount,
            predicateVeto: predicateVeto,
            suggestedPositiveGenerator: "Gen<String>.string().filter(isValid)",
            suggestedNegativeGenerator: "Gen<String>.string().filter { !isValid($0) }"
        )
    }

    @Test("Equatable conformance compares by value")
    func equatableConformanceMatchesByValue() {
        let first = Self.sampleHint()
        let second = Self.sampleHint()
        let differingSiteCount = Self.sampleHint(positiveSiteCount: 4)
        #expect(first == second)
        #expect(first != differingSiteCount)
    }

    @Test("PredicateVetoReason cases are distinct")
    func predicateVetoReasonEquatableDistinguishesCases() {
        let throwsReason = PredicateVetoReason.predicateThrows
        #expect(throwsReason == PredicateVetoReason.predicateThrows)
        #expect(PredicateVetoReason.predicateThrows != PredicateVetoReason.predicateAsync)
        #expect(PredicateVetoReason.predicateMultiArg != PredicateVetoReason.predicateArgNotGeneratable)
    }

    @Test("predicateVeto field distinguishes otherwise-equal hints")
    func vetoFieldDistinguishesEqualOtherwiseHints() {
        let unvetoed = Self.sampleHint(predicateVeto: nil)
        let vetoedThrows = Self.sampleHint(predicateVeto: .predicateThrows)
        let vetoedAsync = Self.sampleHint(predicateVeto: .predicateAsync)
        #expect(unvetoed != vetoedThrows)
        #expect(vetoedThrows != vetoedAsync)
    }

    @Test("Codable round-trips preserve every field including the veto reason")
    func codableRoundTripPreservesAllFields() throws {
        let originals: [EquivalenceClassHint] = [
            Self.sampleHint(predicateVeto: nil),
            Self.sampleHint(predicateVeto: .predicateThrows),
            Self.sampleHint(predicateVeto: .predicateAsync),
            Self.sampleHint(predicateVeto: .predicateMultiArg),
            Self.sampleHint(predicateVeto: .predicateArgNotGeneratable)
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for original in originals {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(EquivalenceClassHint.self, from: data)
            #expect(decoded == original)
        }
    }

    @Test("Per-bucket site counts are independently surfaced")
    func bucketSiteCountsTrackIndependently() {
        let asymmetric = Self.sampleHint(positiveSiteCount: 7, negativeSiteCount: 3)
        #expect(asymmetric.positiveSiteCount == 7)
        #expect(asymmetric.negativeSiteCount == 3)
    }

    @Test("Both buckets at the M11 ≥3 threshold round-trip cleanly")
    func bothBucketsAtThresholdRoundTrip() throws {
        let atThreshold = Self.sampleHint(positiveSiteCount: 3, negativeSiteCount: 3)
        let data = try JSONEncoder().encode(atThreshold)
        let decoded = try JSONDecoder().decode(EquivalenceClassHint.self, from: data)
        #expect(decoded.positiveSiteCount == 3)
        #expect(decoded.negativeSiteCount == 3)
    }
}
