import Foundation
@testable import SwiftInferCLI
import Testing

/// `packageDependsOnSwiftSyntax` answers `false` for two different reasons, and only one is
/// benign: no manifest (an Xcode project or a `--sources` run — `false` is correct) versus a
/// manifest that exists and cannot be read (the answer is *unknown*).
///
/// The second matters because `false` makes the stub omit SwiftSyntax/SwiftParser/
/// PropertyLawSyntax, and the entry then fails as `build-failed` or — worse —
/// `unsupported-carrier`, which reads as *no generator exists* and points the reader at the
/// kit. That misattribution is the one §9.3 spent a day unpicking from the other end.
@Suite("Manifest read failure — unknown is not the same as absent")
struct ManifestReadFailureTests {

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("manifest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// **The arm that must stay quiet** — an Xcode project has no `Package.swift`, and that
    /// is a supported shape, not a fault.
    @Test("no manifest is silent and answers false")
    func absentManifestIsSilent() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var said: [String] = []
        let answer = VerifierWorkdir.packageDependsOnSwiftSyntax(at: root) { said.append($0) }
        #expect(answer == false)
        #expect(said.isEmpty)
    }

    /// A readable manifest still answers from its contents, in both directions.
    @Test("a readable manifest answers from its contents", arguments: [true, false])
    func readableManifestAnswers(declaresSyntax: Bool) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let body = declaresSyntax
            ? "// .package(url: \"https://github.com/swiftlang/swift-syntax.git\", from: \"600.0.0\")"
            : "// no parser dependency here"
        try Data(body.utf8).write(to: root.appendingPathComponent("Package.swift"))

        var said: [String] = []
        let answer = VerifierWorkdir.packageDependsOnSwiftSyntax(at: root) { said.append($0) }
        #expect(answer == declaresSyntax)
        #expect(said.isEmpty, "a manifest that reads cleanly is never worth a line")
    }

    /// A manifest that exists but is not valid UTF-8 is the unknown case.
    @Test("an unreadable manifest is reported, and names the consequence")
    func unreadableManifestIsReported() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // Invalid UTF-8 — `String(contentsOf:encoding:)` throws rather than substituting.
        try Data([0xFF, 0xFE, 0xFF]).write(to: root.appendingPathComponent("Package.swift"))

        var said: [String] = []
        let answer = VerifierWorkdir.packageDependsOnSwiftSyntax(at: root) { said.append($0) }
        #expect(answer == false, "still degrades rather than trapping")
        #expect(said.count == 1)
        #expect(said.first?.contains("could not be read") == true)
        #expect(
            said.first?.contains("no generator exists") == true,
            "the reader must be told the failure will masquerade as a carrier gap"
        )
    }
}
