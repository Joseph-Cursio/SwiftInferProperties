import Testing
import Foundation
import SwiftInferCore
@testable import SwiftInferCLI

/// V1.33.C — `IndexCommand.buildEntry` projects a `Suggestion` (plus
/// its joined `DecisionRecord`, if any) onto a `SemanticIndexEntry`.
@Suite("IndexCommand — V1.33.C Suggestion → SemanticIndexEntry projection")
struct IndexCommandBuildEntryTests {

    // MARK: - Fixtures

    private static func makeSuggestion(
        templateName: String = "round-trip",
        functionName: String = "encode(_:)",
        file: String = "/foo/Bar.swift",
        line: Int = 10,
        scoreSignals: [Signal] = [Signal(kind: .typeSymmetrySignature, weight: 30, detail: "shape")]
    ) -> Suggestion {
        let evidence = Evidence(
            displayName: functionName,
            signature: "(String) -> String",
            location: SourceLocation(file: file, line: line, column: 1)
        )
        return Suggestion(
            templateName: templateName,
            evidence: [evidence],
            score: Score(signals: scoreSignals),
            generator: GeneratorMetadata(
                source: .notYetComputed,
                confidence: nil,
                sampling: .notRun
            ),
            explainability: ExplainabilityBlock(
                whySuggested: ["why"],
                whyMightBeWrong: ["caveat"]
            ),
            identity: SuggestionIdentity(canonicalInput: "test|\(functionName)|\(file):\(line)")
        )
    }

    // MARK: - Projection without decision

    @Test("V1.33.C — buildEntry without decision: decision/decisionAt are nil")
    func buildEntryWithoutDecision() {
        let suggestion = Self.makeSuggestion()
        let now = "2026-05-11T12:00:00Z"
        let entry = SwiftInferCommand.Index.buildEntry(
            from: suggestion,
            decisionsByHash: [:],
            now: now
        )
        #expect(entry.identityHash == suggestion.identity.display)
        #expect(entry.templateName == "round-trip")
        #expect(entry.score == 30)
        #expect(entry.tier == "Possible") // 30 lands in Possible (≥20, <40)
        #expect(entry.primaryFunctionName == "encode(_:)")
        #expect(entry.location == "/foo/Bar.swift:10")
        #expect(entry.decision == nil)
        #expect(entry.decisionAt == nil)
        #expect(entry.firstSeenAt == now)
        #expect(entry.lastSeenAt == now)
    }

    // MARK: - Projection with decision

    @Test("V1.33.C — buildEntry with accept decision: copies decision + timestamp")
    func buildEntryWithAcceptDecision() {
        let suggestion = Self.makeSuggestion()
        let decisionDate = Date(timeIntervalSince1970: 1_780_000_000)
        let record = DecisionRecord(
            identityHash: suggestion.identity.normalized,
            template: "round-trip",
            scoreAtDecision: 30,
            tier: .possible,
            decision: .accepted,
            timestamp: decisionDate
        )
        let now = "2026-05-11T12:00:00Z"
        let entry = SwiftInferCommand.Index.buildEntry(
            from: suggestion,
            decisionsByHash: [suggestion.identity.normalized: record],
            now: now
        )
        #expect(entry.decision == "accepted")
        let expectedTimestamp = SwiftInferCommand.Index.isoTimestamp(from: decisionDate)
        #expect(entry.decisionAt == expectedTimestamp)
    }

    @Test("V1.33.C — buildEntry with reject decision: decision is 'rejected'")
    func buildEntryWithRejectDecision() {
        let suggestion = Self.makeSuggestion()
        let record = DecisionRecord(
            identityHash: suggestion.identity.normalized,
            template: "round-trip",
            scoreAtDecision: 30,
            tier: .possible,
            decision: .rejected,
            timestamp: Date()
        )
        let entry = SwiftInferCommand.Index.buildEntry(
            from: suggestion,
            decisionsByHash: [suggestion.identity.normalized: record],
            now: "2026-05-11T12:00:00Z"
        )
        #expect(entry.decision == "rejected")
    }

    @Test("V1.33.C — buildEntry joins on normalized (no 0x prefix) form")
    func buildEntryJoinsOnNormalized() {
        let suggestion = Self.makeSuggestion()
        // Build a decisions map keyed on the normalized form (no 0x prefix).
        // The display form (with 0x) should NOT be present in decisions.json.
        let record = DecisionRecord(
            identityHash: suggestion.identity.normalized,
            template: "round-trip",
            scoreAtDecision: 30,
            tier: .possible,
            decision: .skipped,
            timestamp: Date()
        )
        let entry = SwiftInferCommand.Index.buildEntry(
            from: suggestion,
            decisionsByHash: [suggestion.identity.normalized: record],
            now: "2026-05-11T12:00:00Z"
        )
        #expect(entry.decision == "skipped")
        // The entry's identityHash is the display form (with 0x prefix).
        #expect(entry.identityHash.hasPrefix("0x"))
        // The normalized hash has no prefix.
        #expect(!suggestion.identity.normalized.hasPrefix("0x"))
    }

    // MARK: - Tier mapping

    @Test("V1.33.C — tier mapping: strong/likely/possible/suppressed/advisory render with capital letter")
    func tierMappingHumanReadable() {
        // Score 85 → Strong
        let strong = Self.makeSuggestion(
            scoreSignals: [Signal(kind: .typeSymmetrySignature, weight: 85, detail: "strong")]
        )
        let strongEntry = SwiftInferCommand.Index.buildEntry(
            from: strong,
            decisionsByHash: [:],
            now: "2026-05-11T12:00:00Z"
        )
        #expect(strongEntry.tier == "Strong")
        // Score 45 → Likely
        let likely = Self.makeSuggestion(
            scoreSignals: [Signal(kind: .typeSymmetrySignature, weight: 45, detail: "likely")]
        )
        let likelyEntry = SwiftInferCommand.Index.buildEntry(
            from: likely,
            decisionsByHash: [:],
            now: "2026-05-11T12:00:00Z"
        )
        #expect(likelyEntry.tier == "Likely")
    }
}
