import SwiftInferCore
@testable import SwiftInferTestLifter
import Testing

@Suite("ConsumerProducerChainDetector — five-criterion narrow scope (M16.1)")
struct ConsumerProducerChainDetectorTests {

    private typealias Fixtures = ConsumerProducerChainDetectorFixtures

    // MARK: - Threshold

    @Test("Below threshold (2 sites) emits no hint")
    func belowThresholdNoHint() {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": Fixtures.sites(count: 2)],
            summariesByName: [
                "format": Fixtures.formatProducer(),
                "validate": Fixtures.validateConsumer()
            ],
            knownRoundTripPairs: []
        )
        #expect(hints.isEmpty)
    }

    @Test("At threshold (3 sites) emits an unvetoed advisory hint")
    func atThresholdHomogeneousHintFires() throws {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": Fixtures.sites(count: 3)],
            summariesByName: [
                "format": Fixtures.formatProducer(),
                "validate": Fixtures.validateConsumer()
            ],
            knownRoundTripPairs: []
        )
        #expect(hints.count == 1)
        let hint = try #require(hints.first)
        #expect(hint.origin == .consumerProducerChain)
        #expect(hint.forwardName == "format")
        #expect(hint.reverseName == "validate")
        #expect(hint.producerName == "format")
        #expect(hint.domainTypeName == "String")
        #expect(hint.siteCount == 3)
        #expect(hint.producerVeto == nil)
        #expect(hint.suggestedGenerator == "Gen<String>.map(format)")
    }

    // MARK: - Homogeneity

    @Test("Mixed-producer chain (one outlier kills) emits no hint")
    func mixedProducerNoHint() {
        var sites = Fixtures.sites(count: 3, producer: "format")
        sites.append(DomainCallSite(argument: .callOutput(producerName: "stringify")))
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": sites],
            summariesByName: [
                "format": Fixtures.formatProducer(),
                "stringify": Fixtures.formatProducer(name: "stringify"),
                "validate": Fixtures.validateConsumer()
            ],
            knownRoundTripPairs: []
        )
        #expect(hints.isEmpty)
    }

    @Test("Identifier-classified site (unresolved) kills homogeneity")
    func unresolvedIdentifierKillsHomogeneity() {
        var sites = Fixtures.sites(count: 3, producer: "format")
        sites[1] = DomainCallSite(argument: .identifier(name: "x"))
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": sites],
            summariesByName: [
                "format": Fixtures.formatProducer(),
                "validate": Fixtures.validateConsumer()
            ],
            knownRoundTripPairs: []
        )
        #expect(hints.isEmpty)
    }

    @Test("`.other` site kills homogeneity")
    func otherSiteKillsHomogeneity() {
        var sites = Fixtures.sites(count: 3, producer: "format")
        sites[0] = DomainCallSite(argument: .other)
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": sites],
            summariesByName: [
                "format": Fixtures.formatProducer(),
                "validate": Fixtures.validateConsumer()
            ],
            knownRoundTripPairs: []
        )
        #expect(hints.isEmpty)
    }

    // MARK: - Producer existence

    @Test("Producer not in summaries (stdlib initializer) emits no hint")
    func producerNotInSummariesNoHint() {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": Fixtures.sites(count: 3, producer: "String")],
            summariesByName: ["validate": Fixtures.validateConsumer()],
            knownRoundTripPairs: []
        )
        #expect(hints.isEmpty)
    }

    // MARK: - Type alignment

    @Test("Producer return-type mismatch kills the chain")
    func producerReturnTypeMismatchNoHint() {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": Fixtures.sites(count: 3)],
            summariesByName: [
                "format": Fixtures.formatProducer(returnTypeText: "Data"),
                "validate": Fixtures.validateConsumer(argTypeText: "String")
            ],
            knownRoundTripPairs: []
        )
        #expect(hints.isEmpty)
    }

    @Test("Implicit-Void producer return type kills the chain")
    func implicitVoidProducerNoHint() {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": Fixtures.sites(count: 3)],
            summariesByName: [
                "format": Fixtures.formatProducer(returnTypeText: nil),
                "validate": Fixtures.validateConsumer()
            ],
            knownRoundTripPairs: []
        )
        #expect(hints.isEmpty)
    }

    @Test("Consumer not in summaries (no first-arg type) emits no hint")
    func consumerNotInSummariesNoHint() {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": Fixtures.sites(count: 3)],
            summariesByName: ["format": Fixtures.formatProducer()],
            knownRoundTripPairs: []
        )
        #expect(hints.isEmpty)
    }

    // MARK: - Anti-double-fire with M10

    @Test("M5 round-trip pair (forward: producer, reverse: consumer) suppresses the chain")
    func m5RoundTripPairSuppressesChain() {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": Fixtures.sites(count: 3)],
            summariesByName: [
                "format": Fixtures.formatProducer(),
                "validate": Fixtures.validateConsumer()
            ],
            knownRoundTripPairs: [
                RoundTripPair(forwardName: "format", reverseName: "validate", domainTypeName: "String")
            ]
        )
        #expect(hints.isEmpty)
    }

    @Test("Unrelated round-trip pair does not suppress the chain")
    func unrelatedRoundTripPairDoesNotSuppress() {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": Fixtures.sites(count: 3)],
            summariesByName: [
                "format": Fixtures.formatProducer(),
                "validate": Fixtures.validateConsumer()
            ],
            knownRoundTripPairs: [
                RoundTripPair(forwardName: "encode", reverseName: "decode", domainTypeName: "Other")
            ]
        )
        #expect(hints.count == 1)
    }
}
