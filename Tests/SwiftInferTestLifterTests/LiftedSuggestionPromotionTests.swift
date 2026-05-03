import SwiftInferCore
import Testing
@testable import SwiftInferTestLifter

@Suite("LiftedSuggestion → Suggestion promotion (M3.0)")
struct LiftedSuggestionPromotionTests {

    // MARK: - Acceptance case (i): round-trip with both types known

    @Test("Round-trip promotion produces two-element evidence with forward + backward signatures")
    func roundTripPromotionEvidenceShape() {
        let detection = DetectedRoundTrip(
            forwardCallee: "encode",
            backwardCallee: "decode",
            inputBindingName: "original",
            recoveredBindingName: "decoded",
            assertionLocation: SourceLocation(file: "CodecTests.swift", line: 12, column: 5)
        )
        let lifted = LiftedSuggestion.roundTrip(from: detection)

        let suggestion = lifted.toSuggestion(typeName: "Int", returnType: "String")

        #expect(suggestion.templateName == "round-trip")
        #expect(suggestion.evidence.count == 2)
        #expect(suggestion.evidence[0].displayName == "encode(_:)")
        #expect(suggestion.evidence[0].signature == "(Int) -> String")
        #expect(suggestion.evidence[1].displayName == "decode(_:)")
        #expect(suggestion.evidence[1].signature == "(String) -> Int")
        // Both halves carry the assertion source location — lifted
        // evidence's "location" is the test body, not a function decl.
        #expect(suggestion.evidence[0].location == detection.assertionLocation)
        #expect(suggestion.evidence[1].location == detection.assertionLocation)
    }

    // MARK: - Acceptance case (ii): idempotence with typeName known

    @Test("Idempotence promotion produces (T) -> T evidence when typeName supplied")
    func idempotencePromotionEvidenceShape() {
        let detection = DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "raw",
            assertionLocation: SourceLocation(file: "NormalizerTests.swift", line: 7, column: 9)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)

        let suggestion = lifted.toSuggestion(typeName: "String")

        #expect(suggestion.templateName == "idempotence")
        #expect(suggestion.evidence.count == 1)
        #expect(suggestion.evidence[0].displayName == "normalize(_:)")
        #expect(suggestion.evidence[0].signature == "(String) -> String")
        #expect(suggestion.evidence[0].location == detection.assertionLocation)
    }

    // MARK: - Acceptance case (iii): commutativity with typeName known

    @Test("Commutativity promotion produces (T, T) -> T evidence when typeName supplied")
    func commutativityPromotionEvidenceShape() {
        let detection = DetectedCommutativity(
            calleeName: "merge",
            leftArgName: "a",
            rightArgName: "b",
            assertionLocation: SourceLocation(file: "MergeTests.swift", line: 22, column: 9)
        )
        let lifted = LiftedSuggestion.commutativity(from: detection)

        let suggestion = lifted.toSuggestion(typeName: "Int")

        #expect(suggestion.templateName == "commutativity")
        #expect(suggestion.evidence.count == 1)
        #expect(suggestion.evidence[0].displayName == "merge(_:_:)")
        #expect(suggestion.evidence[0].signature == "(Int, Int) -> Int")
        #expect(suggestion.evidence[0].location == detection.assertionLocation)
    }

    // MARK: - Acceptance case (iv): typeName: nil fallback

    @Test("typeName: nil fallback synthesizes (?) -> ? evidence and leaves generator at .notYetComputed")
    func nilTypeFallbackProducesSentinelSignature() {
        let detection = DetectedIdempotence(
            calleeName: "canonicalize",
            inputBindingName: "raw",
            assertionLocation: SourceLocation(file: "Test.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)

        let suggestion = lifted.toSuggestion(typeName: nil)

        #expect(suggestion.evidence[0].signature == "(?) -> ?")
        // M3.0 leaves generator selection to the M3.1 GeneratorSelection
        // pass — promotion adapter always emits the placeholder.
        #expect(suggestion.generator.source == .notYetComputed)
        #expect(suggestion.generator.confidence == nil)
    }

    @Test("Round-trip nil-type fallback uses (?) on both halves")
    func roundTripNilTypeFallback() {
        let detection = DetectedRoundTrip(
            forwardCallee: "wrap",
            backwardCallee: "unwrap",
            inputBindingName: "x",
            recoveredBindingName: nil,
            assertionLocation: SourceLocation(file: "Test.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.roundTrip(from: detection)

        let suggestion = lifted.toSuggestion(typeName: nil, returnType: nil)

        #expect(suggestion.evidence[0].signature == "(?) -> ?")
        #expect(suggestion.evidence[1].signature == "(?) -> ?")
    }

    // MARK: - Score / signal shape

    @Test("Promoted suggestion carries exactly one +50 testBodyPattern signal")
    func promotedSuggestionScoreShape() {
        let detection = DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "s",
            assertionLocation: SourceLocation(file: "Test.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)

        let suggestion = lifted.toSuggestion(typeName: "String")

        #expect(suggestion.score.signals.count == 1)
        let signal = suggestion.score.signals[0]
        #expect(signal.kind == .testBodyPattern)
        #expect(signal.weight == 50)
        // PRD §4.1 +50 row — lifted-only suggestion lands at ~Likely
        // tier (M3 plan open decision #5 default `(a)` — natural ~50
        // landing, no synthesized structural base).
        #expect(suggestion.score.total == 50)
        #expect(suggestion.score.tier == .likely)
        #expect(!suggestion.score.isVetoed)
    }

    // MARK: - Identity namespacing

    @Test("Lifted identity uses the lifted| prefix to namespace away from TemplateEngine identities")
    func liftedIdentityNamespace() {
        let detection = DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "s",
            assertionLocation: SourceLocation(file: "Test.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)

        let suggestion = lifted.toSuggestion(typeName: "String")

        #expect(suggestion.identity.canonicalInput == "lifted|idempotence|normalize")
    }

    @Test("Lifted round-trip identity sorts callee names lexicographically (matches CrossValidationKey)")
    func liftedRoundTripIdentitySortedCallees() {
        let abc = DetectedRoundTrip(
            forwardCallee: "encode",
            backwardCallee: "decode",
            inputBindingName: "x",
            recoveredBindingName: nil,
            assertionLocation: SourceLocation(file: "Test.swift", line: 1, column: 1)
        )
        let cba = DetectedRoundTrip(
            forwardCallee: "decode",
            backwardCallee: "encode",
            inputBindingName: "x",
            recoveredBindingName: nil,
            assertionLocation: SourceLocation(file: "Test.swift", line: 1, column: 1)
        )
        let liftedABC = LiftedSuggestion.roundTrip(from: abc).toSuggestion(typeName: "Int", returnType: "String")
        let liftedCBA = LiftedSuggestion.roundTrip(from: cba).toSuggestion(typeName: "String", returnType: "Int")

        // Both orientations share the identity (canonical input is sorted-callees).
        #expect(liftedABC.identity == liftedCBA.identity)
        #expect(liftedABC.identity.canonicalInput == "lifted|round-trip|decode,encode")
    }

    // MARK: - LiftedOrigin plumbing (M3.0 plumbs the parameter; M3.1 populates it)

    @Test("Origin parameter defaults to nil and threads through when supplied")
    func originPlumbing() {
        let detection = DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "s",
            assertionLocation: SourceLocation(file: "Test.swift", line: 1, column: 1)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)

        let withoutOrigin = lifted.toSuggestion(typeName: "String")
        #expect(withoutOrigin.liftedOrigin == nil)

        let origin = LiftedOrigin(
            testMethodName: "testNormalizeIsIdempotent",
            sourceLocation: SourceLocation(file: "NormalizerTests.swift", line: 5, column: 5)
        )
        let withOrigin = lifted.toSuggestion(typeName: "String", origin: origin)
        #expect(withOrigin.liftedOrigin == origin)
        #expect(withOrigin.liftedOrigin?.testMethodName == "testNormalizeIsIdempotent")
    }

    // MARK: - TemplateEngine-originated suggestions remain unchanged

    @Test("TemplateEngine-originated Suggestion init defaults liftedOrigin to nil (no breaking change)")
    func templateEngineSuggestionDefaultLiftedOriginNil() {
        let suggestion = Suggestion(
            templateName: "idempotence",
            evidence: [
                Evidence(
                    displayName: "f(_:)",
                    signature: "(Int) -> Int",
                    location: SourceLocation(file: "F.swift", line: 1, column: 1)
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 25, detail: "")]),
            generator: .m1Placeholder,
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "idempotence|f(_:)|(Int)->Int")
        )
        #expect(suggestion.liftedOrigin == nil)
    }

    // MARK: - Explainability (provenance lines)

    @Test("Explainability block carries the assertion shape + lifted-from line")
    func explainabilityBlockShape() {
        let detection = DetectedIdempotence(
            calleeName: "normalize",
            inputBindingName: "raw",
            assertionLocation: SourceLocation(file: "NormalizerTests.swift", line: 7, column: 9)
        )
        let lifted = LiftedSuggestion.idempotence(from: detection)

        let suggestion = lifted.toSuggestion(typeName: "String")

        #expect(suggestion.explainability.whySuggested.count == 2)
        #expect(suggestion.explainability.whySuggested[0]
            == "Test body asserts normalize(normalize(raw)) == normalize(raw)")
        #expect(suggestion.explainability.whySuggested[1]
            == "Lifted from NormalizerTests.swift:7")
        #expect(suggestion.explainability.whyMightBeWrong.isEmpty)
    }
}
