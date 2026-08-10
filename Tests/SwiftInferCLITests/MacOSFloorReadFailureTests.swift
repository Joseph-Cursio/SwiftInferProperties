import Foundation
@testable import SwiftInferCLI
import Testing

/// `declaredMacOSVersion` answers `nil` for two reasons and the caller cannot tell them
/// apart: no manifest (an Xcode project — the floor is right) versus a manifest that exists
/// and cannot be read (the declared floor is unknown).
///
/// Silently using the 14.0 floor for the second produces a stub that fails to build on a
/// corpus requiring more, with an error naming an availability symbol — which reads as a
/// property of the code rather than of the read.
@Suite("macOS floor — unknown is not the same as undeclared")
struct MacOSFloorReadFailureTests {

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("macos-floor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// **The arm that must stay quiet** — an Xcode project has no `Package.swift`.
    @Test("no manifest is silent")
    func absentManifestIsSilent() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var said: [String] = []
        #expect(VerifierWorkdir.declaredMacOSVersion(inPackageAt: root) { said.append($0) } == nil)
        #expect(said.isEmpty)
    }

    /// A readable manifest still answers from its contents, silently.
    @Test("a readable manifest answers and stays silent")
    func readableManifestAnswers() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("platforms: [.macOS(.v26)]".utf8)
            .write(to: root.appendingPathComponent("Package.swift"))
        var said: [String] = []
        let answer = VerifierWorkdir.declaredMacOSVersion(inPackageAt: root) { said.append($0) }
        #expect(answer == "26.0")
        #expect(said.isEmpty)
    }

    @Test("an unreadable manifest is reported and names the consequence")
    func unreadableManifestIsReported() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0xFF, 0xFE, 0xFF]).write(to: root.appendingPathComponent("Package.swift"))
        var said: [String] = []
        #expect(VerifierWorkdir.declaredMacOSVersion(inPackageAt: root) { said.append($0) } == nil)
        #expect(said.count == 1)
        #expect(said.first?.contains("could not be read") == true)
        #expect(
            said.first?.contains("fail to build on availability") == true,
            "the reader must be told how the fallback will surface"
        )
    }
}
