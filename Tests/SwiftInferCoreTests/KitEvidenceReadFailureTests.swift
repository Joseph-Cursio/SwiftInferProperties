import Foundation
@testable import SwiftInferCore
import Testing

/// An absent kit-evidence log and an unreadable one are different facts, and only one is
/// normal.
///
/// `ProtocolCoverageAudit` has three states — `verified` / `assumed` / `contradicted` — and
/// its own doc says `wasExercised` cannot separate the last two because *"the log's EMPTINESS
/// is what tells them apart"*. A corrupt log read as empty therefore reports `assumed`
/// (normal, one aggregate line) when the truth may be `contradicted`: the project uses the
/// kit, did not run it here, and those laws are checked by nothing.
@Suite("Kit evidence — unreadable is not the same as absent")
struct KitEvidenceReadFailureTests {

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kit-evidence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// **The arm that must stay quiet.** Most projects never record evidence; a line on every
    /// such run would be noise, and noise is how a real warning gets skipped.
    @Test("an absent log is silent")
    func absentLogIsSilent() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var said: [String] = []
        let log = KitEvidenceStore.load(startingFrom: root) { said.append($0) }
        #expect(said.isEmpty, "absent evidence is the normal state, not a warning")
        #expect(log.outcomes.isEmpty)
    }

    /// The measured hazard: the file is there and will not parse.
    @Test("a corrupt log is reported, and still degrades to empty")
    func corruptLogIsReported() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent(KitEvidenceStore.conventionalRelativePath)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("{ this is not json".utf8).write(to: path)

        var said: [String] = []
        let log = KitEvidenceStore.load(startingFrom: root) { said.append($0) }
        #expect(said.count == 1)
        #expect(said.first?.contains("could not be read") == true)
        #expect(
            said.first?.contains("may mean the opposite") == true,
            "the reader must be told which direction the error biases the verdict"
        )
        #expect(log.outcomes.isEmpty, "still degrades rather than trapping — reporting, not failing")
    }
}
