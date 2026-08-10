import Foundation
@testable import SwiftInferCLI
import Testing

/// An unreadable file costs the speculative runner twice: its restricted functions are never
/// proposed for widening, and its path is absent from `sourcesByFile`, so the caller's
/// `guard let original = sourcesByFile[path]` would drop the candidate a second time.
@Suite("Speculative scan — an unreadable file is reported")
struct SpeculativeScanReadFailureTests {

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("spec-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// **The arm that must stay quiet.**
    @Test("readable sources scan silently")
    func readableSourcesAreSilent() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("private func f() {}".utf8).write(to: root.appendingPathComponent("A.swift"))

        var said: [String] = []
        let scan = SpeculativeRefactorRunner.scanRestricted(under: root) { said.append($0) }
        #expect(said.isEmpty)
        #expect(scan.sourcesByFile.count == 1)
    }

    @Test("an unreadable file is reported, and the readable ones still scan")
    func unreadableFileIsReported() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("private func f() {}".utf8).write(to: root.appendingPathComponent("A.swift"))
        try Data([0xFF, 0xFE, 0xFF]).write(to: root.appendingPathComponent("B.swift"))

        var said: [String] = []
        let scan = SpeculativeRefactorRunner.scanRestricted(under: root) { said.append($0) }
        #expect(scan.sourcesByFile.count == 1)
        #expect(said.count == 1)
        #expect(said.first?.contains("widening candidates") == true)
        #expect(
            said.first?.contains("not judged") == true,
            "absent-from-the-run and judged-and-rejected must read differently"
        )
    }
}
