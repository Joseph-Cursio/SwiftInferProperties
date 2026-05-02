import Foundation
import SwiftInferCore
import Testing
@testable import SwiftInferCLI

@Suite("Drift command + --update-baseline (M6.5)")
struct DriftCommandTests {

    // MARK: - --update-baseline

    @Test
    func updateBaselineWritesByteIdenticalJsonAcrossReSaves() throws {
        let directory = try makeFixtureDirectory(name: "UpdateBaselineByteStable")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: directory.appendingPathComponent("Package.swift")
        )
        let target = try makeTarget(in: directory, contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)

        try SwiftInferCommand.Discover.run(
            directory: target,
            updateBaseline: true,
            output: RecordingOutput(),
            diagnostics: RecordingDiagnosticOutput()
        )
        let baselinePath = directory.appendingPathComponent(".swiftinfer/baseline.json")
        let firstSave = try Data(contentsOf: baselinePath)

        try SwiftInferCommand.Discover.run(
            directory: target,
            updateBaseline: true,
            output: RecordingOutput(),
            diagnostics: RecordingDiagnosticOutput()
        )
        let secondSave = try Data(contentsOf: baselinePath)
        #expect(firstSave == secondSave)

        let baseline = try JSONDecoder().decode(Baseline.self, from: firstSave)
        #expect(baseline.entries.count == 1)
        #expect(baseline.entries.first?.template == "idempotence")
        #expect(baseline.entries.first?.tier == .strong)
    }

    @Test
    func updateBaselineWithDryRunReportsPathAndWritesNothing() throws {
        let directory = try makeFixtureDirectory(name: "UpdateBaselineDryRun")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: directory.appendingPathComponent("Package.swift")
        )
        let target = try makeTarget(in: directory, contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        let recording = RecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: target,
            dryRun: true,
            updateBaseline: true,
            output: recording,
            diagnostics: RecordingDiagnosticOutput()
        )
        #expect(recording.lines.contains { line in
            line.contains("[dry-run] would write baseline to") && line.contains(".swiftinfer/baseline.json")
        })
        let baselinePath = directory.appendingPathComponent(".swiftinfer/baseline.json")
        #expect(!FileManager.default.fileExists(atPath: baselinePath.path))
    }

    @Test
    func updateBaselineMixedWithInteractiveEmitsConflictWarning() throws {
        let directory = try makeFixtureDirectory(name: "UpdateBaselineConflict")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: directory.appendingPathComponent("Package.swift")
        )
        let target = try makeTarget(in: directory, contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: target,
            interactive: true,
            updateBaseline: true,
            promptInput: ScriptedPromptInput(scriptedLines: ["s"]),
            output: RecordingOutput(),
            diagnostics: diagnostics
        )
        #expect(diagnostics.lines.contains { line in
            line.contains("--interactive and --update-baseline are mutually exclusive")
        })
        // --update-baseline is ignored when --interactive is also set.
        let baselinePath = directory.appendingPathComponent(".swiftinfer/baseline.json")
        #expect(!FileManager.default.fileExists(atPath: baselinePath.path))
    }

    // MARK: - swift-infer drift

    @Test
    func driftAgainstFreshCorpusWithoutBaselineWarnsOnEveryStrong() throws {
        let directory = try makeFixtureDirectory(name: "DriftFreshCorpus")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: directory.appendingPathComponent("Package.swift")
        )
        let target = try makeTarget(in: directory, contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Drift.run(
            directory: target,
            output: recording,
            diagnostics: diagnostics
        )
        let driftLines = diagnostics.lines.filter { $0.hasPrefix("warning: drift:") }
        #expect(driftLines.count == 1)
        #expect(driftLines.first?.contains("normalize(_:)") == true)
        #expect(driftLines.first?.contains("idempotence") == true)
        #expect(recording.lines.contains("1 drift warning emitted."))
    }

    @Test
    func driftAfterUpdateBaselineIsSilent() throws {
        let directory = try makeFixtureDirectory(name: "DriftSilentAfterBaseline")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: directory.appendingPathComponent("Package.swift")
        )
        let target = try makeTarget(in: directory, contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        try SwiftInferCommand.Discover.run(
            directory: target,
            updateBaseline: true,
            output: RecordingOutput(),
            diagnostics: RecordingDiagnosticOutput()
        )
        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Drift.run(
            directory: target,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(diagnostics.lines.filter { $0.hasPrefix("warning: drift:") }.isEmpty)
        #expect(recording.lines.contains("No drift detected."))
    }

    @Test
    func driftIsSilentForDecidedSuggestionsEvenWhenNotInBaseline() throws {
        let directory = try makeFixtureDirectory(name: "DriftSilentAfterDecision")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: directory.appendingPathComponent("Package.swift")
        )
        let target = try makeTarget(in: directory, contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        // Discover the suggestion to capture its identity, then write a
        // matching .swiftinfer/decisions.json with a `.skipped` record.
        let pipeline = try SwiftInferCommand.Discover.collectVisibleSuggestions(
            directory: target,
            diagnostics: RecordingDiagnosticOutput()
        )
        let strong = try #require(pipeline.suggestions.first { $0.score.tier == .strong })
        let decisions = Decisions(records: [
            DecisionRecord(
                identityHash: strong.identity.normalized,
                template: strong.templateName,
                scoreAtDecision: strong.score.total,
                tier: .strong,
                decision: .skipped,
                timestamp: Date(timeIntervalSince1970: 0)
            )
        ])
        let decisionsPath = directory.appendingPathComponent(".swiftinfer/decisions.json")
        try DecisionsLoader.write(decisions, to: decisionsPath)

        let recording = RecordingOutput()
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Drift.run(
            directory: target,
            output: recording,
            diagnostics: diagnostics
        )
        #expect(diagnostics.lines.filter { $0.hasPrefix("warning: drift:") }.isEmpty)
        #expect(recording.lines.contains("No drift detected."))
    }

    @Test
    func driftLineMatchesByteStableShape() throws {
        let directory = try makeFixtureDirectory(name: "DriftLineGolden")
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("// swift-tools-version: 6.1\n".utf8).write(
            to: directory.appendingPathComponent("Package.swift")
        )
        let target = try makeTarget(in: directory, contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        let diagnostics = RecordingDiagnosticOutput()
        try SwiftInferCommand.Drift.run(
            directory: target,
            output: RecordingOutput(),
            diagnostics: diagnostics
        )
        let driftLine = try #require(diagnostics.lines.first { $0.hasPrefix("warning: drift:") })
        // §9 CI-annotation shape per DriftWarning.renderedLine — pin
        // every part except the dynamic identity hash and the
        // fixture-tmp-dir absolute path the SourceLocation file carries.
        #expect(driftLine.hasPrefix("warning: drift: new Strong suggestion 0x"))
        #expect(driftLine.contains(" for normalize(_:) at "))
        #expect(driftLine.hasSuffix(":2 — idempotence (no recorded decision)"))
    }

    // MARK: - Helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftCommandTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func makeTarget(in root: URL, contents: String) throws -> URL {
        let target = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Lib")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try contents.write(
            to: target.appendingPathComponent("Source.swift"),
            atomically: true,
            encoding: .utf8
        )
        return target
    }
}

// MARK: - Local recording stubs (file-private to avoid colliding with
// same-named helpers in DiscoverPipelineTests / InteractiveTriageTests).

private final class RecordingOutput: DiscoverOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    func write(_ text: String) {
        lines.append(text)
    }
}

private final class RecordingDiagnosticOutput: DiagnosticOutput, @unchecked Sendable {
    private(set) var lines: [String] = []
    func writeDiagnostic(_ text: String) {
        lines.append(text)
    }
}

private final class ScriptedPromptInput: PromptInput, @unchecked Sendable {
    private var remaining: [String]
    init(scriptedLines: [String]) {
        self.remaining = scriptedLines
    }
    func readLine() -> String? {
        guard !remaining.isEmpty else { return nil }
        return remaining.removeFirst()
    }
}
