import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// #701 — folding a `documented-range` row's doc-comment bounds into its evidence fingerprint
/// must not change what `SurveyRunDiff` reads as the BODY fingerprint.
///
/// **The defect this pins.** The first fix folded the bounds into the index entry's
/// `subjectFingerprint`, which the survey copies onto `SurveyRecord.subjectFingerprint`, which
/// `SurveyRunDiff.SubjectMovement` reads as a body fingerprint. A row-level A/B of `main` against
/// the branch over one tree then reported `body changed` on every `documented-range` row (main
/// stamped bodies only, the branch the fold), hiding the reading the diff exists to surface:
/// the tool changed, the code did not. The fix keeps `subjectFingerprint` bodies-only and carries
/// the fold beside it (`SurveyRecord.lawDataFingerprint`).
@Suite("documented-range — survey diff reads bodies, and names a bounds-only edit")
struct DocumentedRangeSurveyDiffTests {

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
        let entry: SemanticIndexEntry
    }

    private static func scan(upper: String) throws -> Scan {
        let corpus = FunctionScanner.scanCorpus(source: source(upper: upper), file: "Progress.swift")
        let summary = try #require(corpus.summaries.first { $0.name == "progress" })
        let suggestion = try #require(DocumentedRangeTemplate.suggest(for: summary))
        return Scan(
            suggestion: suggestion,
            summaries: corpus.summaries,
            entry: SwiftInferCommand.Index.buildEntry(
                from: suggestion,
                decisionsByHash: [:],
                now: "2026-11-13T00:00:00Z",
                fingerprintsByLocation: SubjectFingerprint.byLocation(corpus.summaries)
            )
        )
    }

    /// The record the survey writes for this entry, with a chosen outcome.
    private static func record(
        _ scan: Scan,
        _ outcome: SwiftInferCommand.Verify.SurveyOutcome
    ) -> SwiftInferCommand.Verify.SurveyRecord {
        SwiftInferCommand.Verify.surveyErrorRecord(
            SwiftInferCommand.Verify.recordContext(for: scan.entry), outcome, nil
        )
    }

    private static func run(_ records: [SwiftInferCommand.Verify.SurveyRecord]) -> RetainedSurveyRun {
        RetainedSurveyRun(
            schemaVersion: RetainedSurveyRun.currentSchemaVersion,
            label: "test run",
            capturedAt: Date(timeIntervalSince1970: 1_770_000_000),
            target: "Progress",
            subjectRevision: "/tmp/subject @ abc1234",
            swiftInferVersion: "1.160.0",
            tiersByIdentity: [:],
            records: records
        )
    }

    private static func movement(
        before: SwiftInferCommand.Verify.SurveyRecord,
        after: SwiftInferCommand.Verify.SurveyRecord
    ) -> SurveyRunDiff.SubjectMovement? {
        SurveyRunDiff.compare(before: run([before]), after: run([after])).changed.first?.movement
    }

    @Test("the index and survey fingerprint is the bodies alone; the fold rides beside it")
    func subjectFingerprintIsBodiesOnly() throws {
        let scan = try Self.scan(upper: "1.0")
        let bodies = SubjectFingerprint.forSuggestion(
            evidenceLocations: scan.suggestion.evidence.map(\.location),
            byLocation: SubjectFingerprint.byLocation(scan.summaries)
        )
        let record = Self.record(scan, .measuredBothPass)
        #expect(scan.entry.subjectFingerprint == bodies)
        #expect(record.subjectFingerprint == bodies)
        #expect(record.lawDataFingerprint != nil)
        #expect(record.lawDataFingerprint != bodies)
    }

    /// The value verify stamps from (the survey record's and the index entry's evidence
    /// fingerprint) must equal what discover checks, or every fresh `documented-range`
    /// measurement reads as stale. That the persist steps stamp THIS value, and not the
    /// bodies-only one, is pinned through the real writers in `DocumentedRangeEvidenceStampTests`.
    @Test("the record's and the entry's evidence fingerprint equal discover's")
    func evidenceFingerprintEqualsDiscover() throws {
        let scan = try Self.scan(upper: "1.0")
        let discover = SwiftInferCommand.Discover.fingerprintsByIdentity(
            for: [scan.suggestion], summaries: scan.summaries
        )[scan.suggestion.identity.normalized]
        #expect(discover != nil)
        #expect(Self.record(scan, .measuredBothPass).evidenceFingerprint == discover)
        #expect(scan.entry.evidenceFingerprint == discover)
    }

    @Test("editing only the bounds reports law data changed, not body changed")
    func boundsOnlyEditIsNamed() throws {
        let before = Self.record(try Self.scan(upper: "1.0"), .measuredBothPass)
        let after = Self.record(try Self.scan(upper: "0.5"), .measuredDefaultFails)
        #expect(before.subjectFingerprint == after.subjectFingerprint, "the premise: one body")
        #expect(Self.movement(before: before, after: after) == .lawDataChanged)
    }

    /// The label must not claim the code moved: `lawDataFingerprint` folds the PARSED bounds, so
    /// a parser change over an unchanged doc comment lands here too. It names both causes.
    @Test("the law-data label names both causes and claims neither")
    func lawDataLabelIsNeutral() {
        let label = SurveyRunDiff.SubjectMovement.lawDataChanged.rawValue
        #expect(label.contains("body identical"))
        #expect(label.contains("edited"))
        #expect(label.contains("read differently"))
        #expect(label.contains("cannot tell"))
        #expect(!label.contains("changed ("), "must not assert the doc comment changed")
        #expect(label != SurveyRunDiff.SubjectMovement.bodyIdentical.rawValue)
    }

    /// **The A/B the review named**: `main` stamped the bodies alone and wrote no law-data
    /// field; the branch measures the same tree. The verdict moved and no byte of source did,
    /// so the diff must say the TOOL changed.
    @Test("main against the branch over one tree reads body IDENTICAL")
    func mainAgainstBranchIsAToolChange() throws {
        let scan = try Self.scan(upper: "1.0")
        let branch = Self.record(scan, .measuredBothPass)
        let main = SwiftInferCommand.Verify.SurveyRecord(
            identityHash: branch.identityHash,
            templateName: branch.templateName,
            primaryFunctionName: branch.primaryFunctionName,
            carrier: branch.carrier,
            outcome: .architecturalCoveragePending,
            outcomeDetail: "unsupported-template: documented-range",
            subjectFingerprint: SubjectFingerprint.forSuggestion(
                evidenceLocations: scan.suggestion.evidence.map(\.location),
                byLocation: SubjectFingerprint.byLocation(scan.summaries)
            )
        )
        #expect(Self.movement(before: main, after: branch) == .bodyIdentical)
    }

    /// The control: an unchanged row with an unchanged verdict is not a change at all, and a
    /// re-run over identical bounds keeps `body IDENTICAL` rather than inventing a law-data edit.
    @Test("same bounds, moved verdict → body IDENTICAL")
    func sameBoundsKeepBodyIdentical() throws {
        let before = Self.record(try Self.scan(upper: "1.0"), .measuredBothPass)
        let after = Self.record(try Self.scan(upper: "1.0"), .measuredDefaultFails)
        #expect(Self.movement(before: before, after: after) == .bodyIdentical)
    }
}
