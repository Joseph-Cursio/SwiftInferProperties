import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// #701 — verify evidence for a `documented-range` row does not survive an edit to its
/// doc-comment bounds.
///
/// **The defect, end to end.** Verify stamps its evidence with the index entry's
/// `evidenceFingerprint` (`Index.buildEntry`'s bodies, folded with the entry's bounds) and runs
/// the entry's bounds; discover checks the evidence against this run's fingerprint
/// (`Discover.fingerprintsByIdentity`). Both were body-only, and the doc
/// comment is not in the body, so after editing only "(0.0 to 1.0)" to "(0.0 to 0.5)" the
/// identity and both fingerprints were unchanged and the old `measured-bothPass` promoted the
/// row to `Verified` against bounds never run. Unit arms: `SubjectFingerprintLawDataTests`.
@Suite("documented-range — evidence goes stale when the doc-comment bounds change")
struct DocumentedRangeFingerprintStalenessTests {

    private static func source(upper: String) -> String {
        """
        public struct AnalysisProgress {
            public let filesProcessed: Int
            public let totalFiles: Int
            /// Fraction of files processed (0.0 to \(upper))
            public var progress: Double { 0 }
        }
        """
    }

    private struct Scan {
        let suggestion: Suggestion
        let summaries: [FunctionSummary]
    }

    private static func scan(upper: String) throws -> Scan {
        let corpus = FunctionScanner.scanCorpus(source: source(upper: upper), file: "Progress.swift")
        let summary = try #require(corpus.summaries.first { $0.name == "progress" })
        return Scan(
            suggestion: try #require(DocumentedRangeTemplate.suggest(for: summary)),
            summaries: corpus.summaries
        )
    }

    /// What `verify` writes: the evidence, stamped with the index entry's evidence fingerprint
    /// (`SwiftInferCommand.Verify+Pipeline.swift` and the survey's persist step both stamp it).
    private static func evidence(stampedBy scan: Scan) throws -> VerifyEvidence {
        let entry = SwiftInferCommand.Index.buildEntry(
            from: scan.suggestion,
            decisionsByHash: [:],
            now: "2026-11-13T00:00:00Z",
            fingerprintsByLocation: SubjectFingerprint.byLocation(scan.summaries)
        )
        return VerifyEvidence(
            identityHash: scan.suggestion.identity.normalized,
            template: "documented-range",
            outcome: .measuredBothPass,
            detail: "held",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            swiftInferVersion: "1.160.0",
            subjectFingerprint: try #require(entry.evidenceFingerprint)
        )
    }

    /// What `discover` does with it: check it against THIS run's fingerprint, then score.
    private static func discoverScore(_ scan: Scan, with evidence: VerifyEvidence) -> Suggestion {
        let current = SwiftInferCommand.Discover.fingerprintsByIdentity(
            for: [scan.suggestion], summaries: scan.summaries
        )
        return VerifyEvidenceScoring.applied(
            to: [scan.suggestion],
            evidenceByIdentity: [scan.suggestion.identity.normalized: evidence],
            currentFingerprintByIdentity: current
        )[0]
    }

    @Test("editing only the doc-comment bounds withholds the old bothPass")
    func editedBoundsAreStale() throws {
        let before = try Self.scan(upper: "1.0")
        let after = try Self.scan(upper: "0.5")
        // The premise: the identity and the body did not move, so nothing but the fold sees it.
        #expect(before.suggestion.identity == after.suggestion.identity)
        #expect(
            SubjectFingerprint.byLocation(before.summaries) == SubjectFingerprint.byLocation(after.summaries),
            "a doc-comment edit must leave the body fingerprints alone, or this arm proves nothing"
        )

        let scored = Self.discoverScore(after, with: try Self.evidence(stampedBy: before))
        #expect(!scored.score.signals.contains { $0.kind == .verifyBothPass }, "no +50 for bounds never run")
        #expect(scored.score.signals.last?.kind == .verifyEvidenceStale)
        #expect(scored.score.total == after.suggestion.score.total)
    }

    /// The caveat must not claim the BODY moved: here only the doc-comment bounds did.
    @Test("the stale caveat names the doc-comment bounds, not only the body")
    func staleCaveatNamesTheBounds() throws {
        let scored = Self.discoverScore(
            try Self.scan(upper: "0.5"), with: try Self.evidence(stampedBy: try Self.scan(upper: "1.0"))
        )
        let caveat = try #require(scored.explainability.whyMightBeWrong.first { $0.contains("NOT being applied") })
        #expect(caveat.contains("doc comment"), "a bounds-only edit must be named as a possible cause")
        #expect(!caveat.contains("version of this function's body ("), "must not claim the body alone moved")
    }

    /// The control for the wording: every other template keeps the body-only sentence.
    @Test("other templates keep the body-only caveat")
    func otherTemplatesKeepBodyWording() {
        #expect(VerifyEvidenceScoring.fingerprintedSubject(template: "idempotence") == "this function's body")
        #expect(
            VerifyEvidenceScoring.fingerprintedSubject(template: TemplateName.documentedRange.rawValue)
                .contains("doc comment")
        )
    }

    /// **The control** — without it, a fold that made every documented-range record stale
    /// would pass the arm above while withholding every fresh measurement too.
    @Test("unchanged bounds keep the bothPass: what verify stamps is what discover checks")
    func unchangedBoundsAreApplied() throws {
        let scan = try Self.scan(upper: "1.0")
        let scored = Self.discoverScore(try Self.scan(upper: "1.0"), with: try Self.evidence(stampedBy: scan))
        #expect(scored.score.signals.contains { $0.kind == .verifyBothPass })
        #expect(scored.score.total == scan.suggestion.score.total + VerifyEvidenceScoring.verifyBothPassWeight)
    }
}
