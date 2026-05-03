import SwiftInferCore
import SwiftInferTemplates
import Testing
@testable import SwiftInferTestLifter

@Suite("LiftedSuggestion + cross-validation-key parity (M1.4)")
struct LiftedSuggestionTests {

    @Test("LiftedSuggestion.roundTrip wraps the detection with a sorted-key")
    func liftedSuggestionWrapsDetection() {
        let detection = DetectedRoundTrip(
            forwardCallee: "encode",
            backwardCallee: "decode",
            inputBindingName: "original",
            recoveredBindingName: "decoded",
            assertionLocation: SourceLocation(file: "X.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.roundTrip(from: detection)
        #expect(lifted.templateName == "round-trip")
        #expect(lifted.crossValidationKey.templateName == "round-trip")
        #expect(lifted.crossValidationKey.calleeNames == ["decode", "encode"])
        #expect(lifted.pattern == .roundTrip(detection))
    }

    @Test("Forward/backward orientation collides to the same key")
    func orientationCollidesToSameKey() {
        let abc = DetectedRoundTrip(
            forwardCallee: "encode",
            backwardCallee: "decode",
            inputBindingName: "x",
            recoveredBindingName: nil,
            assertionLocation: SourceLocation(file: "X.swift", line: 1, column: 1)
        )
        let cba = DetectedRoundTrip(
            forwardCallee: "decode",
            backwardCallee: "encode",
            inputBindingName: "x",
            recoveredBindingName: nil,
            assertionLocation: SourceLocation(file: "X.swift", line: 1, column: 1)
        )
        let liftedA = LiftedSuggestion.roundTrip(from: abc)
        let liftedB = LiftedSuggestion.roundTrip(from: cba)
        #expect(liftedA.crossValidationKey == liftedB.crossValidationKey)
    }

    // MARK: - Load-bearing invariant: TestLifter ↔ TemplateEngine key parity

    /// The M1 acceptance bar's load-bearing invariant: a
    /// LiftedSuggestion derived from a test body's round-trip detection
    /// must produce a CrossValidationKey byte-identical to the
    /// CrossValidationKey of TemplateEngine's RoundTripTemplate
    /// suggestion for the same function pair. This is what makes the
    /// +20 cross-validation signal fire end-to-end.
    @Test("LiftedSuggestion.crossValidationKey matches RoundTripTemplate's for the same pair")
    func liftedKeyMatchesTemplateEngineKey() throws {
        // Production-side: build a function pair (encode/decode) and run
        // it through TemplateEngine's discover.
        let encode = FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: nil, internalName: "value", typeText: "MyData", isInout: false)],
            returnTypeText: "Data",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Codec.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let decode = FunctionSummary(
            name: "decode",
            parameters: [Parameter(label: nil, internalName: "data", typeText: "Data", isInout: false)],
            returnTypeText: "MyData",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Codec.swift", line: 5, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let suggestions = TemplateRegistry.discover(in: [encode, decode])
        let templateEngineRoundTrip = try #require(
            suggestions.first { $0.templateName == "round-trip" }
        )
        let templateEngineKey = templateEngineRoundTrip.crossValidationKey

        // Test-side: simulate what TestLifter would derive from a body
        // like `let encoded = encoder.encode(x); let decoded = decoder.decode(encoded); XCTAssertEqual(x, decoded)`.
        let detection = DetectedRoundTrip(
            forwardCallee: "encode",
            backwardCallee: "decode",
            inputBindingName: "original",
            recoveredBindingName: "decoded",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.roundTrip(from: detection)

        // Load-bearing assertion: the keys collide.
        #expect(lifted.crossValidationKey == templateEngineKey)
    }

    @Test("End-to-end: LiftedSuggestion's key feeds discover and lights up +20")
    func endToEndCrossValidationLightUp() throws {
        let encode = FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: nil, internalName: "value", typeText: "MyData", isInout: false)],
            returnTypeText: "Data",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Codec.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let decode = FunctionSummary(
            name: "decode",
            parameters: [Parameter(label: nil, internalName: "data", typeText: "Data", isInout: false)],
            returnTypeText: "MyData",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Codec.swift", line: 5, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )

        let baseline = TemplateRegistry.discover(in: [encode, decode])
        let baselineRoundTrip = try #require(baseline.first { $0.templateName == "round-trip" })
        let baselineTotal = baselineRoundTrip.score.total

        // Build a lifted suggestion from a synthetic test-side detection
        // and feed its key into discover.
        let detection = DetectedRoundTrip(
            forwardCallee: "encode",
            backwardCallee: "decode",
            inputBindingName: "original",
            recoveredBindingName: "decoded",
            assertionLocation: SourceLocation(file: "T.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.roundTrip(from: detection)
        let liftedKeys: Set<CrossValidationKey> = [lifted.crossValidationKey]

        let crossValidated = TemplateRegistry.discover(
            in: [encode, decode],
            crossValidationFromTestLifter: liftedKeys
        )
        let liftedRoundTrip = try #require(crossValidated.first { $0.templateName == "round-trip" })
        #expect(liftedRoundTrip.score.total == baselineTotal + 20)
        #expect(liftedRoundTrip.score.signals.contains { $0.kind == .crossValidation && $0.weight == 20 })
        #expect(liftedRoundTrip.explainability.whySuggested.contains { $0.contains("Cross-validated by TestLifter") })
    }

    @Test("Mismatched callee names produce different keys (no false +20)")
    func unrelatedKeysDoNotCollide() {
        let mineKey = LiftedSuggestion.roundTrip(from: DetectedRoundTrip(
            forwardCallee: "encode",
            backwardCallee: "decode",
            inputBindingName: "x",
            recoveredBindingName: nil,
            assertionLocation: SourceLocation(file: "X.swift", line: 1, column: 1)
        )).crossValidationKey
        let otherKey = LiftedSuggestion.roundTrip(from: DetectedRoundTrip(
            forwardCallee: "serialize",
            backwardCallee: "deserialize",
            inputBindingName: "x",
            recoveredBindingName: nil,
            assertionLocation: SourceLocation(file: "X.swift", line: 1, column: 1)
        )).crossValidationKey
        #expect(mineKey != otherKey)
    }
}

@Suite("Suggestion.crossValidationKey — name extraction (M1.4)")
struct SuggestionCrossValidationKeyTests {

    @Test("crossValidationKey strips the (labels:) suffix from displayName")
    func stripsLabelSuffix() {
        let suggestion = Suggestion(
            templateName: "round-trip",
            evidence: [
                Evidence(
                    displayName: "encode(_:)",
                    signature: "(MyData) -> Data",
                    location: SourceLocation(file: "X.swift", line: 1, column: 1)
                ),
                Evidence(
                    displayName: "decode(_:)",
                    signature: "(Data) -> MyData",
                    location: SourceLocation(file: "X.swift", line: 5, column: 1)
                )
            ],
            score: Score(signals: []),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "round-trip|x|y")
        )
        #expect(suggestion.crossValidationKey.calleeNames == ["decode", "encode"])
    }

    @Test("displayName without parens is preserved")
    func preservesParenlessDisplayName() {
        let suggestion = Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "normalize",
                    signature: "(String) -> String",
                    location: SourceLocation(file: "X.swift", line: 1, column: 1)
                )
            ],
            score: Score(signals: []),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "idempotence|x")
        )
        #expect(suggestion.crossValidationKey.calleeNames == ["normalize"])
    }
}
