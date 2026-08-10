import Foundation
@testable import SwiftInferCore
import Testing

/// The effect table is built from these parsed trees and feeds the purity gates. A file
/// dropped by `compactMap` does not merely shrink the input — it can leave a function
/// unresolved, or resolve it from fewer call sites than the tree contains, and both read
/// downstream as a fact about the code.
@Suite("Effect source parsing — an unreadable file is reported")
struct EffectSourceReadFailureTests {

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("effect-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// **The arm that must stay quiet** — readable sources are the whole point.
    @Test("readable sources parse silently")
    func readableSourcesAreSilent() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("func f() {}".utf8).write(to: root.appendingPathComponent("A.swift"))

        var said: [String] = []
        let trees = EffectResolver.parseSources(in: root) { said.append($0) }
        #expect(trees.count == 1)
        #expect(said.isEmpty)
    }

    /// Invalid UTF-8 throws from `String(contentsOfFile:encoding:)` rather than substituting.
    @Test("an unreadable file is reported and skipped, not silently dropped")
    func unreadableFileIsReported() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("func f() {}".utf8).write(to: root.appendingPathComponent("A.swift"))
        try Data([0xFF, 0xFE, 0xFF]).write(to: root.appendingPathComponent("B.swift"))

        var said: [String] = []
        let trees = EffectResolver.parseSources(in: root) { said.append($0) }
        #expect(trees.count == 1, "the readable file still parses — reporting, not failing")
        #expect(said.count == 1)
        #expect(said.first?.contains("effect table") == true)
        #expect(
            said.first?.contains("property of the code") == true,
            "the reader must be told the omission masquerades as a finding"
        )
    }
}
