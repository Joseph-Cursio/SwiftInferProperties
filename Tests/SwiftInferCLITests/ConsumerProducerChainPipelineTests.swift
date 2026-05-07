import Testing
import SwiftInferCore
import SwiftInferTestLifter
@testable import SwiftInferCLI

@Suite("LiftedSuggestionPipeline — M16.2 consumer-producer chain advisory wiring")
struct ConsumerProducerChainPipelineTests {

    // MARK: - Fixtures

    private static func formatProducer(
        isThrows: Bool = false,
        returnTypeText: String? = "String"
    ) -> FunctionSummary {
        FunctionSummary(
            name: "format",
            parameters: [Parameter(label: nil, internalName: "doc", typeText: "Doc", isInout: false)],
            returnTypeText: returnTypeText,
            isThrows: isThrows,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Format.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    private static func validateConsumer() -> FunctionSummary {
        FunctionSummary(
            name: "validate",
            parameters: [Parameter(label: nil, internalName: "s", typeText: "String", isInout: false)],
            returnTypeText: "Bool",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Validate.swift", line: 10, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    private static func sites(count: Int, producer: String = "format") -> [DomainCallSite] {
        (0..<count).map { _ in DomainCallSite(argument: .callOutput(producerName: producer)) }
    }

    // MARK: - Pipeline behavior

    @Test("Empty domainCallSitesByConsumer produces no chain advisory")
    func emptyCorpusMapNoChainAdvisory() {
        let result = LiftedSuggestionPipeline.promote(
            lifted: [],
            templateEngineSuggestions: [],
            summaries: [Self.formatProducer(), Self.validateConsumer()],
            typeDecls: [],
            domainCallSitesByConsumer: [:]
        )
        #expect(result.isEmpty)
    }

    @Test("3-site homogeneous chain surfaces an advisory `consumer-producer-chain` suggestion")
    func homogeneousChainSurfacesAdvisorySuggestion() throws {
        let result = LiftedSuggestionPipeline.promote(
            lifted: [],
            templateEngineSuggestions: [],
            summaries: [Self.formatProducer(), Self.validateConsumer()],
            typeDecls: [],
            domainCallSitesByConsumer: ["validate": Self.sites(count: 3)]
        )
        #expect(result.count == 1)
        let suggestion = try #require(result.first)
        #expect(suggestion.templateName == "consumer-producer-chain")
        #expect(suggestion.score.tier == .advisory)
        #expect(suggestion.evidence.count == 1)
        #expect(suggestion.evidence.first?.displayName == "validate(_:)")
    }

    @Test("Throws producer surfaces advisory with veto reason in explainability")
    func throwsProducerSurfacesAdvisoryWithVeto() throws {
        let result = LiftedSuggestionPipeline.promote(
            lifted: [],
            templateEngineSuggestions: [],
            summaries: [Self.formatProducer(isThrows: true), Self.validateConsumer()],
            typeDecls: [],
            domainCallSitesByConsumer: ["validate": Self.sites(count: 3)]
        )
        let suggestion = try #require(result.first)
        #expect(suggestion.score.tier == .advisory)
        let whySuggested = suggestion.explainability.whySuggested.joined(separator: "\n")
        #expect(whySuggested.contains("Generator narrowing skipped"))
    }

    @Test("Anti-double-fire: M5 round-trip pair (forward: producer, reverse: consumer) suppresses the chain")
    func roundTripPairAntiDoubleFire() {
        // Use the lifted-side round-trip detection to populate the
        // anti-double-fire input. The chain detector consults the
        // pipeline's derived round-trip pair set.
        let roundTripDetection = DetectedRoundTrip(
            forwardCallee: "format",
            backwardCallee: "validate",
            inputBindingName: "doc",
            recoveredBindingName: nil,
            assertionLocation: SourceLocation(file: "ValidateTests.swift", line: 5, column: 1)
        )
        let liftedRoundTrip = LiftedSuggestion.roundTrip(
            from: roundTripDetection,
            origin: LiftedOrigin(
                testMethodName: "test_validate_format_round_trip",
                sourceLocation: SourceLocation(file: "ValidateTests.swift", line: 1, column: 1)
            )
        )
        let result = LiftedSuggestionPipeline.promote(
            lifted: [liftedRoundTrip],
            templateEngineSuggestions: [],
            summaries: [Self.formatProducer(), Self.validateConsumer()],
            typeDecls: [],
            domainCallSitesByConsumer: ["validate": Self.sites(count: 3)]
        )
        // No consumer-producer-chain suggestion should be emitted —
        // M10 owns the round-trip surface.
        let chainSuggestions = result.filter { $0.templateName == "consumer-producer-chain" }
        #expect(chainSuggestions.isEmpty)
    }

    @Test("Below-threshold sites produce no chain advisory")
    func belowThresholdNoAdvisory() {
        let result = LiftedSuggestionPipeline.promote(
            lifted: [],
            templateEngineSuggestions: [],
            summaries: [Self.formatProducer(), Self.validateConsumer()],
            typeDecls: [],
            domainCallSitesByConsumer: ["validate": Self.sites(count: 2)]
        )
        let chainSuggestions = result.filter { $0.templateName == "consumer-producer-chain" }
        #expect(chainSuggestions.isEmpty)
    }
}
