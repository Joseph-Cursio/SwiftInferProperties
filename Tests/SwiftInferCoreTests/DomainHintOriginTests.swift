@testable import SwiftInferCore
import Testing

@Suite("DomainHint.origin — provenance discriminator (M16.0)")
struct DomainHintOriginTests {

    private static func makeHint(origin: HintOrigin) -> DomainHint {
        DomainHint(
            forwardName: "format",
            reverseName: "validate",
            producerName: "format",
            domainTypeName: "Doc",
            siteCount: 4,
            producerVeto: nil,
            suggestedGenerator: "Gen<Doc>.gen().map(format)",
            origin: origin
        )
    }

    @Test
    func defaultOriginIsRoundTripPair() {
        let hint = DomainHint(
            forwardName: "encode",
            reverseName: "decode",
            producerName: "encode",
            domainTypeName: "MyType",
            siteCount: 3,
            producerVeto: nil,
            suggestedGenerator: "Gen<MyType>.map(encode)"
        )
        #expect(hint.origin == .roundTripPair)
    }

    @Test
    func explicitOriginIsCarriedThroughInitializer() {
        let hint = Self.makeHint(origin: .consumerProducerChain)
        #expect(hint.origin == .consumerProducerChain)
    }

    @Test
    func equatabilityDistinguishesByOrigin() {
        let roundTrip = Self.makeHint(origin: .roundTripPair)
        let chain = Self.makeHint(origin: .consumerProducerChain)
        #expect(roundTrip != chain)
    }

    @Test
    func equatabilityMatchesOnEqualOrigin() {
        let lhs = Self.makeHint(origin: .consumerProducerChain)
        let rhs = Self.makeHint(origin: .consumerProducerChain)
        #expect(lhs == rhs)
    }

    @Test
    func hintOriginEnumDistinguishesItsCases() {
        let roundTrip = HintOrigin.roundTripPair
        #expect(roundTrip == HintOrigin.roundTripPair)
        #expect(HintOrigin.roundTripPair != HintOrigin.consumerProducerChain)
    }
}
