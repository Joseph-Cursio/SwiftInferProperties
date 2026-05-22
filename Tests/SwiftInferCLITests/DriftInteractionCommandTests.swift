import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// V2.0 M10 — end-to-end `drift-interaction` orchestration. Builds a
// real package-on-disk fixture so the M1 reducer-discoverer + M4
// template engine fire; baseline persisted via the loader; warnings
// rendered to a recording diagnostic output.

@Suite("DriftInteraction — V2.0 M10 CLI orchestration")
struct DriftInteractionCommandTests {

    private func makeFixturePackage(name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftInteractionTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: root.appendingPathComponent("Package.swift")
        )
        return root
    }

    private func writeSource(in root: URL, target: String, named name: String, contents: String) throws {
        let dir = root.appendingPathComponent("Sources").appendingPathComponent(target)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: dir.appendingPathComponent(name))
    }

    // MARK: - Empty package: no suggestions → "No drift detected."

    @Test("empty package: drift-interaction reports `No drift detected.`")
    func emptyPackageReportsNoDrift() throws {
        let root = try makeFixturePackage(name: "Empty")
        defer { try? FileManager.default.removeItem(at: root) }
        let target = "MyApp"
        let directory = root.appendingPathComponent("Sources").appendingPathComponent(target)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = DIRecordingOutput()
        let diagnostics = DIRecordingDiagnosticOutput()
        try SwiftInferCommand.DriftInteraction.run(
            target: target,
            workingDirectory: root,
            directory: directory,
            output: output,
            diagnostics: diagnostics
        )
        #expect(output.lines == ["No drift detected."])
        #expect(diagnostics.lines.isEmpty)
    }

    // MARK: - Strong-tier-only filter

    @Test("Possible-tier suggestions (the v2.0 default) don't trigger drift warnings")
    func possibleTierProducesNoWarnings() throws {
        let root = try makeFixturePackage(name: "PossibleOnly")
        defer { try? FileManager.default.removeItem(at: root) }
        // A reducer that fires Conservation at default Possible tier
        // (per PRD §3.5 corollary — every M4+ family ships at default
        // Possible until calibration promotes).
        try writeSource(in: root, target: "MyApp", named: "Reducer.swift", contents: """
        struct InboxState {
            var count: Int = 0
            var items: [Int] = []
        }
        enum InboxAction: CaseIterable { case noop }
        func reduce(_ state: InboxState, _ action: InboxAction) -> InboxState { state }
        """)
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("MyApp")
        let output = DIRecordingOutput()
        let diagnostics = DIRecordingDiagnosticOutput()
        try SwiftInferCommand.DriftInteraction.run(
            target: "MyApp",
            workingDirectory: root,
            directory: directory,
            output: output,
            diagnostics: diagnostics
        )
        // Possible-tier suggestions stay silent — no drift warnings.
        #expect(diagnostics.lines.isEmpty)
        #expect(output.lines == ["No drift detected."])
    }

    // MARK: - Baseline path resolution

    @Test("missing baseline file at implicit path is silent (M10 walks up)")
    func implicitMissingBaselineIsSilent() throws {
        let root = try makeFixturePackage(name: "ImplicitMissing")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("MyApp")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = DIRecordingOutput()
        let diagnostics = DIRecordingDiagnosticOutput()
        try SwiftInferCommand.DriftInteraction.run(
            target: "MyApp",
            workingDirectory: root,
            directory: directory,
            output: output,
            diagnostics: diagnostics
        )
        #expect(!diagnostics.lines.contains { $0.contains("not found") })
    }

    @Test("explicit baseline path missing surfaces a diagnostic warning")
    func explicitMissingBaselineWarns() throws {
        let root = try makeFixturePackage(name: "ExplicitMissing")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Sources").appendingPathComponent("MyApp")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let nowhere = root.appendingPathComponent("does-not-exist.json")
        let output = DIRecordingOutput()
        let diagnostics = DIRecordingDiagnosticOutput()
        try SwiftInferCommand.DriftInteraction.run(
            target: "MyApp",
            workingDirectory: root,
            directory: directory,
            explicitBaselinePath: nowhere,
            output: output,
            diagnostics: diagnostics
        )
        #expect(diagnostics.lines.contains { $0.contains("interaction-baseline file not found") })
    }
}

// MARK: - Recording helpers (file-private — same posture as DriftCommandTests
// to avoid colliding with same-named helpers in other suites).

private final class DIRecordingOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []

    func write(_ text: String) {
        lines.append(text)
    }
}

private final class DIRecordingDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    private(set) var lines: [String] = []

    func writeDiagnostic(_ text: String) {
        lines.append(text)
    }
}
