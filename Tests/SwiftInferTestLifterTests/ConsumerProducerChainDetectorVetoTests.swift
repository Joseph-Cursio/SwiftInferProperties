import Testing
import SwiftInferCore
@testable import SwiftInferTestLifter

@Suite("ConsumerProducerChainDetector — producer veto + edge cases (M16.1)")
struct ConsumerProducerChainDetectorVetoTests {

    private typealias Fixtures = ConsumerProducerChainDetectorFixtures

    // MARK: - Producer veto checks (reused from M10)

    @Test("Throws producer surfaces as advisory with `.producerThrows` veto")
    func throwsProducerSurfacesAdvisoryVeto() throws {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": Fixtures.sites(count: 3)],
            summariesByName: [
                "format": Fixtures.formatProducer(isThrows: true),
                "validate": Fixtures.validateConsumer()
            ],
            knownRoundTripPairs: []
        )
        let hint = try #require(hints.first)
        #expect(hint.producerVeto == .producerThrows)
    }

    @Test("Async producer surfaces as advisory with `.producerAsync` veto")
    func asyncProducerSurfacesAdvisoryVeto() throws {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": Fixtures.sites(count: 3)],
            summariesByName: [
                "format": Fixtures.formatProducer(isAsync: true),
                "validate": Fixtures.validateConsumer()
            ],
            knownRoundTripPairs: []
        )
        let hint = try #require(hints.first)
        #expect(hint.producerVeto == .producerAsync)
    }

    @Test("Multi-arg producer surfaces as advisory with `.producerMultiArg` veto")
    func multiArgProducerSurfacesAdvisoryVeto() throws {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": Fixtures.sites(count: 3)],
            summariesByName: [
                "format": Fixtures.formatProducer(parameterCount: 2),
                "validate": Fixtures.validateConsumer()
            ],
            knownRoundTripPairs: []
        )
        let hint = try #require(hints.first)
        #expect(hint.producerVeto == .producerMultiArg)
    }

    @Test("Non-generatable producer arg surfaces as advisory with `.producerArgNotGeneratable` veto")
    func nonGeneratableProducerArgSurfacesAdvisoryVeto() throws {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: ["validate": Fixtures.sites(count: 3)],
            summariesByName: [
                "format": Fixtures.formatProducer(),
                "validate": Fixtures.validateConsumer()
            ],
            knownRoundTripPairs: []
        ) { _ in false }
        let hint = try #require(hints.first)
        #expect(hint.producerVeto == .producerArgNotGeneratable)
    }

    // MARK: - Empty / missing edge cases (PRD §15)

    @Test("Empty corpus map emits no hint")
    func emptyCorpusMapNoHint() {
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: [:],
            summariesByName: ["format": Fixtures.formatProducer()],
            knownRoundTripPairs: []
        )
        #expect(hints.isEmpty)
    }

    @Test("Multiple qualifying chains all surface; output is deterministic by consumer name")
    func multipleChainsAreDeterministic() throws {
        let consumerB = FunctionSummary(
            name: "verify",
            parameters: [Parameter(label: nil, internalName: "s", typeText: "String", isInout: false)],
            returnTypeText: "Bool",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Verify.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let hints = ConsumerProducerChainDetector.detect(
            callSitesByConsumer: [
                "validate": Fixtures.sites(count: 3),
                "verify": Fixtures.sites(count: 4)
            ],
            summariesByName: [
                "format": Fixtures.formatProducer(),
                "validate": Fixtures.validateConsumer(),
                "verify": consumerB
            ],
            knownRoundTripPairs: []
        )
        #expect(hints.count == 2)
        // Sorted by consumer name: "validate" before "verify".
        #expect(hints[0].reverseName == "validate")
        #expect(hints[1].reverseName == "verify")
        #expect(hints[1].siteCount == 4)
    }
}
