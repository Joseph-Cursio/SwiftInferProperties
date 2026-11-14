import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// #701 — what verify WRITES to `.swiftinfer/verify-evidence.json` for a `documented-range` row
/// must carry the fingerprint discover checks, on both writers.
///
/// **Why through the writers.** The fold lives in `evidenceFingerprint`; the bodies-only value
/// is `subjectFingerprint`, one property name away. Both persist steps
/// (`Verify+AllFromIndex+Persist.swift` for the survey, `Verify+Pipeline.swift` for a single
/// entry) once stamped the latter, and a test that only compares the two values in memory cannot
/// see which one a writer picked. These arms run each writer into a temp root, read the store
/// back, and compare against `Discover.fingerprintsByIdentity`. Stamping `subjectFingerprint` in
/// either writer fails its arm: the bodies-only value differs from discover's folded one.
@Suite("documented-range — both evidence writers stamp the fingerprint discover checks")
struct DocumentedRangeEvidenceStampTests {

    private static let source = """
        public struct AnalysisProgress {
            public let filesProcessed: Int
            public let totalFiles: Int
            /// Fraction of files processed (0.0 to 1.0)
            public var progress: Double { 0 }
        }
        """

    private struct Scan {
        let suggestion: Suggestion
        let summaries: [FunctionSummary]
        let entry: SemanticIndexEntry

        /// What discover checks evidence for this suggestion against.
        var discoverFingerprint: String? {
            SwiftInferCommand.Discover.fingerprintsByIdentity(
                for: [suggestion], summaries: summaries
            )[suggestion.identity.normalized]
        }
    }

    private static func scan() throws -> Scan {
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Progress.swift")
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

    private static func withTempRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("documented-range-stamp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    /// Read the file directly: `VerifyEvidenceStore.load(startingFrom:)` walks up looking for a
    /// `Package.swift` the temp root does not have, and would return an empty log.
    private static func storedRecord(in root: URL) throws -> VerifyEvidence {
        let path = root.appendingPathComponent(".swiftinfer")
            .appendingPathComponent("verify-evidence.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let log = try decoder.decode(VerifyEvidenceLog.self, from: Data(contentsOf: path))
        #expect(log.records.count == 1)
        return try #require(log.records.first)
    }

    /// The premise both arms rest on: the folded and bodies-only values differ for this row, so
    /// a writer that stamped the wrong one cannot pass by coincidence.
    @Test("the premise: discover's fingerprint is the fold, not the bodies alone")
    func foldDiffersFromBodies() throws {
        let scan = try Self.scan()
        let discover = try #require(scan.discoverFingerprint)
        #expect(scan.entry.subjectFingerprint != nil)
        #expect(scan.entry.subjectFingerprint != discover)
    }

    @Test("the survey's persist step stamps discover's fingerprint")
    func surveyPersistStampsDiscoverFingerprint() throws {
        let scan = try Self.scan()
        let record = SwiftInferCommand.Verify.surveyErrorRecord(
            SwiftInferCommand.Verify.recordContext(for: scan.entry), .measuredBothPass, nil
        )
        try Self.withTempRoot { root in
            SwiftInferCommand.Verify.persistSurveyBatch(
                [record], packageRoot: root, now: Date(timeIntervalSince1970: 1_770_000_000)
            )
            let stored = try Self.storedRecord(in: root)
            #expect(stored.template == TemplateName.documentedRange.rawValue)
            #expect(stored.subjectFingerprint != nil)
            #expect(stored.subjectFingerprint == scan.discoverFingerprint)
        }
    }

    @Test("the single-entry writer stamps discover's fingerprint")
    func singleEntryPersistStampsDiscoverFingerprint() throws {
        let scan = try Self.scan()
        try Self.withTempRoot { root in
            SwiftInferCommand.Verify.persistEvidence(
                parsed: .bothPass(defaultTrials: 1_000, edgeTrials: 0, edgeSampled: 0),
                entry: scan.entry,
                packageRoot: root,
                regressionPath: nil,
                now: Date(timeIntervalSince1970: 1_770_000_000)
            )
            let stored = try Self.storedRecord(in: root)
            #expect(stored.template == TemplateName.documentedRange.rawValue)
            #expect(stored.subjectFingerprint != nil)
            #expect(stored.subjectFingerprint == scan.discoverFingerprint)
        }
    }
}
