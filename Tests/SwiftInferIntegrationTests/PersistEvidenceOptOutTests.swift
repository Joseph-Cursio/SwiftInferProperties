import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// #129 — a survey must be able to run without rewriting the file it is being compared
/// against, and must say so when it does rewrite a tracked one.
///
/// The failure is not lost data; it is a comparison against itself. Re-verifying
/// `fixtures/cycle27-surface` and diffing against its frozen evidence reported **0 drift**,
/// which was false: the run had already rewritten the file. The tell was arithmetic —
/// frozen was 39/8/6 and the rerun printed 35/8/5 plus 5 errors, and "0 drifted" cannot be
/// true alongside different distributions.
@Suite("Persisting evidence — opt out, and warn when the target is tracked", .tags(.subprocess))
struct PersistEvidenceOptOutTests {

    private static func record() -> SwiftInferCommand.Verify.SurveyRecord {
        SwiftInferCommand.Verify.SurveyRecord(
            identityHash: "0xAAAA000000000001",
            templateName: "idempotence",
            primaryFunctionName: "f()",
            carrier: "T",
            outcome: .measuredBothPass,
            outcomeDetail: "defaultTrials=100"
        )
    }

    private static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("persist-optout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func evidencePath(_ root: URL) -> URL {
        root.appendingPathComponent(".swiftinfer").appendingPathComponent("verify-evidence.json")
    }

    @Test("--no-persist-evidence writes nothing at all")
    func optOutWritesNothing() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        SwiftInferCommand.Verify.persistSurveyBatch(
            [Self.record()],
            packageRoot: root,
            now: Date(timeIntervalSince1970: 1_000_000),
            persistEvidence: false
        )
        #expect(!FileManager.default.fileExists(atPath: Self.evidencePath(root).path))
    }

    /// **The control.** An opt-out that also broke the default would be a worse bug than
    /// the one it fixes, and a test that only asserts absence cannot tell "opted out" from
    /// "never worked".
    @Test("the default still persists")
    func defaultStillPersists() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        SwiftInferCommand.Verify.persistSurveyBatch(
            [Self.record()],
            packageRoot: root,
            now: Date(timeIntervalSince1970: 1_000_000)
        )
        #expect(FileManager.default.fileExists(atPath: Self.evidencePath(root).path))
    }

    /// An untracked file is the normal case and must stay silent — a warning on every run
    /// is how a warning stops being read.
    @Test("an untracked evidence file produces no warning")
    func untrackedFileIsSilent() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = Self.evidencePath(root)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: path)

        #expect(TrackedFileGuard.overwriteWarning(for: path) == nil)
    }

    /// A tracked file must warn, and the warning must carry the recovery command —
    /// recovering the real baseline needed `git show HEAD:<path>`, and that is the one
    /// thing the reader needs at that moment.
    @Test("a tracked file warns, and names the recovery command")
    func trackedFileWarnsWithRecovery() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        // A file this repo genuinely tracks, and the one the issue is about.
        let tracked = repository
            .appendingPathComponent("fixtures/cycle27-surface/.swiftinfer/verify-evidence.json")
        try #require(FileManager.default.fileExists(atPath: tracked.path))

        let warning = try #require(TrackedFileGuard.overwriteWarning(for: tracked))
        #expect(warning.contains("tracked by git"))
        #expect(warning.contains("git show HEAD:"))
        #expect(warning.contains("fixtures/cycle27-surface/.swiftinfer/verify-evidence.json"))
        #expect(warning.contains("--no-persist-evidence"))
    }
}
