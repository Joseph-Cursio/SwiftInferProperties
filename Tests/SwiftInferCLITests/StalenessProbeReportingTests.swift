import Foundation
@testable import SwiftInferCLI
import Testing

/// The staleness probe answers `false` — *the index is fresh, verify against it* — for three
/// different reasons, two of which are "I could not check".
///
/// The conservative verdict is right and unchanged; the silence was not. A false "fresh"
/// commits the run to whatever `IndexStore.upsert` accumulated, which reports **the union of
/// every run that ever happened** — the trap §6 hit for real at 251 entries against ~123
/// current picks.
@Suite("Staleness probe — a verdict it could not compute says so")
struct StalenessProbeReportingTests {

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stale-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// **The arm that must stay quiet.** A genuine, computable "not stale" is the common
    /// case — an index newer than every source — and must not put a line on every run.
    @Test("a computable not-stale answer is silent")
    func computableFreshIsSilent() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("let a = 1".utf8).write(to: sources.appendingPathComponent("A.swift"))
        // Written after the source, so the index is genuinely newer.
        let index = root.appendingPathComponent("index.json")
        try Data("{}".utf8).write(to: index)

        var said: [String] = []
        let stale = VerifyHarness.isStale(indexPath: index, packageRoot: root) { said.append($0) }
        #expect(stale == false)
        #expect(said.isEmpty, "a real answer is never worth a line")
    }

    /// A real staleness detection also stays quiet — it is a computed answer.
    @Test("a genuinely stale index is detected and silent")
    func staleIsDetectedAndSilent() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = root.appendingPathComponent("index.json")
        try Data("{}".utf8).write(to: index)
        let sources = root.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let newer = sources.appendingPathComponent("A.swift")
        try Data("let a = 1".utf8).write(to: newer)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(3_600)], ofItemAtPath: newer.path
        )

        var said: [String] = []
        let stale = VerifyHarness.isStale(indexPath: index, packageRoot: root) { said.append($0) }
        #expect(stale == true)
        #expect(said.isEmpty)
    }

    /// The index's own attributes are unreadable — the whole verdict is uncomputed.
    @Test("an unreadable index reports, and still answers fresh")
    func unreadableIndexReports() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var said: [String] = []
        let missing = root.appendingPathComponent("does-not-exist.json")
        let stale = VerifyHarness.isStale(indexPath: missing, packageRoot: root) { said.append($0) }
        #expect(stale == false, "conservative verdict preserved deliberately")
        #expect(said.count == 1)
        #expect(said.first?.contains("staleness could not be determined") == true)
        #expect(
            said.first?.contains("accumulated previously") == true,
            "the reader must be told what a false fresh commits them to"
        )
    }

    /// No `Sources` to walk — nothing was compared, and "fresh" means nothing here.
    @Test("an unwalkable Sources reports that nothing was checked")
    func unwalkableSourcesReports() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = root.appendingPathComponent("index.json")
        try Data("{}".utf8).write(to: index)

        var said: [String] = []
        let stale = VerifyHarness.isStale(indexPath: index, packageRoot: root) { said.append($0) }
        #expect(stale == false)
        #expect(said.contains { $0.contains("nothing was actually checked") })
    }
}
