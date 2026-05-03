import Foundation
import Testing
@testable import SwiftInferCLI

@Suite("Discover pipeline — --stats-only mode (M5.4) + --dry-run mode (M5.5 → M6.4)")
struct DiscoverPipelineStatsTests {

    // MARK: - --stats-only mode (M5.4)

    @Test("--stats-only swaps full explainability for the per-template summary block")
    func statsOnlyRendersSummaryBlock() throws {
        // normalize is a Strong-tier idempotence candidate; encode/decode
        // is a Likely-tier round-trip. Two templates, two tiers.
        let directory = try writeDPFixture(name: "StatsOnlyMode", contents: """
        struct MyType {}
        struct Codec {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
            func encode(_ value: MyType) -> Data {
                return Data()
            }
            func decode(_ data: Data) -> MyType {
                return MyType()
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            statsOnly: true,
            output: recording
        )
        // Header line + per-template lines, no per-suggestion blocks.
        #expect(recording.text.hasPrefix("2 suggestions across 2 templates."))
        #expect(recording.text.contains("idempotence"))
        #expect(recording.text.contains("round-trip"))
        #expect(recording.text.contains("(1 Strong)"))
        #expect(recording.text.contains("(1 Likely)"))
        // No explainability-block markers should appear in stats mode.
        #expect(!recording.text.contains("Why suggested:"))
        #expect(!recording.text.contains("[Suggestion]"))
    }

    @Test("--stats-only on an empty corpus renders the zero-suggestions sentinel")
    func statsOnlyEmptyCorpusRendersSentinel() throws {
        let directory = try makeDPFixtureDirectory(name: "StatsOnlyEmpty")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            statsOnly: true,
            output: recording
        )
        #expect(recording.text == "0 suggestions.")
    }

    // MARK: - --dry-run mode (M5.5 → M6.4)

    @Test("--dry-run without --interactive emits no placeholder diagnostic (M5.5 placeholder removed in M6.4)")
    func dryRunWithoutInteractiveIsSilent() throws {
        let directory = try writeDPFixture(name: "DryRunSilentNoInteractive", contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            dryRun: true,
            output: DPRecordingOutput(),
            diagnostics: diagnostics
        )
        // Without --interactive there are no writes to suppress, so
        // --dry-run is a silent no-op.
        #expect(!diagnostics.lines.contains { $0.contains("--dry-run") })
    }

    @Test("--dry-run produces byte-identical stdout to the no-flag path")
    func dryRunStdoutMatchesNoFlagPath() throws {
        // PRD §16 #1 already guarantees discover is read-only, so
        // --dry-run is currently a no-op for the no-interactive path.
        let directory = try writeDPFixture(name: "DryRunParity", contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let withoutFlag = DPRecordingOutput()
        let withFlag = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: withoutFlag,
            diagnostics: DPRecordingDiagnosticOutput()
        )
        try SwiftInferCommand.Discover.run(
            directory: directory,
            dryRun: true,
            output: withFlag,
            diagnostics: DPRecordingDiagnosticOutput()
        )
        #expect(withoutFlag.text == withFlag.text)
    }

    @Test("--dry-run unset emits no placeholder diagnostic")
    func dryRunUnsetIsSilent() throws {
        let directory = try writeDPFixture(name: "DryRunSilent", contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            output: DPRecordingOutput(),
            diagnostics: diagnostics
        )
        #expect(!diagnostics.lines.contains { $0.contains("--dry-run") })
    }
}
