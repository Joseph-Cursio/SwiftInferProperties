import Testing
import SwiftInferCore
import SwiftInferTestLifter
@testable import SwiftInferCLI

@Suite("LiftedSuggestionPipeline — M10.3 domain inference pass")
struct DomainInferencePipelineTests {

    // MARK: - Fixtures

    /// Build a round-trip Suggestion with a populated MockGenerator —
    /// the input shape M10.3 expects to receive after the M4.3 mock
    /// fallback pass has fired.
    private static func roundTripSuggestionWithMockGenerator(
        forwardName: String,
        reverseName: String,
        mockTypeName: String
    ) -> Suggestion {
        let forward = Evidence(
            displayName: "\(forwardName)(_:)",
            signature: "(\(mockTypeName)) -> Data",
            location: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let reverse = Evidence(
            displayName: "\(reverseName)(_:)",
            signature: "(Data) -> \(mockTypeName)",
            location: SourceLocation(file: "T.swift", line: 5, column: 1)
        )
        let mock = MockGenerator(
            typeName: mockTypeName,
            argumentSpec: [],
            siteCount: 5
        )
        return Suggestion(
            templateName: "round-trip",
            evidence: [forward, reverse],
            score: Score(signals: [Signal(kind: .typeSymmetrySignature, weight: 90, detail: "")]),
            generator: GeneratorMetadata(
                source: .inferredFromTests,
                confidence: .low,
                sampling: .notRun
            ),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "round-trip|\(forwardName)|\(reverseName)"),
            mockGenerator: mock
        )
    }

    private static func unaryNonThrowingSummary(name: String) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "p", typeText: "MyType", isInout: false)],
            returnTypeText: "Data",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Codec.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
    }

    private static func directSites(_ count: Int, producer: String = "encode") -> [DomainCallSite] {
        (0..<count).map { _ in
            DomainCallSite(argument: .callOutput(producerName: producer))
        }
    }

    // MARK: - Pipeline behavior

    @Test("Empty domainCallSitesByConsumer is a no-op (mockGenerator.domainHint stays nil)")
    func emptyMapNoOp() {
        let suggestion = Self.roundTripSuggestionWithMockGenerator(
            forwardName: "encode",
            reverseName: "decode",
            mockTypeName: "MyType"
        )
        let result = LiftedSuggestionPipeline.applyDomainInferenceForTesting(
            to: [suggestion],
            summariesByName: ["encode": Self.unaryNonThrowingSummary(name: "encode")],
            domainCallSitesByConsumer: [:]
        )
        #expect(result.first?.mockGenerator?.domainHint == nil)
    }

    @Test("Round-trip with 5 homogeneous sites populates an unvetoed domain hint")
    func homogeneousSitesPopulateHint() throws {
        let suggestion = Self.roundTripSuggestionWithMockGenerator(
            forwardName: "encode",
            reverseName: "decode",
            mockTypeName: "MyType"
        )
        let result = LiftedSuggestionPipeline.applyDomainInferenceForTesting(
            to: [suggestion],
            summariesByName: ["encode": Self.unaryNonThrowingSummary(name: "encode")],
            domainCallSitesByConsumer: ["decode": Self.directSites(5)]
        )
        let hint = try #require(result.first?.mockGenerator?.domainHint)
        #expect(hint.forwardName == "encode")
        #expect(hint.reverseName == "decode")
        #expect(hint.siteCount == 5)
        #expect(hint.producerVeto == nil)
        #expect(hint.suggestedGenerator == "Gen<MyType>.map(encode)")
    }

    @Test("Throwing forward function surfaces hint with .producerThrows veto")
    func throwingForwardSurfacesVetoedHint() throws {
        let suggestion = Self.roundTripSuggestionWithMockGenerator(
            forwardName: "encode",
            reverseName: "decode",
            mockTypeName: "MyType"
        )
        let throwingSummary = FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: nil, internalName: "p", typeText: "MyType", isInout: false)],
            returnTypeText: "Data",
            isThrows: true,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Codec.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let result = LiftedSuggestionPipeline.applyDomainInferenceForTesting(
            to: [suggestion],
            summariesByName: ["encode": throwingSummary],
            domainCallSitesByConsumer: ["decode": Self.directSites(5)]
        )
        let hint = try #require(result.first?.mockGenerator?.domainHint)
        #expect(hint.producerVeto == .producerThrows)
    }

    @Test("Below-threshold corpus (2 sites) doesn't populate a hint")
    func belowThresholdNoHint() {
        let suggestion = Self.roundTripSuggestionWithMockGenerator(
            forwardName: "encode",
            reverseName: "decode",
            mockTypeName: "MyType"
        )
        let result = LiftedSuggestionPipeline.applyDomainInferenceForTesting(
            to: [suggestion],
            summariesByName: ["encode": Self.unaryNonThrowingSummary(name: "encode")],
            domainCallSitesByConsumer: ["decode": Self.directSites(2)]
        )
        #expect(result.first?.mockGenerator?.domainHint == nil)
    }

    @Test("Non-round-trip suggestions are unaffected")
    func nonRoundTripUnaffected() {
        let mock = MockGenerator(typeName: "MyType", argumentSpec: [], siteCount: 5)
        let idempotent = Suggestion(
            templateName: "idempotence",
            evidence: [Evidence(
                displayName: "normalize(_:)",
                signature: "(MyType) -> MyType",
                location: SourceLocation(file: "T.swift", line: 1, column: 1)
            )],
            score: Score(signals: [Signal(kind: .typeSymmetrySignature, weight: 60, detail: "")]),
            generator: GeneratorMetadata(source: .inferredFromTests, confidence: .low, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "idempotence|normalize"),
            mockGenerator: mock
        )
        let result = LiftedSuggestionPipeline.applyDomainInferenceForTesting(
            to: [idempotent],
            summariesByName: [:],
            domainCallSitesByConsumer: ["decode": Self.directSites(5)]
        )
        #expect(result.first?.mockGenerator?.domainHint == nil)
    }
}
