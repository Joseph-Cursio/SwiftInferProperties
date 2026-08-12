import SwiftInferCore
@testable import SwiftInferTestLifter
import Testing

/// Where a lifted law says it came from (CLAUDE.md §7.4).
///
/// `Slicer.location(of:)` carries no `SourceLocationConverter` and emits `<test-body>:0`. The
/// recorded decision is to fall back to `LiftedOrigin` rather than thread a converter through
/// six detectors — and that fallback reached RENDERING only, so `provenanceLine()` printed a
/// real path while `evidence.location` kept the placeholder. Every lifted entry indexed as
/// `location: "<test-body>:0"`, which is a row a reader cannot audit and, per §7.4, is how a
/// package-wide lifting defect stayed hidden.
///
/// **`corpusLevelFindingKeepsItsPlaceholder` is the arm that constrains the fix.** Two
/// placeholders mean different things: `<test-body>` is *one assertion whose line we could not
/// compute*, where the origin is a strictly better answer, while `<corpus>` is *no single site
/// is canonical*, where naming one test would be false rather than imprecise — and
/// `isResolvable` would then report that falsehood as trustworthy provenance.
@Suite("Lifted evidence carries a location a reader can open")
struct LiftedEvidenceLocationTests {

    private var origin: LiftedOrigin {
        LiftedOrigin(
            testMethodName: "normalisingIsIdempotent",
            sourceLocation: SourceLocation(file: "ConfigPropertyTests.swift", line: 132, column: 5)
        )
    }

    private func idempotenceLifted() -> LiftedSuggestion {
        LiftedSuggestion.idempotence(
            from: DetectedIdempotence(
                calleeName: "normalized",
                inputBindingName: "source",
                // What the slicer really produces.
                assertionLocation: .testBodyPlaceholder
            )
        )
    }

    @Test("the placeholder is replaced by the test method's real file and line")
    func placeholderResolvesToTheOrigin() {
        let suggestion = idempotenceLifted().toSuggestion(typeName: "String", origin: origin)
        let location = suggestion.evidence[0].location

        #expect(location == origin.sourceLocation)
        #expect(location.isResolvable)
        #expect(location.file == "ConfigPropertyTests.swift")
        #expect(location.line == 132)
    }

    @Test("with no origin the placeholder stays — an honest unknown beats a wrong path")
    func absentOriginLeavesThePlaceholder() {
        let suggestion = idempotenceLifted().toSuggestion(typeName: "String", origin: nil)

        #expect(suggestion.evidence[0].location == .testBodyPlaceholder)
        #expect(!suggestion.evidence[0].location.isResolvable)
    }

    @Test("an unresolvable origin is not substituted either")
    func unresolvableOriginIsIgnored() {
        let bad = LiftedOrigin(
            testMethodName: "t", sourceLocation: SourceLocation(file: "<unknown>", line: 0, column: 0)
        )
        let suggestion = idempotenceLifted().toSuggestion(typeName: "String", origin: bad)

        #expect(suggestion.evidence[0].location == .testBodyPlaceholder)
    }

    @Test("a detector that DID compute a location keeps it — the origin is a fallback, not an override")
    func realDetectorLocationSurvives() {
        // The origin names the test METHOD; a detector location names the assertion, which is
        // more precise. Preferring the origin would lose precision for every detector that
        // has a converter, so the substitution must be one-way.
        let precise = SourceLocation(file: "CodecTests.swift", line: 12, column: 5)
        let lifted = LiftedSuggestion.idempotence(
            from: DetectedIdempotence(
                calleeName: "normalize", inputBindingName: "raw", assertionLocation: precise
            )
        )
        let suggestion = lifted.toSuggestion(typeName: "String", origin: origin)

        #expect(suggestion.evidence[0].location == precise)
    }

    @Test("a corpus-level finding keeps `<corpus>` even when an origin is available")
    func corpusLevelFindingKeepsItsPlaceholder() {
        // The discriminating arm. An equivalence-class hint is aggregated across many test
        // bodies; resolving it to one of them would name a site the finding is not anchored
        // at. `corpusLevelEvidence` takes no fallback, so this is structural rather than a
        // convention someone must remember.
        let lifted = LiftedSuggestion.equivalenceClass(
            hint: EquivalenceClassHint(
                predicateName: "isValid",
                argTypeName: "Payload",
                positiveMarker: "valid",
                negativeMarker: "invalid",
                positiveSiteCount: 3,
                negativeSiteCount: 2,
                predicateVeto: nil,
                suggestedPositiveGenerator: "",
                suggestedNegativeGenerator: ""
            )
        )
        let suggestion = lifted.toSuggestion(typeName: "Payload", origin: origin)

        #expect(suggestion.evidence[0].location.file == "<corpus>")
        #expect(!suggestion.evidence[0].location.isResolvable)
    }
}
